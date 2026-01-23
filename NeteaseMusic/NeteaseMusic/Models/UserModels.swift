import Foundation

// MARK: - 登录响应
struct LoginResponse: Codable {
    let code: Int
    let cookie: String?
    let token: String?
    let account: Account?
    let profile: UserProfile?
    let message: String?
}

// MARK: - 账户信息
struct Account: Codable {
    let id: Int
    let userName: String?
    let type: Int?
    let status: Int?
    let createTime: Int64?
    let vipType: Int?
}

// MARK: - 用户资料
struct UserProfile: Codable, Equatable {
    let userId: Int
    let nickname: String
    let avatarUrl: String?
    let backgroundUrl: String?
    let signature: String?
    let gender: Int?           // 0: 未知, 1: 男, 2: 女
    let birthday: Int64?
    let city: Int?
    let province: Int?
    let followed: Bool?
    let followeds: Int?        // 粉丝数
    let follows: Int?          // 关注数
    let playlistCount: Int?
    let eventCount: Int?       // 动态数
    let vipType: Int?
    let level: Int?            // 等级
    let listenSongs: Int?      // 听歌数量
    
    var genderText: String {
        switch gender {
        case 1: return "男"
        case 2: return "女"
        default: return "未知"
        }
    }
}

// MARK: - 用户详情响应
struct UserDetailResponse: Codable {
    let code: Int
    let level: Int?
    let listenSongs: Int?
    let profile: UserProfile?
    let createDays: Int?       // 注册天数
    let createTime: Int64?
}

// MARK: - 用户账户响应
struct UserAccountResponse: Codable {
    let code: Int
    let account: Account?
    let profile: UserProfile?
}

// MARK: - 登录状态响应
struct LoginStatusResponse: Codable {
    let data: LoginStatusData?
}

struct LoginStatusData: Codable {
    let code: Int
    let account: Account?
    let profile: UserProfile?
}

// MARK: - 二维码相关
struct QRKeyResponse: Codable {
    let code: Int
    let data: QRKeyData?
}

struct QRKeyData: Codable {
    let code: Int
    let unikey: String?
}

struct QRCreateResponse: Codable {
    let code: Int
    let data: QRCreateData?
}

struct QRCreateData: Codable {
    let qrimg: String?
    let qrurl: String?
}

struct QRCheckResponse: Codable {
    let code: Int
    let cookie: String?
    let message: String?
}

// MARK: - 退出登录响应
struct LogoutResponse: Codable {
    let code: Int
}

// MARK: - 验证码相关
struct CaptchaSentResponse: Codable {
    let code: Int
    let data: Bool?
    let message: String?
}

struct CaptchaVerifyResponse: Codable {
    let code: Int
    let data: Bool?
    let message: String?
}

// MARK: - 用户歌单相关
struct UserPlaylistResponse: Codable {
    let code: Int
    let playlist: [CloudPlaylist]?
}

struct CloudPlaylist: Codable, Identifiable {
    let id: Int
    let name: String
    let coverImgUrl: String?
    let trackCount: Int?
    let playCount: Int?
    let userId: Int?
    let createTime: Int64?
    let specialType: Int?       // 5 表示喜欢的音乐
    let description: String?
    
    var isLikedPlaylist: Bool {
        specialType == 5
    }
    
    var coverUrl: String? {
        coverImgUrl?.replacingOccurrences(of: "http://", with: "https://")
    }
}

// MARK: - 喜欢的音乐ID列表
struct LikelistResponse: Codable {
    let code: Int
    let ids: [Int]?
}

// MARK: - 喜欢歌曲响应
struct LikeResponse: Codable {
    let code: Int
    let playlistId: Int?
}

// MARK: - 收藏的专辑
struct AlbumSublistResponse: Codable {
    let code: Int
    let data: [CloudAlbum]?
    let count: Int?
}

struct CloudAlbum: Codable, Identifiable {
    let id: Int
    let name: String
    let picUrl: String?
    let artist: CloudArtist?
    let artists: [CloudArtist]?
    let size: Int?              // 歌曲数
    let publishTime: Int64?
    
    var coverUrl: String? {
        picUrl?.replacingOccurrences(of: "http://", with: "https://")
    }
    
    var artistName: String {
        artist?.name ?? artists?.first?.name ?? "未知艺术家"
    }
}

struct CloudArtist: Codable {
    let id: Int
    let name: String
}

// MARK: - 云端歌曲模型
struct CloudTrack: Codable, Identifiable {
    let id: Int
    let name: String
    let ar: [CloudTrackArtist]?
    let al: CloudTrackAlbum?
    let dt: Int?  // 时长(毫秒)
    
    var artistName: String {
        ar?.map { $0.name }.joined(separator: " / ") ?? "未知艺术家"
    }
    
    var albumName: String {
        al?.name ?? ""
    }
    
    var coverUrl: String? {
        al?.picUrl?.replacingOccurrences(of: "http://", with: "https://")
    }
    
    var durationSeconds: TimeInterval {
        Double(dt ?? 0) / 1000.0
    }
    
    func toTrack() -> Track {
        Track(
            id: id,
            name: name,
            ar: ar?.map { Artist(id: $0.id, name: $0.name) },
            al: al != nil ? Album(id: al!.id, name: al!.name, picUrl: al!.picUrl) : nil,
            artists: nil,
            album: nil,
            dt: dt,
            duration: nil,
            mv: nil,
            mvid: nil
        )
    }
}

struct CloudTrackArtist: Codable {
    let id: Int
    let name: String
}

struct CloudTrackAlbum: Codable {
    let id: Int
    let name: String
    let picUrl: String?
}

// MARK: - 云端歌单详情响应
struct CloudPlaylistDetailResponse: Codable {
    let code: Int
    let playlist: CloudPlaylistDetailData?
}

struct CloudPlaylistDetailData: Codable {
    let id: Int
    let name: String
    let tracks: [CloudTrack]?
}

// MARK: - 云端专辑详情响应
struct CloudAlbumDetailResponse: Codable {
    let code: Int
    let album: CloudAlbumDetailData?
    let songs: [CloudTrack]?
}

struct CloudAlbumDetailData: Codable {
    let id: Int
    let name: String
}
