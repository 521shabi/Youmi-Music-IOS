import Foundation
import AVFoundation
import MediaPlayer
import Combine
import UIKit

// MARK: - 播放模式
enum PlayMode: String, CaseIterable {
    case order = "顺序播放"
    case random = "随机播放"
    case repeatOne = "单曲循环"
    
    var icon: String {
        switch self {
        case .order: return "repeat"
        case .random: return "shuffle"
        case .repeatOne: return "repeat.1"
        }
    }
}

// MARK: - 缓冲状态
enum BufferingState: Equatable {
    case idle
    case buffering(progress: Double)  // 0-1
    case ready
    case failed(String)
    
    var isBuffering: Bool {
        if case .buffering = self { return true }
        return false
    }
}

// MARK: - 播放器错误
enum AudioPlayerError: Error, LocalizedError {
    case invalidURL
    case networkError(String)
    case playbackFailed(String)
    case noAvailableSource
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "无效的播放链接"
        case .networkError(let msg):
            return "网络错误: \(msg)"
        case .playbackFailed(let msg):
            return "播放失败: \(msg)"
        case .noAvailableSource:
            return "暂无可用音源"
        }
    }
}

// MARK: - 歌曲URL响应
struct SongUrlResponse: Codable {
    let code: Int
    let data: [SongUrlData]?
}

struct SongUrlData: Codable {
    let id: Int
    let url: String?
    let br: Int?          // 比特率
    let size: Int?        // 文件大小
    let type: String?     // 文件类型
    let level: String?    // 音质等级
}

// MARK: - 音频播放器
class AudioPlayer: ObservableObject {
    static let shared = AudioPlayer()
    
    // MARK: - Published 属性
    @Published var currentTrack: Track?
    @Published var isPlaying = false
    @Published var isLoading = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var playlist: [Track] = []
    @Published var currentIndex: Int = 0
    @Published var playMode: PlayMode = .order
    @Published var actualQuality: String = ""  // 实际获取到的音质
    @Published var bufferingState: BufferingState = .idle
    @Published var lastError: AudioPlayerError?
    @Published var currentLocalTrack: LocalTrack?  // 当前播放的本地歌曲
    @Published var isPlayingLocal: Bool = false    // 是否在播放本地歌曲
    
    // MARK: - 回调
    var onTimeUpdate: ((Double) -> Void)?
    var onError: ((AudioPlayerError) -> Void)?
    
    // MARK: - 私有属性
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var timeObserver: Any?
    private var bufferObserver: NSKeyValueObservation?
    private var cancellables = Set<AnyCancellable>()
    private let musicService = MusicService.shared
    private let sourceConfig = MusicSourceConfig.shared
    private let songCache = SongCacheService.shared
    
    // 预加载缓存
    private var preloadedURLs: [Int: String] = [:]
    private let preloadQueue = DispatchQueue(label: "audioPlayer.preload", qos: .utility)
    private var preloadTasks: [Int: Task<Void, Never>] = [:]  // 预加载任务管理
    
    // 动态封面预加载任务
    private var dynamicCoverTask: Task<Void, Never>?

    // 重试配置
    private let maxRetryCount = 3
    private var currentRetryCount = 0
    
    // MARK: - 初始化
    private init() {
        setupAudioSession()
        setupRemoteCommandCenter()
        setupNotifications()
        
        // 启动时清理过期缓存
        songCache.cleanExpired()
        
        // 一次性清理旧的 1:1 动态封面缓存（升级到 3:4 版本后）
        migrateAnimatedArtworkCacheIfNeeded()
        
        // 恢复上次播放的歌曲（仅恢复信息，不自动播放）
        restoreLastPlayedTrack()
    }
    
    /// 迁移动态封面缓存（一次性清理旧的 1:1 缓存）
    private func migrateAnimatedArtworkCacheIfNeeded() {
        let migrationKey = "AnimatedArtworkMigratedTo3x4_v1"
        
        // 如果已经迁移过，跳过
        guard !UserDefaults.standard.bool(forKey: migrationKey) else {
            return
        }
        
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let animatedArtworkDir = cacheDir.appendingPathComponent("AnimatedArtwork", isDirectory: true)
        
        do {
            if FileManager.default.fileExists(atPath: animatedArtworkDir.path) {
                try FileManager.default.removeItem(at: animatedArtworkDir)
                #if DEBUG
                print("✅ 已清理旧的动态封面缓存（升级到 3:4）")
                #endif
            }
            // 清理统一缓存
            DynamicCoverCache.shared.clearAll()
        } catch {
            #if DEBUG
            print(" 清理动态封面缓存失败: \(error.localizedDescription)")
            #endif
        }
        
        // 标记已迁移
        UserDefaults.standard.set(true, forKey: migrationKey)
    }
    
    /// 恢复上次播放的歌曲
    private func restoreLastPlayedTrack() {
        if let lastTrack = LocalStorageService.shared.getLastPlayedTrack() {
            currentTrack = lastTrack
            // 添加到播放列表以便后续操作
            if playlist.isEmpty {
                playlist = [lastTrack]
                currentIndex = 0
            }
        }
    }
    
