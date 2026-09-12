import Foundation

enum GitHubAPIError: LocalizedError {
    case invalidURL
    case requestFailed(Int, String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "无法构造 GitHub API 请求。"
        case .requestFailed(let status, let message):
            return "GitHub API 请求失败（HTTP \(status)）：\(message)"
        case .invalidResponse(let message):
            return "GitHub API 响应无效：\(message)"
        }
    }
}

struct GitHubAPIClient {
    let accessToken: String

    func currentUser() async throws -> GitHubAccount {
        try await request(path: "/user", method: "GET", body: Optional<EmptyBody>.none)
    }

    func repositories() async throws -> [GitHubRepository] {
        var repositories: [GitHubRepository] = []
        var page = 1

        while true {
            let batch: [GitHubRepository] = try await request(
                path: "/user/repos?affiliation=owner,collaborator,organization_member&sort=updated&per_page=100&page=\(page)",
                method: "GET",
                body: Optional<EmptyBody>.none
            )
            repositories.append(contentsOf: batch)
            if batch.count < 100 { break }
            page += 1
        }

        return repositories
    }

    func createRepository(
        name: String,
        description: String,
        isPrivate: Bool
    ) async throws -> GitHubRepository {
        let body = CreateRepositoryBody(
            name: name,
            description: description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : description,
            private: isPrivate,
            autoInit: false,
            hasIssues: true,
            hasWiki: false
        )
        return try await request(path: "/user/repos", method: "POST", body: body)
    }

    func repository(fullName: String) async throws -> GitHubRepository? {
        do {
            return try await request(
                path: "/repos/\(fullName)",
                method: "GET",
                body: Optional<EmptyBody>.none
            )
        } catch GitHubAPIError.requestFailed(let statusCode, _) where statusCode == 404 {
            return nil
        }
    }

    func updateVisibility(repositorySlug: String, isPrivate: Bool) async throws {
        let body = UpdateRepositoryBody(
            description: nil,
            private: isPrivate,
            homepage: nil
        )
        let _: GitHubRepository = try await request(
            path: "/repos/\(repositorySlug)",
            method: "PATCH",
            body: body
        )
    }

    func updateMetadata(
        repositorySlug: String,
        description: String?,
        homepage: String?
    ) async throws {
        let body = UpdateRepositoryBody(
            description: description,
            private: nil,
            homepage: homepage
        )
        let _: GitHubRepository = try await request(
            path: "/repos/\(repositorySlug)",
            method: "PATCH",
            body: body
        )
    }

    func updateTopics(repositorySlug: String, topics: [String]) async throws {
        let body = TopicsBody(names: Array(topics.prefix(20)))
        let _: TopicsResponse = try await request(
            path: "/repos/\(repositorySlug)/topics",
            method: "PUT",
            body: body
        )
    }

    private func request<Response: Decodable, Body: Encodable>(
        path: String,
        method: String,
        body: Body?
    ) async throws -> Response {
        guard let url = URL(string: "https://api.github.com\(path)") else {
            throw GitHubAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("GitHubDesk", forHTTPHeaderField: "User-Agent")
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitHubAPIError.invalidResponse("缺少 HTTP 状态")
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = (try? JSONDecoder().decode(APIErrorResponse.self, from: data).message)
                ?? String(decoding: data, as: UTF8.self)
            throw GitHubAPIError.requestFailed(httpResponse.statusCode, message)
        }

        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw GitHubAPIError.invalidResponse(error.localizedDescription)
        }
    }
}

private struct EmptyBody: Codable {}

private struct CreateRepositoryBody: Codable {
    let name: String
    let description: String?
    let `private`: Bool
    let autoInit: Bool
    let hasIssues: Bool
    let hasWiki: Bool

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case `private`
        case autoInit = "auto_init"
        case hasIssues = "has_issues"
        case hasWiki = "has_wiki"
    }
}

private struct UpdateRepositoryBody: Codable {
    let description: String?
    let `private`: Bool?
    let homepage: String?

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(`private`, forKey: .private)
        try container.encodeIfPresent(homepage, forKey: .homepage)
    }

    enum CodingKeys: String, CodingKey {
        case description
        case `private`
        case homepage
    }
}

private struct TopicsBody: Codable {
    let names: [String]
}

private struct TopicsResponse: Codable {
    let names: [String]
}

private struct APIErrorResponse: Codable {
    let message: String
}
