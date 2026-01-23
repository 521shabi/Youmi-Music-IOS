import Foundation

/// 用户服务
class UserService {
    static let shared = UserService()
    private let network = NetworkService.shared
    
    private init() {}
    
    /// 获取用户账号信息
    func getUserAccount() async throws -> UserAccountResponse {
        return try await network.get(endpoint: .userAccount)
    }
    
    /// 获取用户详情
    /// - Parameter uid: 用户ID
    func getUserDetail(uid: Int) async throws -> UserDetailResponse {
        return try await network.get(endpoint: .userDetail(uid: uid))
    }
    
    /// 获取当前登录用户的完整资料
    func getCurrentUserProfile() async throws -> UserProfile {
        // 先获取账号信息拿到 uid
        let accountResponse = try await getUserAccount()
        
        guard accountResponse.code == 200,
              let account = accountResponse.account else {
            throw NetworkError.serverError(accountResponse.code, "获取账号信息失败")
        }
        
        // 再获取用户详情
        let detailResponse = try await getUserDetail(uid: account.id)
        
        guard detailResponse.code == 200,
              let profile = detailResponse.profile else {
            throw NetworkError.serverError(detailResponse.code, "获取用户详情失败")
        }
        
        // 合并根级别的 level 和 listenSongs 到 profile
        return UserProfile(
            userId: profile.userId,
            nickname: profile.nickname,
            avatarUrl: profile.avatarUrl,
            backgroundUrl: profile.backgroundUrl,
            signature: profile.signature,
            gender: profile.gender,
            birthday: profile.birthday,
            city: profile.city,
            province: profile.province,
            followed: profile.followed,
            followeds: profile.followeds,
            follows: profile.follows,
            playlistCount: profile.playlistCount,
            eventCount: profile.eventCount,
            vipType: profile.vipType,
            level: detailResponse.level ?? profile.level,
            listenSongs: detailResponse.listenSongs ?? profile.listenSongs
        )
    }
    
    // MARK: - 网易云歌单和收藏
    
    /// 获取用户歌单列表
    func getUserPlaylists(uid: Int) async throws -> [CloudPlaylist] {
        let response: UserPlaylistResponse = try await network.get(endpoint: .userPlaylist(uid: uid))
        guard response.code == 200 else {
            throw NetworkError.serverError(response.code, "获取歌单失败")
        }
        return response.playlist ?? []
    }
    
    /// 获取喜欢的音乐ID列表
    func getLikeList(uid: Int) async throws -> [Int] {
        let response: LikelistResponse = try await network.get(endpoint: .likelist(uid: uid))
        guard response.code == 200 else {
            throw NetworkError.serverError(response.code, "获取喜欢列表失败")
        }
        return response.ids ?? []
    }
    
    /// 获取收藏的专辑
    func getAlbumSublist() async throws -> [CloudAlbum] {
        let response: AlbumSublistResponse = try await network.get(endpoint: .albumSublist)
        guard response.code == 200 else {
            throw NetworkError.serverError(response.code, "获取收藏专辑失败")
        }
        return response.data ?? []
    }
    
    /// 喜欢/取消喜欢歌曲
    /// - Parameters:
    ///   - id: 歌曲ID
    ///   - like: true 喜欢，false 取消喜欢
    func likeSong(id: Int, like: Bool) async throws -> Bool {
        let response: LikeResponse = try await network.get(endpoint: .like(id: id, like: like))
        guard response.code == 200 else {
            throw NetworkError.serverError(response.code, like ? "喜欢失败" : "取消喜欢失败")
        }
        return true
    }
}
