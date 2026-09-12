import Foundation

struct GitHubRepository: Codable, Identifiable, Hashable {
    let nameWithOwner: String
    let description: String?
    let isPrivate: Bool
    let visibility: String
    let url: String
    let sshUrl: String?
    let updatedAt: String?
    let defaultBranchRef: BranchReference?
    let primaryLanguage: Language?

    var id: String { nameWithOwner }
    var slug: String { nameWithOwner.lowercased() }
    var name: String { nameWithOwner.split(separator: "/").last.map(String.init) ?? nameWithOwner }
    var owner: String { nameWithOwner.split(separator: "/").first.map(String.init) ?? "" }
    var isPublic: Bool { !isPrivate }
    var defaultBranch: String { defaultBranchRef?.name ?? "main" }
    var shortUpdatedAt: String { updatedAt.map { String($0.prefix(10)) } ?? "未知" }
}

struct BranchReference: Codable, Hashable {
    let name: String
}

struct Language: Codable, Hashable {
    let name: String
}

struct LocalRepository: Identifiable, Hashable {
    let path: String
    let name: String
    let originURL: String?
    let remoteSlug: String?
    let branch: String
    let hasCommits: Bool
    let isDirty: Bool
    let changedFileCount: Int
    let ahead: Int
    let behind: Int
    let hasUpstream: Bool
    let lastCommitDate: String?
    var remote: GitHubRepository?

    var id: String { path }

    var status: RepositoryStatus {
        guard remoteSlug != nil else { return .localOnly }
        guard remote != nil else { return .unmatchedRemote }
        if isDirty || ahead > 0 || behind > 0 { return .needsSync }
        return .synced
    }
}

enum RepositoryStatus {
    case localOnly
    case unmatchedRemote
    case needsSync
    case synced

    var title: String {
        switch self {
        case .localOnly: return "仅本地"
        case .unmatchedRemote: return "远程未匹配"
        case .needsSync: return "待同步"
        case .synced: return "已同步"
        }
    }
}

enum RepositoryVisibility: String, CaseIterable, Identifiable {
    case publicRepository = "public"
    case privateRepository = "private"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .publicRepository: return "公开"
        case .privateRepository: return "私有"
        }
    }
}

enum WorkspaceSection: String, CaseIterable, Identifiable {
    case overview
    case local
    case remote

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "总览"
        case .local: return "本地项目"
        case .remote: return "GitHub 仓库"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .local: return "folder"
        case .remote: return "shippingbox"
        }
    }
}

struct AppAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

struct VisibilityChange: Identifiable {
    let repository: LocalRepository
    let visibility: RepositoryVisibility
    var id: String { repository.id }
}

struct PublishRequest: Identifiable {
    let repository: LocalRepository
    let name: String
    let description: String
    let visibility: RepositoryVisibility
    var id: String { repository.id }
}

struct CommitRequest: Identifiable {
    let repository: LocalRepository
    let message: String
    var id: String { repository.id }
}

enum RepositoryName {
    static func sanitize(_ value: String) -> String {
        let latinValue = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .applyingTransform(.toLatin, reverse: false)?
            .applyingTransform(.stripDiacritics, reverse: false)
            ?? value.trimmingCharacters(in: .whitespacesAndNewlines)

        let lowered = latinValue
            .lowercased()

        var result = ""
        var previousWasSeparator = false

        for character in lowered {
            if character.isLetter || character.isNumber || character == "_" || character == "." {
                result.append(character)
                previousWasSeparator = false
            } else if !previousWasSeparator {
                result.append("-")
                previousWasSeparator = true
            }
        }

        result = result.trimmingCharacters(in: CharacterSet(charactersIn: "-."))
        return result.isEmpty ? "repository" : result
    }
}

enum GitRemoteParser {
    static func slug(from remoteURL: String) -> String? {
        var value = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        if value.hasPrefix("git@github.com:") {
            value = String(value.dropFirst("git@github.com:".count))
        } else if value.hasPrefix("ssh://git@github.com/") {
            value = String(value.dropFirst("ssh://git@github.com/".count))
        } else if let url = URL(string: value), url.host == "github.com" {
            value = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        } else {
            return nil
        }

        if value.hasSuffix(".git") {
            value.removeLast(4)
        }

        let parts = value.split(separator: "/").map(String.init)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else {
            return nil
        }

        return "\(parts[0])/\(parts[1])".lowercased()
    }
}