    // MARK: - 音频会话设置
    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print(" 音频会话设置失败: \(error)")
        }
    }
    
    // MARK: - 远程控制中心
    private func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.play()
            return .success
        }
        
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }
        
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            self?.playNext()
            return .success
        }
        
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            self?.playPrevious()
            return .success
        }
        
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            if let positionEvent = event as? MPChangePlaybackPositionCommandEvent {
                self?.seek(to: positionEvent.positionTime)
            }
            return .success
        }
    }
    
    // MARK: - 通知监听
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }
    
    @objc private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        switch type {
        case .began:
            pause()
        case .ended:
            if let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    play()
                }
            }
        @unknown default:
            break
        }
    }
    
    @objc private func handleRouteChange(_ notification: Notification) {
        guard let info = notification.userInfo,
              let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        
        if reason == .oldDeviceUnavailable {
            pause()
        }
    }
    
    // MARK: - 播放控制
    
    /// 播放指定歌曲（带重试和缓冲状态）
    func play(track: Track) async {
        print("🎵 play(track:) 被调用: \(track.name)")
        
        await MainActor.run {
            isLoading = true
            bufferingState = .buffering(progress: 0)
            currentTrack = track
            currentLocalTrack = nil
            isPlayingLocal = false
            lastError = nil
            currentRetryCount = 0
        }
        
        // 添加到播放历史
        LocalStorageService.shared.addToHistory(track)
        
        // 保存为上次播放的歌曲
        LocalStorageService.shared.saveLastPlayedTrack(track)
        
        // 立即开始预加载动态封面（不等待结果）
        preloadDynamicCover(for: track)
        
        await playWithRetry(track: track)
    }
    
    /// 播放本地歌曲
    func play(localTrack: LocalTrack) async {
        await MainActor.run {
            isLoading = true
            bufferingState = .buffering(progress: 0)
            currentLocalTrack = localTrack
            currentTrack = localTrack.toTrack()
            isPlayingLocal = true
            lastError = nil
        }
        
        // 检查文件是否存在
        guard FileManager.default.fileExists(atPath: localTrack.fileURL.path) else {
            await MainActor.run {
                isLoading = false
                lastError = .playbackFailed("文件不存在")
                bufferingState = .failed("文件不存在")
            }
            return
        }
        
        await MainActor.run {
            bufferingState = .buffering(progress: 0.5)
        }
        
        // 设置播放器（本地文件）
        await setupLocalPlayer(with: localTrack.fileURL, track: localTrack)
    }
    
    /// 设置本地文件播放器
    private func setupLocalPlayer(with url: URL, track: LocalTrack) async {
        await MainActor.run {
            // 移除旧的观察者
            cleanupObservers()
            
            // 本地文件不需要请求头
            let asset = AVURLAsset(url: url)
            playerItem = AVPlayerItem(asset: asset)
            player = AVPlayer(playerItem: playerItem)
            
            // 添加时间观察者
            let interval = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
            timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
                guard let self = self else { return }
                let seconds = CMTimeGetSeconds(time)
                if seconds.isFinite {
                    self.currentTime = seconds
                    self.onTimeUpdate?(seconds)
                }
            }
            
            // 监听播放结束
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(playerDidFinishPlaying),
                name: .AVPlayerItemDidPlayToEndTime,
                object: playerItem
            )
            
            // 监听播放状态
            playerItem?.publisher(for: \.status)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] status in
                    guard let self = self else { return }
                    switch status {
                    case .readyToPlay:
                        self.isLoading = false
                        self.bufferingState = .ready
                        if let duration = self.playerItem?.duration {
                            let seconds = CMTimeGetSeconds(duration)
                            if seconds.isFinite {
                                self.duration = seconds
                            }
                        }
                    case .failed:
                        self.isLoading = false
                        self.bufferingState = .failed("播放失败")
                    default:
                        break
                    }
                }
                .store(in: &cancellables)
            
            // 开始播放
            player?.play()
            isPlaying = true
            isLoading = false
            
            // 更新锁屏信息（本地歌曲）
            updateLocalNowPlayingInfo(track: track)
        }
    }
    
    /// 更新本地歌曲锁屏信息
    private func updateLocalNowPlayingInfo(track: LocalTrack) {
        var info = [String: Any]()
        
        info[MPMediaItemPropertyTitle] = track.displayTitle
        info[MPMediaItemPropertyArtist] = track.artistName
        info[MPMediaItemPropertyAlbumTitle] = track.albumName
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        
        // 设置封面
        if let artworkImage = track.artworkImage {
            let artwork = MPMediaItemArtwork(boundsSize: artworkImage.size) { _ in artworkImage }
            info[MPMediaItemPropertyArtwork] = artwork
        }
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
    
    /// 设置本地歌曲播放列表
    func setLocalPlaylist(_ tracks: [LocalTrack], startAt index: Int) {
        // 将本地歌曲转换为 Track 用于播放列表管理
        playlist = tracks.map { $0.toTrack() }
        currentIndex = index
        if index < tracks.count {
            Task {
                await play(localTrack: tracks[index])
            }
        }
    }
    
    /// 带重试的播放逻辑
    private func playWithRetry(track: Track) async {
        do {
            // 获取歌曲URL（优先使用缓存）
            let urlString = try await getSongUrl(id: track.id)
            
            guard let url = URL(string: urlString) else {
                throw AudioPlayerError.invalidURL
            }
            
            await MainActor.run {
                bufferingState = .buffering(progress: 0.3)
            }
            
            await setupPlayer(with: url, track: track)
            
        } catch {
            await handlePlaybackError(error, track: track)
        }
    }
    
    /// 设置播放器
    private func setupPlayer(with url: URL, track: Track) async {
        #if DEBUG
        print("🎶 setupPlayer 被调用: \(track.name)")
        #endif
        
        await MainActor.run {
            // 移除旧的观察者
            cleanupObservers()
            
            // 创建带请求头的 AVURLAsset（解决网易云音乐防盗链问题）
            let headers = [
                "Referer": "https://music.163.com/",
                "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 CloudMusic/1.0",
                "Origin": "https://music.163.com"
            ]
            let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
            playerItem = AVPlayerItem(asset: asset)
            player = AVPlayer(playerItem: playerItem)
            
            // 设置缓冲策略
            playerItem?.preferredForwardBufferDuration = 10  // 预缓冲10秒
            
            // 添加时间观察者
            let interval = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
            timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
                guard let self = self else { return }
                let seconds = CMTimeGetSeconds(time)
                if seconds.isFinite {
                    self.currentTime = seconds
                    self.onTimeUpdate?(seconds)
                }
            }
            
            // 监听缓冲进度
            bufferObserver = playerItem?.observe(\.loadedTimeRanges, options: [.new]) { [weak self] item, _ in
                guard let self = self else { return }
                self.updateBufferProgress(item: item)
            }
            
            // 监听播放结束
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(playerDidFinishPlaying),
                name: .AVPlayerItemDidPlayToEndTime,
                object: playerItem
            )
            
            // 监听播放失败
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(playerDidFail),
                name: .AVPlayerItemFailedToPlayToEndTime,
                object: playerItem
            )
            
            // 监听播放状态
            playerItem?.publisher(for: \.status)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] status in
                    guard let self = self else { return }
                    switch status {
                    case .readyToPlay:
                        self.isLoading = false
                        self.bufferingState = .ready
                        if let duration = self.playerItem?.duration {
                            let seconds = CMTimeGetSeconds(duration)
                            if seconds.isFinite {
                                self.duration = seconds
                            }
                        }
                    case .failed:
                        if let error = self.playerItem?.error {
                            self.handlePlaybackFailure(error: error)
                        }
                    default:
                        break
                    }
                }
                .store(in: &cancellables)
            
            // 开始播放
            player?.play()
            isPlaying = true
            isLoading = false
            
            // 更新锁屏信息
            updateNowPlayingInfo()
            
            // 批量预加载后续歌曲
            batchPreloadNextTracks()
        }
    }
    
    /// 更新缓冲进度
    private func updateBufferProgress(item: AVPlayerItem) {
        guard let timeRange = item.loadedTimeRanges.first?.timeRangeValue else { return }
        let bufferedTime = CMTimeGetSeconds(timeRange.start) + CMTimeGetSeconds(timeRange.duration)
        let duration = CMTimeGetSeconds(item.duration)
        
        if duration > 0 {
            let progress = min(bufferedTime / duration, 1.0)
            DispatchQueue.main.async {
                if case .buffering = self.bufferingState {
                    self.bufferingState = .buffering(progress: progress)
                }
            }
        }
    }
    
    /// 处理播放错误（带重试）
    private func handlePlaybackError(_ error: Error, track: Track) async {
        currentRetryCount += 1
        
        if currentRetryCount <= maxRetryCount {
            #if DEBUG
            print(" 播放失败，重试 \(currentRetryCount)/\(maxRetryCount): \(error.localizedDescription)")
            #endif
            
            // 清除该歌曲的 URL 缓存（可能已过期）
            songCache.clearUrlCache(songId: track.id)
            preloadedURLs.removeValue(forKey: track.id)
            
            // 等待后重试（指数退避）
            let delay = pow(2.0, Double(currentRetryCount - 1))
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            
            await playWithRetry(track: track)
        } else {
            // 重试次数用尽
            await MainActor.run {
                isLoading = false
                let playerError = AudioPlayerError.playbackFailed(error.localizedDescription)
                lastError = playerError
                bufferingState = .failed(error.localizedDescription)
                onError?(playerError)
            }
            
            #if DEBUG
            print(" 播放失败（已达最大重试次数）: \(error)")
            #endif
        }
    }
    
    /// 播放失败处理（触发重试）
    private func handlePlaybackFailure(error: Error) {
        #if DEBUG
        print(" 播放器错误: \(error)")
        #endif
        
        // 如果有当前歌曲，尝试重试
        if let track = currentTrack {
            Task {
                await handlePlaybackError(error, track: track)
            }
        } else {
            let playerError = AudioPlayerError.playbackFailed(error.localizedDescription)
            lastError = playerError
            bufferingState = .failed(error.localizedDescription)
            onError?(playerError)
        }
    }
    
    @objc private func playerDidFail(_ notification: Notification) {
        if let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error {
            handlePlaybackFailure(error: error)
        }
    }
    
    /// 清理观察者
    private func cleanupObservers() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        bufferObserver?.invalidate()
        bufferObserver = nil
        cancellables.removeAll()
    }
    
    @objc private func playerDidFinishPlaying() {
        switch playMode {
        case .order:
            playNext()
        case .random:
            playRandomNext()
        case .repeatOne:
            seek(to: 0)
            play()
        }
    }
    
    /// 播放
    func play() {
        player?.play()
        isPlaying = true
        updateNowPlayingInfo()
    }
    
    /// 暂停
    func pause() {
        player?.pause()
        isPlaying = false
        updateNowPlayingInfo()
    }
    
    /// 切换播放/暂停
    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            // 如果 player 为 nil 但有 currentTrack（恢复的歌曲），则开始播放
            if player == nil, let track = currentTrack {
                Task {
                    await play(track: track)
                }
            } else {
                play()
            }
        }
    }
    
    /// 播放下一首
    func playNext() {
        // 如果播放列表为空但有 currentTrack，尝试从历史记录播放下一首
        if playlist.isEmpty {
            if let currentTrack = currentTrack {
                // 从播放历史中获取下一首
                let history = LocalStorageService.shared.getHistory()
                if let currentIndex = history.firstIndex(where: { $0.id == currentTrack.id }),
                   currentIndex + 1 < history.count {
                    let nextTrack = history[currentIndex + 1]
                    Task {
                        await play(track: nextTrack)
                    }
                } else if let firstTrack = history.first, firstTrack.id != currentTrack.id {
                    // 如果当前歌曲不在历史中，播放历史第一首
                    Task {
                        await play(track: firstTrack)
                    }
                }
            }
            return
        }
        
        let nextIndex: Int
        switch playMode {
        case .order, .repeatOne:
            nextIndex = (currentIndex + 1) % playlist.count
        case .random:
            nextIndex = Int.random(in: 0..<playlist.count)
        }
        
        currentIndex = nextIndex
        Task {
            await play(track: playlist[nextIndex])
        }
    }
    
    /// 播放上一首
    func playPrevious() {
        guard !playlist.isEmpty else { return }
        
        let prevIndex: Int
        switch playMode {
        case .order, .repeatOne:
            prevIndex = (currentIndex - 1 + playlist.count) % playlist.count
        case .random:
            prevIndex = Int.random(in: 0..<playlist.count)
        }
        
        currentIndex = prevIndex
        Task {
            await play(track: playlist[prevIndex])
        }
    }
    
    /// 随机播放下一首
    private func playRandomNext() {
        guard !playlist.isEmpty else { return }
        let randomIndex = Int.random(in: 0..<playlist.count)
        currentIndex = randomIndex
        Task {
            await play(track: playlist[randomIndex])
        }
    }
    
    /// 跳转到指定时间
    func seek(to time: Double) {
        let cmTime = CMTime(seconds: time, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player?.seek(to: cmTime)
        currentTime = time
        updateNowPlayingInfo()
    }
    
    /// 切换播放模式
    func togglePlayMode() {
        switch playMode {
        case .order:
            playMode = .random
        case .random:
            playMode = .repeatOne
        case .repeatOne:
            playMode = .order
        }
    }
    
    /// 设置播放列表并开始播放
    func setPlaylist(_ tracks: [Track], startAt index: Int) {
        playlist = tracks
        currentIndex = index
        if index < tracks.count {
            Task {
                await play(track: tracks[index])
            }
        }
    }
    
    /// 将歌曲添加到当前播放位置的下一首
    func playNext(track: Track) {
        if playlist.isEmpty {
            playlist = [track]
            currentIndex = 0
        } else {
            let insertIndex = currentIndex + 1
            if insertIndex >= playlist.count {
                playlist.append(track)
            } else {
                playlist.insert(track, at: insertIndex)
            }
        }
    }
    
    /// 将歌曲添加到播放列表末尾
    func addToQueue(track: Track) {
        playlist.append(track)
        // 如果当前没有播放，设置索引
        if currentTrack == nil && !playlist.isEmpty {
            currentIndex = playlist.count - 1
        }
    }
    
    // MARK: - 锁屏信息
    // 缓存锁屏封面以避免重复加载
    private var nowPlayingArtworkCache: [String: MPMediaItemArtwork] = [:]
    
    private func updateNowPlayingInfo() {
        print("📱 updateNowPlayingInfo 被调用, currentTrack: \(currentTrack?.name ?? "nil")")
        
        var info = [String: Any]()
        
        if let track = currentTrack {
            info[MPMediaItemPropertyTitle] = track.name
            info[MPMediaItemPropertyArtist] = track.artistName
            info[MPMediaItemPropertyAlbumTitle] = track.albumName
        }
        
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        
        // 优化：使用缓存加载封面图片
        if let coverUrl = currentTrack?.coverUrl, let url = URL(string: coverUrl) {
            // 先检查锁屏封面缓存
            if let cachedArtwork = nowPlayingArtworkCache[coverUrl] {
                info[MPMediaItemPropertyArtwork] = cachedArtwork
            } else {
                // 异步加载封面（优先使用ImageCache）
                loadNowPlayingArtwork(from: url, coverUrl: coverUrl)
            }
        }
        
        // iOS 26+ (内部版本 iOS 19.0): 设置动态封面
        if #available(iOS 19.0, *), let track = currentTrack {
            print("🎬 尝试设置动态封面 (iOS 26+), track: \(track.name)")
            setAnimatedArtwork(for: track, info: &info)
        } else {
            print("⚠️ 当前系统不支持动态封面 API (iOS < 26)")
        }
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
    
    // MARK: - iOS 26+ 动态封面支持
    
    /// iOS 26+ (内部版本 iOS 19.0): 设置锁屏动态封面
    /// 使用 MPMediaItemAnimatedArtwork API 在锁屏显示动态专辑封面
    ///
    /// 当用户在锁屏点击封面时，系统会自动播放动态封面视频
    /// 类似 QQ音乐、Apple Music 的全屏动态封面效果
    @available(iOS 19.0, *)
    private func setAnimatedArtwork(for track: Track, info: inout [String: Any]) {
        print("🎬 setAnimatedArtwork 被调用")
        
        // 检查平台支持的动态封面 keys
        let supportedKeys = MPNowPlayingInfoCenter.supportedAnimatedArtworkKeys
        print(" 支持的动态封面 keys: \(supportedKeys)")
        
        // 优先使用 3:4，如果不支持则尝试 1:1
        let animatedArtworkKey: String
        if supportedKeys.contains(MPNowPlayingInfoProperty3x4AnimatedArtwork) {
            animatedArtworkKey = MPNowPlayingInfoProperty3x4AnimatedArtwork
            #if DEBUG
            print(" 使用 3:4 动态封面")
            #endif
        } else if supportedKeys.contains(MPNowPlayingInfoProperty1x1AnimatedArtwork) {
            animatedArtworkKey = MPNowPlayingInfoProperty1x1AnimatedArtwork
            #if DEBUG
            print(" 使用 1:1 动态封面")
            #endif
        } else {
            #if DEBUG
            print(" 当前平台不支持动态封面")
            #endif
            return
        }
        
        // 检查是否有预加载的动态封面 URL
        guard let videoUrlString = getMasterUrlCached(for: track.id) else {
            print("⚠️ 尚无预加载的动态封面 URL (trackId: \(track.id))")
            return
        }
        
        print("✅ 已获取动态封面 URL: \(videoUrlString.suffix(60))")
        
        let trackId = track.id
        let coverUrl = track.coverUrl
        let remoteVideoUrlString = videoUrlString
        
        // 创建唯一的 artworkID
        let artworkID = "track_\(trackId)_animated"
        
        // 创建 MPMediaItemAnimatedArtwork
        let animatedArtwork = MPMediaItemAnimatedArtwork(
            artworkID: artworkID,
            previewImageRequestHandler: { [weak self] requestedSize, completion in
                print("🖼️ 系统请求预览图, size: \(requestedSize)")
                
                // 返回静态封面作为预览图
                guard let coverUrl = coverUrl,
                      let url = URL(string: coverUrl) else {
                    #if DEBUG
                    print(" 无封面 URL")
                    #endif
                    completion(nil)
                    return
                }
                
                // 异步加载并裁剪为请求的宽高比
                Task {
                    do {
                        // 下载原图
                        let (data, _) = try await URLSession.shared.data(from: url)
                        guard let originalImage = UIImage(data: data) else {
                            completion(nil)
                            return
                        }
                        
                        // 裁剪为请求的宽高比 (3:4)
                        let croppedImage = self?.cropImageToAspectRatio(
                            originalImage,
                            targetWidth: requestedSize.width,
                            targetHeight: requestedSize.height
                        )
                        
                        print("✅ 预览图加载成功")
                        completion(croppedImage)
                    } catch {
                        #if DEBUG
                        print(" 预览图加载失败: \(error.localizedDescription)")
                        #endif
                        completion(nil)
                    }
                }
            },
            videoAssetFileURLRequestHandler: { [weak self] requestedSize, completion in
                print("🎥 系统请求动态封面视频, size: \(requestedSize), trackId: \(trackId)")
                
                guard let self = self else {
                    #if DEBUG
                    print("❌ self 已释放")
                    #endif
                    completion(nil)
                    return
                }
                
                // 检查是否已下载到本地（锁屏时应该已经预下载完成）
                if let localURL = self.getLocalFileCached(for: trackId) {
                    #if DEBUG
                    print("✅ 使用已缓存的动态封面: \(localURL.lastPathComponent)")
                    #endif
                    
                    // 验证文件是否存在
                    if FileManager.default.fileExists(atPath: localURL.path) {
                        print("✅ 文件存在，返回给系统")
                        completion(localURL)
                    } else {
                        print("⚠️ 缓存记录存在但文件不存在，清除缓存并重新下载")
                        // 清除无效的缓存记录
                        DynamicCoverCache.shared.clearLocalFile(for: trackId)
                        // 继续下载
                        self.downloadAndCacheVideo(remoteVideoUrlString, trackId, completion)
                    }
                    return
                }
                
                #if DEBUG
                print("📥 未找到本地缓存，开始下载动态封面视频...")
                #endif
                
                // 异步下载视频到本地
                self.downloadAndCacheVideo(remoteVideoUrlString, trackId, completion)
            }
        )
        
        // 设置动态封面
        info[animatedArtworkKey] = animatedArtwork
        
        print("✅ 已设置锁屏动态封面到 NowPlayingInfo: \(track.name)")
    }
    
    /// 下载并缓存视频的辅助方法（用于 videoAssetFileURLRequestHandler）
    @available(iOS 19.0, *)
    private func downloadAndCacheVideo(_ remoteVideoUrlString: String, _ trackId: Int, _ completion: @escaping (URL?) -> Void) {
        Task {
            do {
                let localURL = try await self.downloadAnimatedArtwork(
                    from: remoteVideoUrlString,
                    trackId: trackId
                )
                await MainActor.run {
                    self.cacheLocalFile(localURL, for: trackId)
                }
                #if DEBUG
                print("✅ 动态封面视频已就绪: \(localURL.lastPathComponent)")
                #endif
                completion(localURL)
            } catch {
                #if DEBUG
                print("❌ 动态封面下载失败: \(error)")
                #endif
                completion(nil)
            }
        }
    }
    
    /// 下载动态封面视频到本地
    /// 支持 HLS 流和普通视频文件
    @available(iOS 19.0, *)
    private func downloadAnimatedArtwork(from urlString: String, trackId: Int) async throws -> URL {
        // 创建本地文件路径
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let animatedArtworkDir = cacheDir.appendingPathComponent("AnimatedArtwork", isDirectory: true)
        
        // 确保目录存在
        try FileManager.default.createDirectory(at: animatedArtworkDir, withIntermediateDirectories: true)
        
        let basePath = animatedArtworkDir.appendingPathComponent("track_\(trackId)")
        let tsURL = basePath.appendingPathExtension("ts")
        let mp4URL = basePath.appendingPathExtension("mp4")
        
        // 检查缓存：优先检查 .ts，然后检查 .mp4
        if FileManager.default.fileExists(atPath: tsURL.path) {
            #if DEBUG
            print(" 动态封面使用缓存: \(tsURL.lastPathComponent)")
            #endif
            return tsURL
        }
        
        if FileManager.default.fileExists(atPath: mp4URL.path) {
            #if DEBUG
            print(" 动态封面使用缓存: \(mp4URL.lastPathComponent)")
            #endif
            return mp4URL
        }
        
        // 检查是否是 HLS 流
        if urlString.contains(".m3u8") {
            // HLS 流：下载并合并 ts 分段
            return try await downloadHLSSegment(masterUrl: urlString, to: basePath)
        } else {
            // 普通视频文件：直接下载
            guard let remoteURL = URL(string: urlString) else {
                throw AudioPlayerError.invalidURL
            }
            let (tempURL, _) = try await URLSession.shared.download(from: remoteURL)
            
            // 移动到目标位置
            if FileManager.default.fileExists(atPath: mp4URL.path) {
                try FileManager.default.removeItem(at: mp4URL)
            }
            try FileManager.default.moveItem(at: tempURL, to: mp4URL)
            
            #if DEBUG
            print(" 动态封面已下载: \(mp4URL.lastPathComponent)")
            #endif
            
            return mp4URL
        }
    }
    
    /// 下载 HLS 分段文件（下载所有 ts 并合并）
    /// - Parameters:
    ///   - masterUrl: HLS master m3u8 URL
    ///   - basePath: 输出文件的基础路径（不带扩展名）
    @available(iOS 19.0, *)
    private func downloadHLSSegment(masterUrl: String, to basePath: URL) async throws -> URL {
        // Step 1: 获取已缓存的变体 URL，或解析 master m3u8
        var variantUrl: String?
        
        if let cached = HLSVariantCache.shared.getVariant(for: masterUrl) {
            variantUrl = cached
            #if DEBUG
            print("📥 使用缓存的 HLS 变体")
            #endif
        } else {
            // 解析 master m3u8
            guard let masterURL = URL(string: masterUrl) else {
                throw AudioPlayerError.invalidURL
            }
            let (masterData, _) = try await URLSession.shared.data(from: masterURL)
            guard let masterText = String(data: masterData, encoding: .utf8) else {
                throw AudioPlayerError.playbackFailed("无法解析 HLS 主播放列表")
            }
            
            // 使用 HLSParser 选择合适的变体（优先 3:4 宽高比）
            variantUrl = HLSParser.shared.selectVariant(
                from: masterText,
                baseUrl: masterUrl,
                strategy: .preferAspectRatio(width: 3, height: 4, maxPixels: 1620 * 2160)
            )
            
            // 缓存结果
            if let url = variantUrl {
                HLSVariantCache.shared.setVariant(url, for: masterUrl)
            }
        }
        
        guard let variantUrlString = variantUrl, let variantURL = URL(string: variantUrlString) else {
            throw AudioPlayerError.playbackFailed("无法获取 HLS 变体")
        }
        
        #if DEBUG
        print("📥 下载 HLS 变体: \(variantUrlString.suffix(60))")
        #endif
        
        // Step 2: 下载变体 m3u8 并解析 ts 分段
        let (variantData, _) = try await URLSession.shared.data(from: variantURL)
        guard let variantText = String(data: variantData, encoding: .utf8) else {
            throw AudioPlayerError.playbackFailed("无法解析 HLS 变体播放列表")
        }
        
        // 使用 HLSParser 提取所有 ts 文件 URL
        let tsUrls = HLSParser.shared.extractTSUrls(from: variantText, baseUrl: variantUrlString)
        
        guard !tsUrls.isEmpty else {
            throw AudioPlayerError.playbackFailed("无法找到 ts 分段")
        }
        
        #if DEBUG
        print("📥 共 \(tsUrls.count) 个 ts 分段需要下载")
        #endif
        
        // Step 3: 下载所有 ts 文件并合并
        var combinedData = Data()
        
        for (index, tsUrlString) in tsUrls.enumerated() {
            guard let tsURL = URL(string: tsUrlString) else { continue }
            
            #if DEBUG
            print("📥 下载分段 \(index + 1)/\(tsUrls.count)")
            #endif
            
            let (tsData, _) = try await URLSession.shared.data(from: tsURL)
            combinedData.append(tsData)
        }
        
        // Step 4: 保存合并后的 ts 文件
        let outputURL = basePath.appendingPathExtension("ts")
        
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        try combinedData.write(to: outputURL)
        
        #if DEBUG
        print("✅ 动态封面已下载: \(outputURL.lastPathComponent) (\(combinedData.count / 1024)KB)")
        #endif
        
        return outputURL
    }
    
    // MARK: - 缓存访问方法（使用 DynamicCoverCache）

    /// 获取歌曲的 master m3u8 URL
    private func getMasterUrlCached(for trackId: Int) -> String? {
        return DynamicCoverCache.shared.getMasterUrl(for: trackId)
    }

    /// 缓存歌曲的 master m3u8 URL
    private func cacheMasterUrl(_ url: String, for trackId: Int) {
        DynamicCoverCache.shared.cacheMasterUrl(url, for: trackId)
    }

    /// 获取歌曲的本地文件 URL
    private func getLocalFileCached(for trackId: Int) -> URL? {
        return DynamicCoverCache.shared.getLocalFile(for: trackId)
    }

    /// 缓存歌曲的本地文件 URL
    private func cacheLocalFile(_ fileUrl: URL, for trackId: Int) {
        DynamicCoverCache.shared.cacheLocalFile(fileUrl, for: trackId)
    }

    /// 裁剪图片为指定宽高比
    private func cropImageToAspectRatio(_ image: UIImage, targetWidth: CGFloat, targetHeight: CGFloat) -> UIImage? {
        let targetAspectRatio = targetWidth / targetHeight  // 3:4 = 0.75
        let imageAspectRatio = image.size.width / image.size.height
        
        var cropRect: CGRect
        
        if imageAspectRatio > targetAspectRatio {
            // 图片过宽，裁剪左右
            let newWidth = image.size.height * targetAspectRatio
            let xOffset = (image.size.width - newWidth) / 2
            cropRect = CGRect(x: xOffset, y: 0, width: newWidth, height: image.size.height)
        } else {
            // 图片过高，裁剪上下
            let newHeight = image.size.width / targetAspectRatio
            let yOffset = (image.size.height - newHeight) / 2
            cropRect = CGRect(x: 0, y: yOffset, width: image.size.width, height: newHeight)
        }
        
        // 执行裁剪
        guard let cgImage = image.cgImage,
              let croppedCGImage = cgImage.cropping(to: cropRect) else {
            return nil
        }
        
        // 缩放到目标尺寸
        let targetSize = CGSize(width: targetWidth, height: targetHeight)
        UIGraphicsBeginImageContextWithOptions(targetSize, false, 0)
        let croppedImage = UIImage(cgImage: croppedCGImage, scale: image.scale, orientation: image.imageOrientation)
        croppedImage.draw(in: CGRect(origin: .zero, size: targetSize))
        let finalImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return finalImage
    }
    
    /// 异步加载锁屏封面（优化：使用ImageCache，避免阻塞主线程）
    private func loadNowPlayingArtwork(from url: URL, coverUrl: String) {
        Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }
            
            // 优先从 ImageCache 获取
            let targetSize = CGSize(width: 300, height: 300)
            if let cachedImage = ImageCache.shared.getFromMemory(url, targetSize: targetSize) {
                await self.setNowPlayingArtwork(cachedImage, for: coverUrl)
                return
            }
            
            // 尝试从磁盘缓存获取
            if let diskImage = ImageCache.shared.getFromDisk(url, targetSize: targetSize) {
                await self.setNowPlayingArtwork(diskImage, for: coverUrl)
                return
            }
            
            // 网络加载（后台线程）
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                // 下采样优化
                if let image = ImageCache.shared.downsample(data: data, to: targetSize) {
                    // 保存到缓存
                    ImageCache.shared.saveToMemory(image, for: url, targetSize: targetSize)
                    ImageCache.shared.saveToDisk(data, for: url)
                    await self.setNowPlayingArtwork(image, for: coverUrl)
                }
            } catch {
                #if DEBUG
                print(" 锁屏封面加载失败: \(error.localizedDescription)")
                #endif
            }
        }
    }
    
    /// 设置锁屏封面（主线程）
    @MainActor
    private func setNowPlayingArtwork(_ image: UIImage, for coverUrl: String) {
        let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        nowPlayingArtworkCache[coverUrl] = artwork
        
        var updatedInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        updatedInfo[MPMediaItemPropertyArtwork] = artwork
        MPNowPlayingInfoCenter.default().nowPlayingInfo = updatedInfo
    }
    
    // MARK: - 获取歌曲URL（多级缓存）
    private func getSongUrl(id: Int) async throws -> String {
        let quality = sourceConfig.quality.rawValue
        
        // 1. 先检查内存预加载缓存
        if let cachedUrl = preloadedURLs[id] {
            #if DEBUG
            print(" 使用预加载缓存: \(id)")
            #endif
            return cachedUrl
        }
        
        // 2. 检查持久化缓存
        if let cachedUrl = songCache.getCachedUrl(songId: id, quality: quality) {
            // 同时放入内存缓存
            preloadedURLs[id] = cachedUrl
            return cachedUrl
        }
        
        // 3. 网络请求（GET API）
        #if DEBUG
        print(" 请求音质: \(quality)")
        #endif

        // GET API格式: /song?id=xxx&type=json&level=xxx
        guard let url = URL(string: "\(sourceConfig.apiURL)?id=\(id)&type=json&level=\(quality)") else {
            throw AudioPlayerError.invalidURL
        }

        #if DEBUG
        print(" 完整API请求: \(url.absoluteString)")
        #endif

        let (data, _) = try await URLSession.shared.data(from: url)

        #if DEBUG
        // 调试：打印原始API响应
        if let responseString = String(data: data, encoding: .utf8) {
            print(" API响应: \(responseString)")
        }
        #endif
        
        // 解析响应 - 格式: data.url
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let dataDict = json["data"] as? [String: Any],
           let resultUrl = dataDict["url"] as? String,
           !resultUrl.isEmpty {
            // 保存实际音质
            if let level = dataDict["level"] as? String {
                await MainActor.run {
                    self.actualQuality = level
                }
                #if DEBUG
                print(" 实际音质: \(level)")
                #endif
            }
            
            // 缓存结果
            preloadedURLs[id] = resultUrl
            songCache.cacheUrl(songId: id, url: resultUrl, quality: quality)
            
            return resultUrl
        }
        
        #if DEBUG
        // 调试：打印解析失败的详细信息
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            print(" 解析失败 - code: \(json["code"] ?? "unknown"), msg: \(json["msg"] ?? "unknown")")
        }
        #endif
        
        throw AudioPlayerError.noAvailableSource
    }
    
    // MARK: - 预加载（批量预加载优化）
    
    /// 批量预加载后续歌曲（默认预加载3首）
    private func batchPreloadNextTracks(count: Int = 3) {
        guard !playlist.isEmpty else { return }
        
        for offset in 1...count {
            let nextIndex = (currentIndex + offset) % playlist.count
            let nextTrack = playlist[nextIndex]
            preloadTrack(nextTrack)
        }
    }
    
    /// 预加载单首歌曲
    private func preloadTrack(_ track: Track) {
        let quality = sourceConfig.quality.rawValue
        
        // 已经预加载过则跳过
        if preloadedURLs[track.id] != nil { return }
        
        // 检查持久化缓存
        if let cachedUrl = songCache.getCachedUrl(songId: track.id, quality: quality) {
            preloadedURLs[track.id] = cachedUrl
            #if DEBUG
            print(" 预加载(缓存命中): \(track.name)")
            #endif
            return
        }
        
        // 取消已有的预加载任务
        preloadTasks[track.id]?.cancel()
        
        // 创建新的预加载任务
        let task = Task(priority: .utility) { [weak self] in
            guard let self = self else { return }

            do {
                // GET API格式: /song?id=xxx&type=json&level=xxx
                guard let url = URL(string: "\(self.sourceConfig.apiURL)?id=\(track.id)&type=json&level=\(quality)") else {
                    return
                }

                // 检查任务是否已取消
                if Task.isCancelled { return }

                let (data, _) = try await URLSession.shared.data(from: url)
                
                // 再次检查任务是否已取消
                if Task.isCancelled { return }
                
                // 解析响应 - 格式: data.url
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let dataDict = json["data"] as? [String: Any],
                   let resultUrl = dataDict["url"] as? String,
                   !resultUrl.isEmpty {
                    
                    // 缓存结果
                    await MainActor.run {
                        self.preloadedURLs[track.id] = resultUrl
                    }
                    self.songCache.cacheUrl(songId: track.id, url: resultUrl, quality: quality)
                    
                    #if DEBUG
                    print(" 预加载完成: \(track.name)")
                    #endif
                }
            } catch {
                if !Task.isCancelled {
                    #if DEBUG
                    print(" 预加载失败: \(track.name) - \(error.localizedDescription)")
                    #endif
                }
            }
            
            // 清理任务引用
            await MainActor.run {
                self.preloadTasks.removeValue(forKey: track.id)
            }
        }
        
        preloadTasks[track.id] = task
    }
    
    /// 预加载单首（兼容旧方法）
    private func preloadNextTrack() {
        batchPreloadNextTracks(count: 1)
    }
    
    // MARK: - 动态封面预加载
    
    /// 预加载动态封面（在点击歌曲时立即调用）
    private func preloadDynamicCover(for track: Track) {
        // 已经预加载过则跳过
        if getMasterUrlCached(for: track.id) != nil,
           getLocalFileCached(for: track.id) != nil { 
            return 
        }
        
        // 取消之前的预加载任务
        dynamicCoverTask?.cancel()
        
        let trackId = track.id
        
        dynamicCoverTask = Task(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            
            do {
                #if DEBUG
                print(" 开始预加载动态封面: \(track.name) - \(track.artistName)")
                #endif
                
                if let videoUrl = try await self.musicService.getAppleMusicAnimatedCover(
                    songName: track.name,
                    artistName: track.artistName
                ) {
                    // 缓存 master URL
                    await MainActor.run {
                        self.cacheMasterUrl(videoUrl, for: trackId)
                    }
                    
                    // 同时预加载 HLS 变体
                    HLSVariantCache.shared.preload(masterUrl: videoUrl)
                    
                    #if DEBUG
                    print(" 动态封面 URL 预加载完成: \(track.name)")
                    #endif
                    
                    // iOS 26+ (内部版本 iOS 19.0): 立即下载视频文件到本地（避免锁屏后无法下载）
                    if #available(iOS 19.0, *) {
                        do {
                            #if DEBUG
                            print(" 开始预下载动态封面视频文件")
                            #endif
                            
                            let localURL = try await self.downloadAnimatedArtwork(
                                from: videoUrl,
                                trackId: trackId
                            )
                            
                            await MainActor.run {
                                self.cacheLocalFile(localURL, for: trackId)
                            }
                            
                            #if DEBUG
                            print(" 动态封面视频文件预下载完成: \(localURL.lastPathComponent)")
                            #endif
                            
                            // 确保当前播放的仍是同一首歌，重新更新锁屏信息以应用动态封面
                            await MainActor.run {
                                if self.currentTrack?.id == trackId {
                                    self.updateNowPlayingInfo()
                                }
                            }
                        } catch {
                            if !Task.isCancelled {
                                #if DEBUG
                                print(" 动态封面视频文件预下载失败: \(error.localizedDescription)")
                                #endif
                            }
                        }
                    }
                } else {
                    #if DEBUG
                    print(" 未找到动态封面: \(track.name)")
                    #endif
                }
            } catch {
                if !Task.isCancelled {
                    #if DEBUG
                    print(" 动态封面预加载失败: \(error.localizedDescription)")
                    #endif
                }
            }
        }
    }
    
    /// 获取预加载的动态封面URL
    func getDynamicCoverURL(for trackId: Int) -> String? {
        return getMasterUrlCached(for: trackId)
    }

    /// 缓存动态封面URL，并触发视频文件预下载
    func cacheDynamicCoverURL(_ url: String, for trackId: Int) {
        cacheMasterUrl(url, for: trackId)
        
        // 强制输出日志（不受 DEBUG 条件限制）
        print("💾 cacheDynamicCoverURL 被调用: trackId=\(trackId), url=\(url.suffix(60))")
        
        // iOS 26+ (iOS 19.0): 立即开始预下载视频文件（避免锁屏后无法下载）
        if #available(iOS 19.0, *) {
            print("📱 iOS 19.0+ 检测通过，开始预下载流程")
            
            // 检查是否已经有本地文件缓存
            if getLocalFileCached(for: trackId) != nil {
                print("✅ 动态封面视频文件已缓存，跳过下载")
                return
            }
            
            print("📥 开始创建下载 Task...")
            
            // 开始后台下载
            Task(priority: .userInitiated) { [weak self] in
                guard let self = self else {
                    print("❌ self 已释放")
                    return
                }
                
                do {
                    print("📥 Task 开始执行: 下载动态封面视频文件 (trackId: \(trackId))")
                    
                    let localURL = try await self.downloadAnimatedArtwork(
                        from: url,
                        trackId: trackId
                    )
                    
                    await MainActor.run {
                        self.cacheLocalFile(localURL, for: trackId)
                    }
                    
                    print("✅ 动态封面视频文件预下载完成: \(localURL.lastPathComponent)")
                    
                    // 如果当前正在播放这首歌，更新锁屏信息
                    await MainActor.run {
                        if self.currentTrack?.id == trackId {
                            self.updateNowPlayingInfo()
                        }
                    }
                } catch {
                    print("❌ 动态封面视频文件预下载失败: \(error.localizedDescription)")
                }
            }
        } else {
            print("⚠️ iOS 版本 < 19.0，不支持动态封面预下载")
        }
    }

    /// 清除预加载缓存
    func clearPreloadCache() {
        // 取消所有预加载任务
        for (_, task) in preloadTasks {
            task.cancel()
        }
        preloadTasks.removeAll()
        preloadedURLs.removeAll()
        dynamicCoverTask?.cancel()
        
        // 清理动态封面缓存
        DynamicCoverCache.shared.clearAll()
        
        #if DEBUG
        print("🗑️ 预加载缓存已清除")
        #endif
    }
    
    /// 取消所有预加载任务
    func cancelAllPreloads() {
        for (_, task) in preloadTasks {
            task.cancel()
        }
        preloadTasks.removeAll()
    }
    
    deinit {
        cleanupObservers()
        cancelAllPreloads()
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - 辅助方法
    
    /// 获取缓冲进度（0-1）
    var bufferProgress: Double {
        if case .buffering(let progress) = bufferingState {
            return progress
        }
        return bufferingState == .ready ? 1.0 : 0.0
    }
    
    /// 重置错误状态
    func resetError() {
        lastError = nil
        bufferingState = .idle
    }
    
    /// 保存缓存到磁盘（App 进入后台时调用）
    func saveCacheToDisk() {
        songCache.saveToDisk()
    }
}
