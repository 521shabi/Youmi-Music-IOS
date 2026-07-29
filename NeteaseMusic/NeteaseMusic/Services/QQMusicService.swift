import Foundation

/// QQ音乐服务
class QQMusicService {
    static let shared = QQMusicService()
    private let session: URLSession
    private let decoder = JSONDecoder()
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - 数据模型
    
    struct QQSearchResult: Codable {
        let code: Int
        let data: QQSearchData?
    }
    
    struct QQSearchData: Codable {
        let song: QQSongList?
    }
    
    struct QQSongList: Codable {
        let totalnum: Int?
        let list: [QQSongItem]?
    }
    
    struct QQSongItem: Codable, Identifiable {
        let songid: Int
        let songmid: String
        let songname: String
        let singer: [QQSinger]?
        let album: QQAlbum?
        let interval: Int?
        let file: QQFile?
        
        var id: String { songmid }
        var displayName: String { songname }
        var artistName: String { singer?.map { $0.name ?? "" }.joined(separator: ", ") ?? "未知" }
        var albumName: String { album?.name ?? "未知" }
        var durationSeconds: Int { interval ?? 0 }
        var durationText: String {
            let minutes = durationSeconds / 60
            let seconds = durationSeconds % 60
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
    
    struct QQSinger: Codable {
        let id: Int?
        let name: String?
        let mid: String?
    }
    
    struct QQAlbum: Codable {
        let id: Int?
        let name: String?
        let mid: String?
        let pmid: String?
    }
    
    struct QQFile: Codable {
        let media_mid: String?
    }
    
    // MARK: - 搜索
    
    func search(keyword: String, page: Int = 1, perPage: Int = 20) async throws -> [QQSongItem] {
        guard let url = QQMusicAPIEndpoint.search(keyword: keyword, page: page, perPage: perPage).url else {
            throw NSError(domain: "QQMusicService", code: -1)
        }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        request.setValue("https://y.qq.com", forHTTPHeaderField: "Referer")
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "QQMusicService", code: -2)
        }
        
        guard let jsonString = String(data: data, encoding: .utf8),
              let jsonData = jsonString.data(using: .utf8),
              let result = try? decoder.decode(QQSearchResult.self, from: jsonData) else {
            throw NSError(domain: "QQMusicService", code: -3)
        }
        
        return result.data?.song?.list ?? []
    }
    
    // MARK: - 获取歌曲URL
    
    func getSongURL(songmid: String) async throws -> String? {
        guard let url = QQMusicAPIEndpoint.songUrl(songmid: songmid).url else { return nil }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        request.setValue("https://y.qq.com", forHTTPHeaderField: "Referer")
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return nil }
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let reqData = json["req_1_4"] as? [String: Any],
           let dataDetail = reqData["data"] as? [String: Any],
           let urlinfo = dataDetail["midurlinfo"] as? [[String: Any]],
           let firstInfo = urlinfo.first {
            if let purl = firstInfo["purl"] as? String, !purl.isEmpty { return purl }
            if let urlStr = firstInfo["url"] as? String, !urlStr.isEmpty { return urlStr }
        }
        return nil
    }
    
    // MARK: - 获取歌词
    
    func getLyric(songmid: String) async throws -> (lyric: String, translation: String?) {
        guard let url = QQMusicAPIEndpoint.lyric(songmid: songmid).url else { return ("", nil) }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        request.setValue("https://y.qq.com", forHTTPHeaderField: "Referer")
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return ("", nil) }
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return (json["lyric"] as? String ?? "", json["trans"] as? String)
        }
        return ("", nil)
    }
    
    // MARK: - 排行榜
    
    func getTopList() async throws -> [QQSongItem] {
        guard let url = QQMusicAPIEndpoint.topList.url else { return [] }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return [] }
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let cdlist = json["cdlist"] as? [[String: Any]],
           let firstCd = cdlist.first,
           let songlist = firstCd["songlist"] as? [[String: Any]] {
            var songs: [QQSongItem] = []
            for songData in songlist {
                if let songmid = songData["songmid"] as? String, let songname = songData["songname"] as? String {
                    songs.append(QQSongItem(songid: songData["songid"] as? Int ?? 0, songmid: songmid, songname: songname, singer: nil, album: nil, interval: songData["interval"] as? Int, file: QQFile(media_mid: songData["filemediaid"] as? String)))
                }
            }
            return songs
        }
        return []
    }
}