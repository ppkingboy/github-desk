import AppKit
import Combine
import Foundation

@MainActor
final class AppStore: ObservableObject {
    @Published var workspaceRootPath: String
    @Published var section: WorkspaceSection? = .overview
    @Published var searchText = ""
    @Published var login = ""
    @Published var localRepositories: [LocalRepository] = []
    @Published var remoteRepositories: [GitHubRepository] = []
    @Published var isRefreshing = false
    @Published var busyRepositoryID: String?
    @Published var alert: AppAlert?
    @Published var toastMessage: String?
    @Published var publishTarget: LocalRepository?
    @Published var commitTarget: LocalRepository?
    @Published var visibilityChange: VisibilityChange?

    private let defaults = UserDefaults.standard
    private let workspaceRootKey = "workspaceRootPath"

    init() {
        let defaultRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents", isDirectory: true)
        workspaceRootPath = defaults.string(forKey: workspaceRootKey) ?? defaultRoot.path
    }

    var filteredLocalRepositories: [LocalRepository] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return localRepositories }
        return localRepositories.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.path.localizedCaseInsensitiveContains(query)
                || ($0.remote?.nameWithOwner.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var remoteOnlyRepositories: [GitHubRepository] {
        let localSlugs = Set(localRepositories.compactMap(\.remoteSlug))
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        return remoteRepositories.filter { repository in
            guard !localSlugs.contains(repository.slug) else { return false }
            guard !query.isEmpty else { return true }
            return repository.nameWithOwner.localizedCaseInsensitiveContains(query)
                || (repository.description?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var localOnlyCount: Int {
        localRepositories.filter { $0.status == .localOnly }.count
    }

    var needsAttentionCount: Int {
        localRepositories.filter { $0.status == .needsSync || $0.status == .unmatchedRemote }.count
    }

    var syncedCount: Int {
        localRepositories.filter { $0.status == .synced }.count
    }

    var attentionRepositories: [LocalRepository] {
        localRepositories.filter { $0.status != .synced }
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        let root = URL(fileURLWithPath: workspaceRootPath, isDirectory: true)

        Task {
            do {
                let snapshot = try await Task.detached(priority: .userInitiated) {
                    let github = try GitHubService.loadSnapshot()
                    let local = try GitService.scan(root: root)
                    return RepositorySnapshot(local: local, github: github)
                }.value

                login = snapshot.github.login
                remoteRepositories = snapshot.github.repositories

                let remoteMap = Dictionary(
                    uniqueKeysWithValues: snapshot.github.repositories.map { ($0.slug, $0) }
                )
                localRepositories = snapshot.local.map { repository in
                    var updated = repository
                    updated.remote = repository.remoteSlug.flatMap { remoteMap[$0] }
                    return updated
                }
            } catch {
                alert = AppAlert(title: "刷新失败", message: error.localizedDescription)
            }

            isRefreshing = false
        }
    }

    func chooseWorkspace() {
        let panel = NSOpenPanel()
        panel.title = "选择本地项目目录"
        panel.message = "GitHub Desk 会扫描此目录中的 Git 仓库。"
        panel.prompt = "选择"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: workspaceRootPath, isDirectory: true)

        guard panel.runModal() == .OK, let url = panel.url else { return }
        workspaceRootPath = url.path
        defaults.set(url.path, forKey: workspaceRootKey)
        refresh()
    }

    func reveal(_ repository: LocalRepository) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: repository.path)])
    }

    func openOnGitHub(_ repository: LocalRepository) {
        guard let urlString = repository.remote?.url, let url = URL(string: urlString) else {
            alert = AppAlert(title: "没有远程仓库", message: "这个项目还没有匹配到 GitHub 仓库。")
            return
        }
        NSWorkspace.shared.open(url)
    }

    func openOnGitHub(_ repository: GitHubRepository) {
        guard let url = URL(string: repository.url) else { return }
        NSWorkspace.shared.open(url)
    }

    func clone(_ repository: GitHubRepository) {
        perform(
            repositoryID: repository.id,
            success: "已克隆 \(repository.nameWithOwner)",
            operation: {
                try GitService.clone(
                    repository: repository,
                    into: URL(fileURLWithPath: self.workspaceRootPath, isDirectory: true)
                )
            }
        )
    }

    func publish(_ request: PublishRequest) {
        let sanitizedName = RepositoryName.sanitize(request.name)
        perform(
            repositoryID: request.repository.id,
            success: "已发布 \(request.repository.name)",
            operation: {
                try GitService.publish(
                    repository: request.repository,
                    owner: self.login,
                    repositoryName: sanitizedName,
                    description: request.description,
                    visibility: request.visibility
                )
            }
        )
    }

    func commitAndPush(_ request: CommitRequest) {
        perform(
            repositoryID: request.repository.id,
            success: "已提交并推送 \(request.repository.name)",
            operation: {
                try GitService.commitAndPush(
                    repository: request.repository,
                    message: request.message
                )
            }
        )
    }

    func pull(_ repository: LocalRepository) {
        perform(
            repositoryID: repository.id,
            success: "已拉取 \(repository.name)",
            operation: { try GitService.pull(repository: repository) }
        )
    }

    func push(_ repository: LocalRepository) {
        perform(
            repositoryID: repository.id,
            success: "已推送 \(repository.name)",
            operation: { try GitService.push(repository: repository) }
        )
    }

    func confirmVisibilityChange(_ change: VisibilityChange) {
        guard let repositorySlug = change.repository.remote?.nameWithOwner else { return }
        perform(
            repositoryID: change.repository.id,
            success: "已将 \(change.repository.name) 设为\(change.visibility.title)",
            operation: {
                try GitHubService.setVisibility(
                    repositorySlug: repositorySlug,
                    visibility: change.visibility
                )
            }
        )
    }

    func dismissToast() {
        toastMessage = nil
    }

    private func perform(
        repositoryID: String,
        success: String,
        operation: @escaping () throws -> Void
    ) {
        guard busyRepositoryID == nil else { return }
        busyRepositoryID = repositoryID

        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try operation()
                }.value
                toastMessage = success
                refresh()
            } catch {
                alert = AppAlert(title: "操作失败", message: error.localizedDescription)
            }

            busyRepositoryID = nil
        }
    }
}

private struct RepositorySnapshot {
    let local: [LocalRepository]
    let github: GitHubSnapshot
}
