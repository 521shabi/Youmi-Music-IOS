import Foundation

/// 认证服务
class AuthService {
    static let shared = AuthService()
    private let network = NetworkService.shared
    
    private init() {}
    
    /// 手机号密码登录
    /// - Parameters:
    ///   - phone: 手机号
    ///   - password: 密码
    /// - Returns: 登录响应
    func loginWithPhone(phone: String, password: String) async throws -> LoginResponse {
        let params: [String: Any] = [
            "phone": phone,
            "password": password
        ]
        
        let response: LoginResponse = try await network.post(endpoint: .loginCellphone, params: params)
        
        if response.code == 200, let cookie = response.cookie {
            network.setCookie(cookie)
        }
        
        return response
    }
    
    /// 手机号验证码登录
    /// - Parameters:
    ///   - phone: 手机号
    ///   - captcha: 验证码
    /// - Returns: 登录响应
    func loginWithCaptcha(phone: String, captcha: String) async throws -> LoginResponse {
        let params: [String: Any] = [
            "phone": phone,
            "captcha": captcha
        ]
        
        let response: LoginResponse = try await network.post(endpoint: .loginCellphone, params: params)
        
        if response.code == 200, let cookie = response.cookie {
            network.setCookie(cookie)
        }
        
        return response
    }
    
    /// 发送验证码
    /// - Parameter phone: 手机号
    /// - Returns: 发送结果
    func sendCaptcha(phone: String) async throws -> CaptchaSentResponse {
        let params: [String: Any] = [
            "phone": phone
        ]
        return try await network.post(endpoint: .captchaSent, params: params)
    }
    
    /// 验证验证码是否正确
    /// - Parameters:
    ///   - phone: 手机号
    ///   - captcha: 验证码
    /// - Returns: 验证结果
    func verifyCaptcha(phone: String, captcha: String) async throws -> CaptchaVerifyResponse {
        let params: [String: Any] = [
            "phone": phone,
            "captcha": captcha
        ]
        return try await network.post(endpoint: .captchaVerify, params: params)
    }
    
    /// 获取二维码 Key
    func getQRKey() async throws -> String {
        guard let url = APIEndpoint.loginQRKey.url else {
            throw NetworkError.invalidURL
        }
        
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "timestamp", value: "\(Int(Date().timeIntervalSince1970 * 1000))")
        ]
        
        guard let finalURL = components.url else {
            throw NetworkError.invalidURL
        }
        
        var request = URLRequest(url: finalURL)
        request.httpMethod = "GET"
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(QRKeyResponse.self, from: data)
        
        guard response.code == 200, let unikey = response.data?.unikey else {
            throw NetworkError.serverError(response.code, "获取二维码Key失败")
        }
        return unikey
    }
    
    /// 生成二维码
    /// - Parameter key: 二维码 Key
    /// - Returns: 二维码图片 Base64 或 URL
    func createQRCode(key: String) async throws -> String {
        guard let url = APIEndpoint.loginQRCreate.url else {
            throw NetworkError.invalidURL
        }
        
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "key", value: key),
            URLQueryItem(name: "qrimg", value: "true"),
            URLQueryItem(name: "timestamp", value: "\(Int(Date().timeIntervalSince1970 * 1000))")
        ]
        
        guard let finalURL = components.url else {
            throw NetworkError.invalidURL
        }
        
        var request = URLRequest(url: finalURL)
        request.httpMethod = "GET"
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(QRCreateResponse.self, from: data)
        
        if let qrimg = response.data?.qrimg {
            return qrimg
        } else if let qrurl = response.data?.qrurl {
            return qrurl
        }
        
        throw NetworkError.serverError(response.code, "生成二维码失败")
    }
    
    /// 检查二维码扫码状态
    /// - Parameter key: 二维码 Key
    /// - Returns: 状态响应
    /// 返回码: 800-二维码过期, 801-等待扫码, 802-待确认, 803-登录成功
    func checkQRStatus(key: String) async throws -> QRCheckResponse {
        guard let url = APIEndpoint.loginQRCheck.url else {
            throw NetworkError.invalidURL
        }
        
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "key", value: key),
            URLQueryItem(name: "timestamp", value: "\(Int(Date().timeIntervalSince1970 * 1000))"),
            URLQueryItem(name: "noCookie", value: "true")
        ]
        
        guard let finalURL = components.url else {
            throw NetworkError.invalidURL
        }
        
        var request = URLRequest(url: finalURL)
        request.httpMethod = "GET"
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(QRCheckResponse.self, from: data)
        
        // 803 表示登录成功
        if response.code == 803, let cookie = response.cookie {
            network.setCookie(cookie)
        }
        
        return response
    }
    
    /// 获取登录状态
    func getLoginStatus() async throws -> LoginStatusResponse {
        return try await network.get(endpoint: .loginStatus)
    }
    
    /// 退出登录
    func logout() async throws {
        let _: LogoutResponse = try await network.get(endpoint: .logout)
        network.setCookie(nil)
    }
    
    /// 检查是否已登录
    func isLoggedIn() -> Bool {
        return network.getSavedCookie() != nil
    }
    
    /// 恢复登录状态
    func restoreSession() {
        network.loadSavedCookie()
    }
    
    /// 设置 Cookie
    func setCookie(_ cookie: String?) {
        network.setCookie(cookie)
    }
}
