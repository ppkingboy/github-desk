import Foundation

struct GitHubSnapshot {
    let login: String
    let repositories: [GitHubRepository]
}

enum GitHubServiceError: LocalizedError {
    case commandFailed(String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message):
            return message
        case .invalidResponse(let message):
            return "无法读取 GitHub 返回的数据：\(message)"
        }
    }
}

enum GitHubService {
    static func loadSnapshot() throws -> GitHubSnapshot {
        let loginResult = try CommandRunner.run(
            named: "gh",
            arguments: ["api", "user", "--jq", ".login"]
        )
        guard loginResult.succeeded else {
            throw GitHubServiceError.commandFailed(
                loginResult.combinedOutput.isEmpty
                    ? "GitHub 尚未登录。"
                    : loginResult.combinedOutput
            )
        }

        let login = loginResult.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !login.isEmpty else {
            throw GitHubServiceError.invalidResponse("缺少登录账号")
        }

        let repositoryResult = try CommandRunner.run(
            named: "gh",
            arguments: [
                "repo", "list", login,
                "--limit", "1000",
                "--json",
                "nameWithOwner,description,isPrivate,visibility,url,sshUrl,updatedAt,defaultBranchRef,primaryLanguage"
            ]
        )
        guard repositoryResult.succeeded else {
            throw GitHubServiceError.commandFailed(repositoryResult.combinedOutput)
        }

        let data = Data(repositoryResult.standardOutput.utf8)
        do {
            let repositories = try JSONDecoder().decode([GitHubRepository].self, from: data)
            return GitHubSnapshot(login: login, repositories: repositories)
        } catch {
            throw GitHubServiceError.invalidResponse(error.localizedDescription)
        }
    }

    static func setVisibility(
        repositorySlug: String,
        visibility: RepositoryVisibility
    ) throws {
        let result = try CommandRunner.run(
            named: "gh",
            arguments: [
                "repo", "edit", repositorySlug,
                "--visibility", visibility.rawValue,
                "--accept-visibility-change-consequences"
            ]
        )
        guard result.succeeded else {
            throw GitHubServiceError.commandFailed(result.combinedOutput)
        }
    }
}
