import Foundation

/// API 配置
struct APIConfig {
    // MARK: - 网易云音乐公共API服务器
    
    static let publicAPIServers: [String: String] = [
        "默认": "https://netease-cloud-music-api-sigma-sage.vercel.app",
        "备用1": "https://api.03c3.cn",
        "备用2": "https://api.injahow.cn",
        "备用3": "https://music-api.ixiaoping.com",
    ]
    
    static let qqSearchURL = "https://c.y.qq.com/soso/fcgi-bin/client_search_cp"
    static let iTunesSearchURL = "https://itunes.apple.com/search"
    static let kuwoAPIURL = "https://www.kuwo.cn"
    static let kugouAPIURL = "https://www.kugou.com"
    
    static var baseURL: String = "https://netease-cloud-music-api-sigma-sage.vercel.app"
    static var usePublicAPI: Bool = true
    static var customServerURL: String = "http://localhost:3000"
    
    static func setBaseURL(_ url: String) {
        baseURL = url.hasSuffix("/") ? String(url.dropLast()) : url
    }
    
    static func usePublicServer(_ serverName: String = "默认") {
        if let url = publicAPIServers[serverName] {
            setBaseURL(url)
            usePublicAPI = true
        }
    }
    
    static func useCustomServer(_ url: String) {
        customServerURL = url
        setBaseURL(url)
        usePublicAPI = false
    }
}

/// API 端点
enum APIEndpoint {
    case loginCellphone
    case loginQRKey
    case loginQRCreate
    case loginQRCheck
    case loginStatus
    case logout
    case captchaSent
    case captchaVerify
    case userAccount
    case userDetail(uid: Int)
    case userPlaylist(uid: Int)
    case likelist(uid: Int)
    case like(id: Int, like: Bool)
    case albumSublist
    case playlistDetail(id: Int)
    case songDetail(ids: [Int])
    case songUrl(id: Int, br: Int)
    case lyric(id: Int)
    case search(keyword: String, limit: Int, offset: Int)
    
    var path: String {
        switch self {
        case .loginCellphone: return "/login/cellphone"
        case .loginQRKey: return "/login/qr/key"
        case .loginQRCreate: return "/login/qr/create"
        case .loginQRCheck: return "/login/qr/check"
        case .loginStatus: return "/login/status"
        case .logout: return "/logout"
        case .captchaSent: return "/captcha/sent"
        case .captchaVerify: return "/captcha/verify"
        case .userAccount: return "/user/account"
        case .userDetail(let uid): return "/user/detail?uid=\(uid)"
        case .userPlaylist(let uid): return "/user/playlist?uid=\(uid)"
        case .likelist(let uid): return "/likelist?uid=\(uid)"
        case .like(let id, let like): return "/like?id=\(id)&like=\(like)"
        case .albumSublist: return "/album/sublist"
        case .playlistDetail(let id): return "/playlist/detail?id=\(id)"
        case .songDetail(let ids): return "/song/detail?ids=\(ids.map { String($0) }.joined(separator: ","))"
        case .songUrl(let id, let br): return "/song/url?id=\(id)&br=\(br)"
        case .lyric(let id): return "/lyric?id=\(id)"
        case .search(let keyword, let limit, let offset):
            let encoded = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword
            return "/search?keywords=\(encoded)&limit=\(limit)&offset=\(offset)"
        }
    }
    
    var url: URL? { URL(string: APIConfig.baseURL + path) }
}

/// QQ音乐API端点
enum QQMusicAPIEndpoint {
    case search(keyword: String, page: Int, perPage: Int)
    case songDetail(songmid: String)
    case songUrl(songmid: String)
    case lyric(songmid: String)
    case topList
    case topSongs(singerId: String)
    
    var url: URL? {
        switch self {
        case .search(let keyword, let page, let perPage):
            let encoded = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword
            return URL(string: "\(APIConfig.qqSearchURL)?w=\(encoded)&p=\(page)&n=\(perPage)&cr=1&g_tk=5381&loginUin=0&format=json&inCharset=utf8&outCharset=utf-8&notice=0&platform=yqq&needNewCode=0")
        case .songDetail(let songmid):
            return URL(string: "https://c.y.qq.com/v8/fcg-bin/fcg_v8_song_page.fcg?songmid=\(songmid)&platform=0&json=1")
        case .songUrl(let songmid):
            return URL(string: "https://u.y.qq.com/cgi-bin/musicu.fcg?req_1_4=%7B%22module%22%3A%22CGIuc25GetSongline%22%2C%22method%22%3A%22GetSongDetailInfo%22%2C%22param%22%3A%7B%22songmid%22%3A%5B%22\(songmid)%22%5D%2C%22platform%22%3A%22%22%7D%7D")
        case .lyric(let songmid):
            return URL(string: "https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg?songmid=\(songmid)&g_tk=5381&format=json&nobase64=1")
        case .topList:
            return URL(string: "https://c.y.qq.com/qzone/fcg-bin/fcg_ucc_getcdinfo_byids_cp.fcg?type=1&json=1&utf8=1&onlysong=0&disstid=264&format=json")
        case .topSongs(let singerId):
            return URL(string: "https://c.y.qq.com/v8/fcg-bin/fcg_v8_singer_track_cp.fcg?singerId=\(singerId)&order=listen&pageSize=30&pageNum=1&g_tk=5381&loginUin=0&format=json&inCharset=utf8&outCharset=utf-8&notice=0&platform=yqq&needNewCode=0")
        }
    }
}

/// Apple Music API端点
enum AppleMusicAPIEndpoint {
    case search(term: String, limit: Int)
    case lookup(id: Int)
    case topSongs(genre: String, limit: Int)
    
    var url: URL? {
        switch self {
        case .search(let term, let limit):
            let encoded = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? term
            return URL(string: "\(APIConfig.iTunesSearchURL)?term=\(encoded)&media=music&limit=\(limit)")
        case .lookup(let id):
            return URL(string: "\(APIConfig.iTunesSearchURL)?id=\(id)")
        case .topSongs(let genre, let limit):
            return URL(string: "https://itunes.apple.com/\(genre)/rss/topsongs/limit=\(limit)/json")
        }
    }
}