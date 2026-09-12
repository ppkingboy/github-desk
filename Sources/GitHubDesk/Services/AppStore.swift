import AppKit
import Combine
import Foundation

struct LoginPresentation: Identifiable {
    let id = UUID()
    let userCode: String
    let verificationURI: String
}

struct BatchSyncReport: Identifiable {
    let id = UUID()
    let succeeded: [String]
    let skipped: [String]
    let failed: [String]
}

@MainActor
final class AppStore: ObservableObject {
    @Published var workspaceRootPath: String
    @Published var section: WorkspaceSection? = .overview
    @Published var searchText = ""
    @Published var accounts: [GitHubAccount] = []
    @Published var currentAccountID: Int?
    @Published var loginPresentation: LoginPresentation?
    @Published var isLoggingIn = false
    @Published var localRepositories: [LocalRepository] = []
    @Published var remoteRepositories: [GitHubRepository] = []
    @Published var isRefreshing = false
    @Published var busyRepositoryID: String?
    @Published var alert: AppAlert?
    @Published var toastMessage: String?
    @Published var publishTarget: LocalRepository?
    @Published var commitTarget: LocalRepository?
    @Published var visibilityChange: VisibilityChange?
    @Published var batchSyncReport: BatchSyncReport?

    private let defaults = UserDefaults.standard
    private let workspaceRootKey = "workspaceRootPath"
    private let accountsKey = "githubAccounts"
    private let currentAccountKey = "currentGitHubAccountID"
    private var loginTask: Task<Void, Never>?

    init() {
        let defaultRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents", isDirectory: true)
        workspaceRootPath = defaults.string(forKey: workspaceRootKey) ?? defaultRoot.path
        accounts = loadAccounts()
        currentAccountID = defaults.object(forKey: currentAccountKey) as? Int
        if currentAccountID == nil {
            currentAccountID = accounts.first?.id
        }
    }

