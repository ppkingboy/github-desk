import Foundation

enum OAuthConfiguration {
    static let clientID = "Ov23lizZW41iBf7A2ky5"
    static let scope = "repo read:org"
}

enum GitHubOAuthError: LocalizedError {
    case invalidResponse(String)
    case authorizationDenied
    case expired
    case network(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse(let message):
            return "GitHub 登录响应无效：\(message)"
        case .authorizationDenied:
            return "GitHub 授权被拒绝。"
        case .expired:
            return "设备验证码已过期，请重新登录。"
        case .network(let message):
            return "GitHub 登录失败：\(message)"
        }
    }
}

enum GitHubOAuthService {
    private static let decoder = JSONDecoder()
    private static let encoder = JSONEncoder()

    static func requestDeviceCode() async throws -> DeviceCodeResponse {
        let body = formData([
            "client_id": OAuthConfiguration.clientID,
            "scope": OAuthConfiguration.scope
        ])
        let data = try await request(
            url: URL(string: "https://github.com/login/device/code")!,
            body: body
        )
        return try decoder.decode(DeviceCodeResponse.self, from: data)
    }

    static func pollForToken(
        deviceCode: String,
        interval: Int,
        expiresIn: Int
    ) async throws -> OAuthTokenResponse {
        let deadline = Date().addingTimeInterval(TimeInterval(expiresIn))
        var pollingInterval = max(5, interval)

        while Date() < deadline {
            try Task.checkCancellation()
            try await Task.sleep(for: .seconds(pollingInterval))

            let response = try await tokenRequest(
                parameters: [
                    "client_id": OAuthConfiguration.clientID,
                    "device_code": deviceCode,
                    "grant_type": "urn:ietf:params:oauth:grant-type:device_code"
                ]
            )

            switch response.error {
            case nil:
                guard response.accessToken != nil else {
                    throw GitHubOAuthError.invalidResponse("缺少访问令牌")
                }
                return response
            case "authorization_pending":
                continue
            case "slow_down":
                pollingInterval += 5
            case "access_denied":
                throw GitHubOAuthError.authorizationDenied
            case "expired_token":
                throw GitHubOAuthError.expired
            case let error?:
                throw GitHubOAuthError.invalidResponse(response.errorDescription ?? error)
            }
        }

        throw GitHubOAuthError.expired
    }

    static func refresh(refreshToken: String) async throws -> OAuthTokenResponse {
        let response = try await tokenRequest(parameters: [
            "client_id": OAuthConfiguration.clientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken
        ])

        if let error = response.error {
            throw GitHubOAuthError.invalidResponse(response.errorDescription ?? error)
        }
        guard response.accessToken != nil else {
            throw GitHubOAuthError.invalidResponse("刷新响应缺少访问令牌")
        }
        return response
    }

    private static func tokenRequest(parameters: [String: String]) async throws -> OAuthTokenResponse {
        let data = try await request(
            url: URL(string: "https://github.com/login/oauth/access_token")!,
            body: formData(parameters)
        )
        return try decoder.decode(OAuthTokenResponse.self, from: data)
    }

    private static func request(url: URL, body: Data) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw GitHubOAuthError.invalidResponse("缺少 HTTP 状态")
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                let message = String(decoding: data, as: UTF8.self)
                throw GitHubOAuthError.invalidResponse("HTTP \(httpResponse.statusCode) \(message)")
            }
            return data
        } catch let error as GitHubOAuthError {
            throw error
        } catch {
            throw GitHubOAuthError.network(error.localizedDescription)
        }
    }

    private static func formData(_ values: [String: String]) -> Data {
        var components = URLComponents()
        components.queryItems = values.map { URLQueryItem(name: $0.key, value: $0.value) }
        return Data((components.percentEncodedQuery ?? "").utf8)
    }
}
