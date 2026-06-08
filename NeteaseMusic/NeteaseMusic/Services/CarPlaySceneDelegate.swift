import Foundation
import CarPlay
import MediaPlayer

// MARK: - CarPlay Scene Delegate
class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    
    var interfaceController: CPInterfaceController?
    private let audioPlayer = AudioPlayer.shared
    private let musicService = MusicService.shared
    
    // MARK: - CPTemplateApplicationSceneDelegate
    
    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                   didConnect interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
        
        // 设置根模板
        let tabBarTemplate = createTabBarTemplate()
        interfaceController.setRootTemplate(tabBarTemplate, animated: true, completion: nil)
    }
    
    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                   didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        self.interfaceController = nil
    }
    
    // MARK: - 创建 Tab Bar 模板
    
    private func createTabBarTemplate() -> CPTabBarTemplate {
        let nowPlayingTemplate = CPNowPlayingTemplate.shared
        nowPlayingTemplate.updateNowPlayingButtons([
            CPNowPlayingShuffleButton(handler: { [weak self] _ in
                self?.audioPlayer.playMode = .random
            }),
            CPNowPlayingRepeatButton(handler: { [weak self] _ in
                self?.audioPlayer.togglePlayMode()
            })
        ])
        
        let playlistTemplate = createPlaylistTemplate()
        let historyTemplate = createHistoryTemplate()
        let favoritesTemplate = createFavoritesTemplate()
        
        let tabBarTemplate = CPTabBarTemplate(templates: [
            nowPlayingTemplate,
            playlistTemplate,
            historyTemplate,
            favoritesTemplate
        ])
        
        return tabBarTemplate
    }
    
    // MARK: - 播放列表模板
    
    private func createPlaylistTemplate() -> CPListTemplate {
        let template = CPListTemplate(title: "播放列表", sections: [])
        template.tabImage = UIImage(systemName: "music.note.list")
        
        updatePlaylistTemplate(template)
        
        // 监听播放列表变化
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("PlaylistDidChange"),
            object: nil,
            queue: .main
        ) { [weak self, weak template] _ in
            guard let template = template else { return }
            self?.updatePlaylistTemplate(template)
        }
        
        return template
    }
    
    private func updatePlaylistTemplate(_ template: CPListTemplate) {
        let tracks = audioPlayer.playlist
        
        if tracks.isEmpty {
            let emptyItem = CPListItem(text: "暂无播放列表", detailText: "在手机上添加歌曲")
            emptyItem.isEnabled = false
            template.updateSections([CPListSection(items: [emptyItem])])
            return
        }
        
        let items = tracks.prefix(50).enumerated().map { index, track -> CPListItem in
            let item = CPListItem(
                text: track.name,
                detailText: track.artistName
            )
            
            // 加载封面
            if let coverUrl = track.coverUrl, let url = URL(string: coverUrl) {
                loadImage(from: url) { image in
                    item.setImage(image)
                }
            }
            
            item.handler = { [weak self] _, completion in
                self?.audioPlayer.currentIndex = index
                Task {
                    await self?.audioPlayer.play(track: track)
                }
                completion()
            }
            
            return item
        }
        
        template.updateSections([CPListSection(items: items)])
    }
    
    // MARK: - 播放历史模板
    
    private func createHistoryTemplate() -> CPListTemplate {
        let template = CPListTemplate(title: "最近播放", sections: [])
        template.tabImage = UIImage(systemName: "clock")
        
        updateHistoryTemplate(template)
        
        return template
    }
    
    private func updateHistoryTemplate(_ template: CPListTemplate) {
        let history = LocalStorageService.shared.getHistory()
        
        if history.isEmpty {
            let emptyItem = CPListItem(text: "暂无播放历史", detailText: "开始播放音乐吧")
            emptyItem.isEnabled = false
            template.updateSections([CPListSection(items: [emptyItem])])
            return
        }
        
        let items = history.prefix(50).map { track -> CPListItem in
            let item = CPListItem(
                text: track.name,
                detailText: track.artistName
            )
            
            if let coverUrl = track.coverUrl, let url = URL(string: coverUrl) {
                loadImage(from: url) { image in
                    item.setImage(image)
                }
            }
            
            item.handler = { [weak self] _, completion in
                Task {
                    await self?.audioPlayer.play(track: track)
                }
                completion()
            }
            
            return item
        }
        
        template.updateSections([CPListSection(items: items)])
    }
    
    // MARK: - 收藏模板
    
    private func createFavoritesTemplate() -> CPListTemplate {
        let template = CPListTemplate(title: "我喜欢", sections: [])
        template.tabImage = UIImage(systemName: "heart.fill")
        
        updateFavoritesTemplate(template)
        
        return template
    }
    
    private func updateFavoritesTemplate(_ template: CPListTemplate) {
        // 获取本地收藏的歌曲
        let favorites = LocalStorageService.shared.getFavorites()
        
        if favorites.isEmpty {
            let emptyItem = CPListItem(text: "暂无收藏的歌曲", detailText: "点击 ❤️ 收藏歌曲")
            emptyItem.isEnabled = false
            template.updateSections([CPListSection(items: [emptyItem])])
            return
        }
        
        let items = favorites.prefix(50).map { track -> CPListItem in
            let item = CPListItem(
                text: track.name,
                detailText: track.artistName
            )
            
            if let coverUrl = track.coverUrl, let url = URL(string: coverUrl) {
                self.loadImage(from: url) { image in
                    item.setImage(image)
                }
            }
            
            item.handler = { [weak self] _, completion in
                Task {
                    await self?.audioPlayer.play(track: track)
                }
                completion()
            }
            
            return item
        }
        
        template.updateSections([CPListSection(items: items)])
    }
    
    // MARK: - 图片加载
    
    private func loadImage(from url: URL, completion: @escaping (UIImage?) -> Void) {
        // 先检查内存缓存
        if let cachedImage = ImageCache.shared.getFromMemory(url) {
            completion(cachedImage)
            return
        }
        
        // 检查磁盘缓存
        if let cachedImage = ImageCache.shared.getFromDisk(url) {
            completion(cachedImage)
            return
        }
        
        // 网络加载
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data, let image = UIImage(data: data) else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            
            // 缓存图片
            ImageCache.shared.saveToMemory(image, for: url)
            ImageCache.shared.saveToDisk(data, for: url)
            
            DispatchQueue.main.async {
                completion(image)
            }
        }.resume()
    }
}