    var currentAccount: GitHubAccount? {
        guard let currentAccountID else { return accounts.first }
        return accounts.first { $0.id == currentAccountID } ?? accounts.first
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
        let account = currentAccount

        Task {
            do {
                let local = try await Task.detached(priority: .userInitiated) {
                    try GitService.scan(root: root)
                }.value

                var remote: [GitHubRepository] = []
                if let account {
                    let credential = try await validCredential(for: account)
                    remote = try await GitHubAPIClient(accessToken: credential.accessToken)
                        .repositories()
                }

                let remoteMap = Dictionary(uniqueKeysWithValues: remote.map { ($0.slug, $0) })
                localRepositories = local.map { repository in
                    var updated = repository
                    updated.remote = repository.remoteSlug.flatMap { remoteMap[$0] }
                    return updated
                }
                remoteRepositories = remote
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

    func beginLogin() {
        guard loginTask == nil else { return }
        isLoggingIn = true

        loginTask = Task {
            do {
                let deviceCode = try await GitHubOAuthService.requestDeviceCode()
                loginPresentation = LoginPresentation(
                    userCode: deviceCode.userCode,
                    verificationURI: deviceCode.verificationURI
                )

                if let url = URL(string: deviceCode.verificationURI) {
                    NSWorkspace.shared.open(url)
                }

                let token = try await GitHubOAuthService.pollForToken(
                    deviceCode: deviceCode.deviceCode,
                    interval: deviceCode.interval,
                    expiresIn: deviceCode.expiresIn
                )
                guard let accessToken = token.accessToken else {
                    throw GitHubOAuthError.invalidResponse("缺少访问令牌")
                }

                let account = try await GitHubAPIClient(accessToken: accessToken).currentUser()
                let credential = AccountCredential(
                    accessToken: accessToken,
                    refreshToken: token.refreshToken,
                    expiresAt: token.expiresIn.map { Date().addingTimeInterval(TimeInterval($0)) },
                    scope: token.scope
                )
                try KeychainStore.save(credential, accountID: account.id)

                if let index = accounts.firstIndex(where: { $0.id == account.id }) {
                    accounts[index] = account
                } else {
                    accounts.append(account)
                }
                currentAccountID = account.id
                persistAccounts()
                loginPresentation = nil
                toastMessage = "已登录 \(account.login)"
                refresh()
            } catch is CancellationError {
                loginPresentation = nil
            } catch {
                loginPresentation = nil
                alert = AppAlert(title: "登录失败", message: error.localizedDescription)
            }

            isLoggingIn = false
            loginTask = nil
        }
    }

    func cancelLogin() {
        loginTask?.cancel()
        loginTask = nil
        loginPresentation = nil
        isLoggingIn = false
    }

    func switchAccount(to account: GitHubAccount) {
        currentAccountID = account.id
        defaults.set(account.id, forKey: currentAccountKey)
        localRepositories = localRepositories.map { repository in
            var updated = repository
            updated.remote = nil
            return updated
        }
        remoteRepositories = []
        refresh()
    }

    func removeAccount(_ account: GitHubAccount) {
        try? KeychainStore.delete(accountID: account.id)
        accounts.removeAll { $0.id == account.id }
        if currentAccountID == account.id {
            currentAccountID = accounts.first?.id
        }
        persistAccounts()
        remoteRepositories = []
        localRepositories = localRepositories.map { repository in
            var updated = repository
            updated.remote = nil
            return updated
        }
        if currentAccount != nil { refresh() }
    }

    func accountCandidate(for repository: LocalRepository) -> GitHubAccount? {
        if let owner = repository.remote?.owner,
           let account = accounts.first(where: { $0.login.caseInsensitiveCompare(owner) == .orderedSame }) {
            return account
        }
        return currentAccount
    }

    func reveal(_ repository: LocalRepository) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: repository.path)])
    }

    func openOnGitHub(_ repository: LocalRepository) {
        guard let urlString = repository.remote?.htmlURL, let url = URL(string: urlString) else {
            alert = AppAlert(title: "没有远程仓库", message: "这个项目还没有匹配到 GitHub 仓库。")
            return
        }
        NSWorkspace.shared.open(url)
    }

    func openOnGitHub(_ repository: GitHubRepository) {
        guard let url = URL(string: repository.htmlURL) else { return }
        NSWorkspace.shared.open(url)
    }

    func clone(_ repository: GitHubRepository, account: GitHubAccount) {
        let workspaceRoot = URL(fileURLWithPath: workspaceRootPath, isDirectory: true)
        perform(
            repositoryID: repository.idString,
            success: "已克隆 \(repository.nameWithOwner)",
            operation: {
                let credential = try await self.validCredential(for: account)
                try await Task.detached(priority: .userInitiated) {
                    try GitService.clone(
                        repository: repository,
                        into: workspaceRoot,
                        credential: credential
                    )
                }.value
            }
        )
    }

    func publish(_ request: PublishRequest, account: GitHubAccount) {
        let sanitizedName = RepositoryName.sanitize(request.name)
        perform(
            repositoryID: request.repository.id,
            success: "已发布 \(request.repository.name)",
            operation: {
                try await Task.detached(priority: .userInitiated) {
                    try GitService.prepareForPublish(request.repository, account: account)
                }.value

                let credential = try await self.validCredential(for: account)
                try self.requireWorkflowScopeIfNeeded(
                    repository: request.repository,
                    credential: credential
                )
                let repository = try await GitHubAPIClient(accessToken: credential.accessToken)
                    .createRepository(
                        name: sanitizedName,
                        description: request.description,
                        isPrivate: request.visibility == .privateRepository
                    )

                try await Task.detached(priority: .userInitiated) {
                    try GitService.attachRemoteAndPush(
                        repository: request.repository,
                        remoteURL: repository.cloneURL,
                        credential: credential
                    )
                }.value
            }
        )
    }

    func commitAndPush(_ request: CommitRequest) {
        guard let account = accountCandidate(for: request.repository) else {
            promptForAccount()
            return
        }

        perform(
            repositoryID: request.repository.id,
            success: "已提交并推送 \(request.repository.name)",
            operation: {
                let credential = try await self.validCredential(for: account)
                try self.requireWorkflowScopeIfNeeded(
                    repository: request.repository,
                    credential: credential
                )
                try await Task.detached(priority: .userInitiated) {
                    try GitService.commitAndPush(
                        repository: request.repository,
                        message: request.message,
                        account: account,
                        credential: credential
                    )
                }.value
            }
        )
    }

    func pull(_ repository: LocalRepository) {
        guard let account = accountCandidate(for: repository) else {
            promptForAccount()
            return
        }
        perform(
            repositoryID: repository.id,
            success: "已拉取 \(repository.name)",
            operation: {
                let credential = try await self.validCredential(for: account)
                try await Task.detached(priority: .userInitiated) {
                    try GitService.pull(repository: repository, credential: credential)
                }.value
            }
        )
    }

    func push(_ repository: LocalRepository) {
        guard let account = accountCandidate(for: repository) else {
            promptForAccount()
            return
        }
        perform(
            repositoryID: repository.id,
            success: "已推送 \(repository.name)",
            operation: {
                let credential = try await self.validCredential(for: account)
                try self.requireWorkflowScopeIfNeeded(
                    repository: repository,
                    credential: credential
                )
                try await Task.detached(priority: .userInitiated) {
                    try GitService.push(repository: repository, credential: credential)
                }.value
            }
        )
    }

    func disconnectRemote(_ repository: LocalRepository) {
        perform(
            repositoryID: repository.id,
            success: "已断开 \(repository.name) 的远程连接",
            operation: {
                try await Task.detached(priority: .userInitiated) {
                    try GitService.disconnectRemote(repository: repository)
                }.value
            }
        )
    }

    func confirmVisibilityChange(_ change: VisibilityChange) {
        guard let account = accountCandidate(for: change.repository) else {
            promptForAccount()
            return
        }
        guard let repositorySlug = change.repository.remote?.fullName else { return }

        perform(
            repositoryID: change.repository.id,
            success: "已将 \(change.repository.name) 设为\(change.visibility.title)",
            operation: {
                let credential = try await self.validCredential(for: account)
                try await GitHubAPIClient(accessToken: credential.accessToken)
                    .updateVisibility(
                        repositorySlug: repositorySlug,
                        isPrivate: change.visibility == .privateRepository
                    )
            }
        )
    }

    func standardize(_ repository: LocalRepository, includeMITLicense: Bool) {
        guard let account = accountCandidate(for: repository) else {
            promptForAccount()
            return
        }

        perform(
            repositoryID: repository.id,
            success: "已补齐 \(repository.name) 的基础文件",
            operation: {
                let changes = try await Task.detached(priority: .userInitiated) {
                    try GitService.standardize(
                        repository: repository,
                        accountName: account.displayName,
                        includeMITLicense: includeMITLicense
                    )
                }.value

                if let remote = repository.remote {
                    let credential = try await self.validCredential(for: account)
                    let client = GitHubAPIClient(accessToken: credential.accessToken)
                    if remote.description?.isEmpty != false {
                        try await client.updateMetadata(
                            repositorySlug: remote.fullName,
                            description: "A repository for \(repository.name).",
                            homepage: nil
                        )
                    }
                    if remote.topics.isEmpty {
                        let languageTopic = remote.language?.lowercased().replacingOccurrences(of: " ", with: "-")
                        try await client.updateTopics(
                            repositorySlug: remote.fullName,
                            topics: [languageTopic, "repository"].compactMap { $0 }
                        )
                    }
                }

                if changes.isEmpty {
                    self.toastMessage = "仓库基础文件已经完整"
                }
            }
        )
    }

    func batchSync() {
        guard busyRepositoryID == nil else { return }
        busyRepositoryID = "batch"

        Task {
            var succeeded: [String] = []
            var skipped: [String] = []
            var failed: [String] = []

            for repository in localRepositories where repository.remote != nil {
                if repository.isDirty || (repository.ahead > 0 && repository.behind > 0) {
                    skipped.append("\(repository.name)：存在未提交修改或分叉")
                    continue
                }

                guard let account = accountCandidate(for: repository) else {
                    skipped.append("\(repository.name)：没有可用账号")
                    continue
                }

                do {
                    let credential = try await validCredential(for: account)
                    if repository.behind > 0 {
                        try await Task.detached(priority: .userInitiated) {
                            try GitService.pull(repository: repository, credential: credential)
                        }.value
                        succeeded.append("\(repository.name)：已拉取")
                    } else if repository.ahead > 0 {
                        try self.requireWorkflowScopeIfNeeded(
                            repository: repository,
                            credential: credential
                        )
                        try await Task.detached(priority: .userInitiated) {
                            try GitService.push(repository: repository, credential: credential)
                        }.value
                        succeeded.append("\(repository.name)：已推送")
                    } else {
                        skipped.append("\(repository.name)：无需同步")
                    }
                } catch {
                    failed.append("\(repository.name)：\(error.localizedDescription)")
                }
            }

            busyRepositoryID = nil
            batchSyncReport = BatchSyncReport(
                succeeded: succeeded,
                skipped: skipped,
                failed: failed
            )
            refresh()
        }
    }

    func createProject(
        name: String,
        description: String,
        visibility: RepositoryVisibility,
        account: GitHubAccount
    ) {
        let sanitizedName = RepositoryName.sanitize(name)
        let workspaceRoot = URL(fileURLWithPath: workspaceRootPath, isDirectory: true)
        perform(
            repositoryID: "new-project",
            success: "已创建并发布 \(sanitizedName)",
            operation: {
                let localRepository = try await Task.detached(priority: .userInitiated) {
                    try GitService.initializeProject(
                        root: workspaceRoot,
                        name: sanitizedName,
                        description: description,
                        account: account
                    )
                }.value

                let credential = try await self.validCredential(for: account)
                let repository = try await GitHubAPIClient(accessToken: credential.accessToken)
                    .createRepository(
                        name: sanitizedName,
                        description: description,
                        isPrivate: visibility == .privateRepository
                    )

                try await Task.detached(priority: .userInitiated) {
                    try GitService.attachRemoteAndPush(
                        repository: localRepository,
                        remoteURL: repository.cloneURL,
                        credential: credential
                    )
                }.value
            }
        )
    }

    func dismissToast() {
        toastMessage = nil
    }

    private func promptForAccount() {
        alert = AppAlert(
            title: "需要 GitHub 账号",
            message: "请先在“账号管理”中添加并选择一个 GitHub 账号。"
        )
    }

    private func validCredential(for account: GitHubAccount) async throws -> AccountCredential {
        guard let credential = try KeychainStore.load(accountID: account.id) else {
            throw GitHubOAuthError.invalidResponse("没有找到 \(account.login) 的登录信息")
        }

        guard let expiresAt = credential.expiresAt,
              expiresAt.timeIntervalSinceNow < 300,
              let refreshToken = credential.refreshToken else {
            return credential
        }

        let refreshed = try await GitHubOAuthService.refresh(refreshToken: refreshToken)
        guard let accessToken = refreshed.accessToken else {
            throw GitHubOAuthError.invalidResponse("刷新响应缺少访问令牌")
        }

        let updated = AccountCredential(
            accessToken: accessToken,
            refreshToken: refreshed.refreshToken ?? refreshToken,
            expiresAt: refreshed.expiresIn.map { Date().addingTimeInterval(TimeInterval($0)) },
            scope: refreshed.scope ?? credential.scope
        )
        try KeychainStore.save(updated, accountID: account.id)
        return updated
    }

    private func requireWorkflowScopeIfNeeded(
        repository: LocalRepository,
        credential: AccountCredential
    ) throws {
        guard repository.hasWorkflowFiles,
              !credential.scopes.contains("workflow") else {
            return
        }
        throw GitHubOAuthError.missingScope("workflow")
    }

    private func perform(
        repositoryID: String,
        success: String,
        operation: @escaping () async throws -> Void
    ) {
        guard busyRepositoryID == nil else { return }
        busyRepositoryID = repositoryID

        Task {
            do {
                try await operation()
                toastMessage = success
                refresh()
            } catch {
                alert = AppAlert(title: "操作失败", message: error.localizedDescription)
            }

            busyRepositoryID = nil
        }
    }

    private func loadAccounts() -> [GitHubAccount] {
        guard let data = defaults.data(forKey: accountsKey) else { return [] }
        return (try? JSONDecoder().decode([GitHubAccount].self, from: data)) ?? []
    }

    private func persistAccounts() {
        let data = try? JSONEncoder().encode(accounts)
        defaults.set(data, forKey: accountsKey)
        defaults.set(currentAccountID, forKey: currentAccountKey)
    }
}
