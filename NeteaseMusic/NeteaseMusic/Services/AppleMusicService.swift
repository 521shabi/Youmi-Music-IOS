import Foundation
import MusicKit
import MediaPlayer

// MARK: - Apple Music 服务
@MainActor
class AppleMusicService: ObservableObject {
    static let shared = AppleMusicService()
    
    @Published var isAuthorized = false
    @Published var hasSubscription = false
    @Published var isPlaying = false
    @Published var currentSong: Song?
    @Published var playbackTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    
    private let player = ApplicationMusicPlayer.shared
    
    private init() {
        checkAuthorization()
    }
    
    // MARK: - 授权
    func checkAuthorization() {
        let status = MusicAuthorization.currentStatus
        isAuthorized = status == .authorized
    }
    
    func requestAuthorization() async -> Bool {
        let status = await MusicAuthorization.request()
        isAuthorized = status == .authorized
        
        if isAuthorized {
            await checkSubscription()
        }
        
        return isAuthorized
    }
    
    func checkSubscription() async {
        do {
            let subscription = try await MusicSubscription.current
            hasSubscription = subscription.canPlayCatalogContent
        } catch {
            hasSubscription = false
        }
    }
    
    // MARK: - 搜索
    func searchSongs(term: String, limit: Int = 25) async throws -> [Song] {
        var request = MusicCatalogSearchRequest(term: term, types: [Song.self])
        request.limit = limit
        let response = try await request.response()
        return Array(response.songs)
    }
    
    func searchPlaylists(term: String, limit: Int = 25) async throws -> MusicItemCollection<Playlist> {
        var request = MusicCatalogSearchRequest(term: term, types: [Playlist.self])
        request.limit = limit
        let response = try await request.response()
        return response.playlists
    }
    
    // MARK: - 获取推荐内容
    func getRecommendations() async throws -> [MusicPersonalRecommendation] {
        let request = MusicPersonalRecommendationsRequest()
        let response = try await request.response()
        return Array(response.recommendations)
    }
    
    func getCharts() async throws -> [MusicCatalogChart<Song>] {
        var request = MusicCatalogChartsRequest(kinds: [.mostPlayed], types: [Song.self])
        request.limit = 50
        let response = try await request.response()
        return response.songCharts
    }
    
    // MARK: - 用户资料库
    func getLibrarySongs(limit: Int = 100) async throws -> [Song] {
        var request = MusicLibraryRequest<Song>()
        request.limit = limit
        let response = try await request.response()
        return Array(response.items)
    }

    func getAllLibrarySongs(batchSize: Int = 100) async throws -> [Song] {
        var request = MusicLibraryRequest<Song>()
        request.limit = batchSize
        let response = try await request.response()

        var collection = response.items
        var songs = Array(collection)

        while let next = try await collection.nextBatch(limit: batchSize) {
            songs.append(contentsOf: next)
            collection = next
        }

        return songs
    }
    
    func getAllLibraryAlbums(batchSize: Int = 100) async throws -> [MusicKit.Album] {
        var request = MusicLibraryRequest<MusicKit.Album>()
        request.limit = batchSize
        let response = try await request.response()
        
        var collection = response.items
        var albums = Array(collection)
        
        while let next = try await collection.nextBatch(limit: batchSize) {
            albums.append(contentsOf: next)
            collection = next
        }
        
        return albums
    }
    
    func getAllLibraryArtists(batchSize: Int = 100) async throws -> [MusicKit.Artist] {
        var request = MusicLibraryRequest<MusicKit.Artist>()
        request.limit = batchSize
        let response = try await request.response()
        
        var collection = response.items
        var artists = Array(collection)
        
        while let next = try await collection.nextBatch(limit: batchSize) {
            artists.append(contentsOf: next)
            collection = next
        }
        
        return artists
    }
    
    func getLibraryPlaylists(limit: Int = 50) async throws -> MusicItemCollection<Playlist> {
        var request = MusicLibraryRequest<Playlist>()
        request.limit = limit
        let response = try await request.response()
        return response.items
    }
    
    func getAllLibraryPlaylists(batchSize: Int = 100) async throws -> [Playlist] {
        var request = MusicLibraryRequest<Playlist>()
        request.limit = batchSize
        let response = try await request.response()
        
        var collection = response.items
        var playlists = Array(collection)
        
        while let next = try await collection.nextBatch(limit: batchSize) {
            playlists.append(contentsOf: next)
            collection = next
        }
        
        return playlists
    }
    
    func getAlbumTracks(album: MusicKit.Album) async throws -> [MusicKit.Track] {
        let detailedAlbum = try await album.with([.tracks])
        if let tracks = detailedAlbum.tracks {
            return Array(tracks)
        }
        return []
    }
    
    func getPlaylistTracks(playlist: Playlist) async throws -> [MusicKit.Track] {
        let detailedPlaylist = try await playlist.with([.tracks])
        if let tracks = detailedPlaylist.tracks {
            return Array(tracks)
        }
        return []
    }
    
    // MARK: - 播放控制
    func play(song: Song) async throws {
        player.queue = [song]
        try await player.play()
        currentSong = song
        isPlaying = true
    }
    
    func play(songs: [Song], startingAt index: Int = 0) async throws {
        guard !songs.isEmpty, index < songs.count else { return }
        player.queue = ApplicationMusicPlayer.Queue(for: songs, startingAt: songs[index])
        try await player.play()
        currentSong = songs[index]
        isPlaying = true
    }
    
    func togglePlayPause() {
        if player.state.playbackStatus == .playing {
            player.pause()
            isPlaying = false
        } else {
            Task {
                try? await player.play()
                isPlaying = true
            }
        }
    }
    
    func pause() {
        player.pause()
        isPlaying = false
    }
    
    func skipToNext() async throws {
        try await player.skipToNextEntry()
        updateCurrentSong()
    }
    
    func skipToPrevious() async throws {
        try await player.skipToPreviousEntry()
        updateCurrentSong()
    }
    
    func seek(to time: TimeInterval) {
        player.playbackTime = time
    }
    
    private func updateCurrentSong() {
        if let entry = player.queue.currentEntry,
           case .song(let song) = entry.item {
            currentSong = song
            duration = song.duration ?? 0
        }
    }
}
