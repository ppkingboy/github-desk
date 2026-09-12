import Foundation

enum GitServiceError: LocalizedError {
    case commandFailed(String)
    case invalidRepository(String)
    case secretsFound([SecretFinding])

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message):
            return message
        case .invalidRepository(let path):
            return "无法识别 Git 仓库：\(path)"
        case .secretsFound(let findings):
            let lines = findings.prefix(8).map { "\($0.path):\($0.line)  \($0.kind)" }
            return "检测到疑似敏感信息，已阻止上传：\n" + lines.joined(separator: "\n")
        }
    }
}

enum GitService {
    private static let skippedDirectories: Set<String> = [
        ".build", ".git", ".swiftpm", "DerivedData", "Library",
        "node_modules", "Pods", "dist", "build", "vendor"
    ]

    static func scan(root: URL) throws -> [LocalRepository] {
        let repositoryRoots = discoverRepositoryRoots(root: root)
        return repositoryRoots.compactMap { try? inspect(repositoryURL: $0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func prepareForPublish(_ repository: LocalRepository, account: GitHubAccount) throws {
        let findings = try SecretScanner.scan(repositoryURL: URL(fileURLWithPath: repository.path))
        guard findings.isEmpty else {
            throw GitServiceError.secretsFound(findings)
        }

        guard !repository.hasCommits else { return }
        let workingDirectory = URL(fileURLWithPath: repository.path)
        try ensureGitIdentity(workingDirectory: workingDirectory, account: account)
        try runGit(["add", "-A"], workingDirectory: workingDirectory)
        try runGit(["commit", "-m", "Initial commit"], workingDirectory: workingDirectory)
    }

    static func attachRemoteAndPush(
        repository: LocalRepository,
        remoteURL: String,
        credential: AccountCredential
    ) throws {
        let workingDirectory = URL(fileURLWithPath: repository.path)
        let existingRemote = try? runRawGit(
            ["remote", "get-url", "origin"],
            workingDirectory: workingDirectory
        )

        if existingRemote == nil {
            try runGit(["remote", "add", "origin", remoteURL], workingDirectory: workingDirectory)
        } else {
            try runGit(["remote", "set-url", "origin", remoteURL], workingDirectory: workingDirectory)
        }

        let branch = repository.branch == "HEAD" ? "main" : repository.branch
        try runGit(
            ["push", "-u", "origin", branch],
            workingDirectory: workingDirectory,
            credential: credential
        )
    }

    static func clone(
        repository: GitHubRepository,
        into root: URL,
        credential: AccountCredential
    ) throws {
        let destination = root.appendingPathComponent(repository.name, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw GitServiceError.commandFailed("目标文件夹已存在：\(destination.path)")
        }

        let environment = try gitEnvironment(credential: credential)
        try requireSuccess(
            CommandRunner.run(
                named: "git",
                arguments: [
                    "-c", "credential.helper=",
                    "clone", "https://github.com/\(repository.fullName).git", destination.path
                ],
                environment: environment
            )
        )
    }

    static func pull(repository: LocalRepository, credential: AccountCredential) throws {
        try ensureOrigin(for: repository)
        try runGit(
            ["pull", "--rebase=false"],
            workingDirectory: URL(fileURLWithPath: repository.path),
            credential: credential
        )
    }

    static func push(repository: LocalRepository, credential: AccountCredential) throws {
        try ensureOrigin(for: repository)
        try runGit(
            ["push"],
            workingDirectory: URL(fileURLWithPath: repository.path),
            credential: credential
        )
    }

    static func disconnectRemote(repository: LocalRepository) throws {
        let workingDirectory = URL(fileURLWithPath: repository.path)
        let remote = try runRawGit(["remote", "get-url", "origin"], workingDirectory: workingDirectory)
        guard remote.succeeded else { return }
        try runGit(["remote", "remove", "origin"], workingDirectory: workingDirectory)
    }

    static func commitAndPush(
        repository: LocalRepository,
        message: String,
        account: GitHubAccount,
        credential: AccountCredential
    ) throws {
        let cleanMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanMessage.isEmpty else {
            throw GitServiceError.commandFailed("提交说明不能为空。")
        }

        let findings = try SecretScanner.scan(repositoryURL: URL(fileURLWithPath: repository.path))
        guard findings.isEmpty else {
            throw GitServiceError.secretsFound(findings)
        }

        let workingDirectory = URL(fileURLWithPath: repository.path)
        try ensureOrigin(for: repository)
        try ensureGitIdentity(workingDirectory: workingDirectory, account: account)
        try runGit(["add", "-A"], workingDirectory: workingDirectory)
        try runGit(["commit", "-m", cleanMessage], workingDirectory: workingDirectory)
        try runGit(
            ["push", "-u", "origin", repository.branch],
            workingDirectory: workingDirectory,
            credential: credential
        )
    }

    static func initializeProject(
        root: URL,
        name: String,
        description: String,
        account: GitHubAccount
    ) throws -> LocalRepository {
        let projectURL = root.appendingPathComponent(name, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: projectURL.path) else {
            throw GitServiceError.commandFailed("目标文件夹已存在：\(projectURL.path)")
        }

        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        try writeProjectTemplates(to: projectURL, name: name, description: description)
        try runGit(["init", "-b", "main"], workingDirectory: projectURL)
        try ensureGitIdentity(workingDirectory: projectURL, account: account)
        try runGit(["add", "-A"], workingDirectory: projectURL)
        try runGit(["commit", "-m", "Initial commit"], workingDirectory: projectURL)
        return try inspect(repositoryURL: projectURL)
    }

    static func standardize(
        repository: LocalRepository,
        accountName: String,
        includeMITLicense: Bool
    ) throws -> [String] {
        let root = URL(fileURLWithPath: repository.path, isDirectory: true)
        let existing = Set((try? FileManager.default.contentsOfDirectory(atPath: repository.path)) ?? [])
        var changes: [String] = []

        if !existing.contains(where: { $0.lowercased() == "readme.md" || $0.lowercased() == "readme" }) {
            let description = repository.remote?.description ?? "项目说明。"
            let readme = "# \(repository.name)\n\n\(description)\n"
            try Data(readme.utf8).write(to: root.appendingPathComponent("README.md"))
            changes.append("README.md")
        }

        if !existing.contains(".gitignore") {
            let gitignore = """
            .DS_Store
            .env
            .env.*
            !.env.example
            .build/
            .swiftpm/
            DerivedData/
            dist/
            node_modules/
            """
            try Data(gitignore.utf8).write(to: root.appendingPathComponent(".gitignore"))
            changes.append(".gitignore")
        }

        if includeMITLicense,
           !existing.contains(where: { $0.lowercased() == "license" || $0.lowercased() == "license.md" }) {
            let year = Calendar.current.component(.year, from: Date())
            let license = """
            MIT License

            Copyright (c) \(year) \(accountName)

            Permission is hereby granted, free of charge, to any person obtaining a copy
            of this software and associated documentation files (the "Software"), to deal
            in the Software without restriction, including without limitation the rights
            to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
            copies of the Software, and to permit persons to whom the Software is
            furnished to do so, subject to the following conditions:

            The above copyright notice and this permission notice shall be included in all
            copies or substantial portions of the Software.

            THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
            IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
            FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
            AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
            LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
            OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
            SOFTWARE.
            """
            try Data(license.utf8).write(to: root.appendingPathComponent("LICENSE"))
            changes.append("LICENSE")
        }

        let workflowDirectory = root.appendingPathComponent(".github/workflows", isDirectory: true)
        if !FileManager.default.fileExists(atPath: workflowDirectory.path) {
            try FileManager.default.createDirectory(at: workflowDirectory, withIntermediateDirectories: true)
            let workflow = """
            name: Repository Check

            on:
              push:
              pull_request:

            jobs:
              verify:
                runs-on: ubuntu-latest
                steps:
                  - uses: actions/checkout@v4
                  - name: Verify repository
                    run: test -f README.md
            """
            try Data(workflow.utf8).write(to: workflowDirectory.appendingPathComponent("ci.yml"))
            changes.append(".github/workflows/ci.yml")
        }

        return changes
    }

    private static func writeProjectTemplates(
        to root: URL,
        name: String,
        description: String
    ) throws {
        let summary = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let readme = "# \(name)\n\n\(summary.isEmpty ? "项目说明。" : summary)\n"
        let gitignore = """
        .DS_Store
        .env
        .env.*
        !.env.example
        .build/
        .swiftpm/
        DerivedData/
        dist/
        node_modules/
        """
        try Data(readme.utf8).write(to: root.appendingPathComponent("README.md"))
        try Data(gitignore.utf8).write(to: root.appendingPathComponent(".gitignore"))
    }

    private static func discoverRepositoryRoots(root: URL) -> [URL] {
        var results: [URL] = []
        let fileManager = FileManager.default

        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsPackageDescendants],
            errorHandler: nil
        ) else {
            return results
        }

        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey]),
                  values.isDirectory == true else {
                continue
            }

            let name = url.lastPathComponent
            let depth = url.pathComponents.count - root.pathComponents.count

            if depth > 4 {
                enumerator.skipDescendants()
                continue
            }

            if name == ".git" {
                enumerator.skipDescendants()
                results.append(url.deletingLastPathComponent())
                continue
            }

            if skippedDirectories.contains(name) || (name.hasPrefix(".") && name != ".git") {
                enumerator.skipDescendants()
            }
        }

        return Array(Set(results)).sorted { $0.path < $1.path }
    }

    private static func inspect(repositoryURL: URL) throws -> LocalRepository {
        let statusResult = try runRawGit(
            ["status", "--porcelain=v1", "--branch"],
            workingDirectory: repositoryURL
        )
        guard statusResult.succeeded else {
            throw GitServiceError.invalidRepository(repositoryURL.path)
        }

        let statusLines = statusResult.standardOutput.components(separatedBy: .newlines)
        let changedLines = statusLines.dropFirst().filter { !$0.isEmpty }
        let branchResult = try runRawGit(
            ["branch", "--show-current"],
            workingDirectory: repositoryURL
        )
        let branch = branchResult.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveBranch = branch.isEmpty ? "HEAD" : branch

        let headResult = try runRawGit(
            ["rev-parse", "--verify", "HEAD"],
            workingDirectory: repositoryURL
        )
        let hasCommits = headResult.succeeded

        let upstreamResult = try runRawGit(
            ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"],
            workingDirectory: repositoryURL
        )
        let hasUpstream = upstreamResult.succeeded
        var ahead = 0
        var behind = 0

        if hasUpstream {
            let divergenceResult = try runRawGit(
                ["rev-list", "--left-right", "--count", "HEAD...@{u}"],
                workingDirectory: repositoryURL
            )
            if divergenceResult.succeeded {
                let parts = divergenceResult.standardOutput
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .split(whereSeparator: \.isWhitespace)
                if parts.count == 2 {
                    ahead = Int(parts[0]) ?? 0
                    behind = Int(parts[1]) ?? 0
                }
            }
        }

        let remoteResult = try runRawGit(
            ["remote", "get-url", "origin"],
            workingDirectory: repositoryURL
        )
        let remoteURL = remoteResult.succeeded
            ? remoteResult.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            : nil

        let commitResult = try runRawGit(
            ["log", "-1", "--format=%cI"],
            workingDirectory: repositoryURL
        )
        let commitDate = commitResult.succeeded
            ? commitResult.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            : nil

        return LocalRepository(
            path: repositoryURL.path,
            name: repositoryURL.lastPathComponent,
            originURL: remoteURL?.isEmpty == false ? remoteURL : nil,
            remoteSlug: remoteURL.flatMap(GitRemoteParser.slug(from:)),
            branch: effectiveBranch,
            hasCommits: hasCommits,
            isDirty: !changedLines.isEmpty,
            changedFileCount: changedLines.count,
            ahead: ahead,
            behind: behind,
            hasUpstream: hasUpstream,
            lastCommitDate: commitDate?.isEmpty == false ? commitDate : nil,
            remote: nil
        )
    }

    private static func runGit(
        _ arguments: [String],
        workingDirectory: URL,
        credential: AccountCredential? = nil
    ) throws {
        var fullArguments = [
            "-c", "credential.helper=",
            "-c", "url.https://github.com/.insteadOf=git@github.com:",
            "-c", "url.https://github.com/.insteadOf=ssh://git@github.com/"
        ]
        fullArguments.append(contentsOf: arguments)

        let environment = try credential.map(gitEnvironment(credential:)) ?? [:]
        try requireSuccess(
            CommandRunner.run(
                named: "git",
                arguments: fullArguments,
                workingDirectory: workingDirectory,
                environment: environment
            )
        )
    }

    private static func runRawGit(
        _ arguments: [String],
        workingDirectory: URL
    ) throws -> CommandResult {
        try CommandRunner.run(
            named: "git",
            arguments: arguments,
            workingDirectory: workingDirectory
        )
    }

    private static func ensureGitIdentity(
        workingDirectory: URL,
        account: GitHubAccount
    ) throws {
        let currentName = try? runRawGit(["config", "--get", "user.name"], workingDirectory: workingDirectory)
        if currentName?.succeeded != true
            || currentName?.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            try runGit(["config", "user.name", account.displayName], workingDirectory: workingDirectory)
        }

        let currentEmail = try? runRawGit(["config", "--get", "user.email"], workingDirectory: workingDirectory)
        if currentEmail?.succeeded != true
            || currentEmail?.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            try runGit(
                ["config", "user.email", "\(account.login)@users.noreply.github.com"],
                workingDirectory: workingDirectory
            )
        }
    }

    @discardableResult
    private static func ensureOrigin(for repository: LocalRepository) throws -> String {
        let workingDirectory = URL(fileURLWithPath: repository.path)
        let current = try runRawGit(
            ["remote", "get-url", "origin"],
            workingDirectory: workingDirectory
        )
        if current.succeeded {
            return current.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let remote = repository.remote else {
            throw GitServiceError.commandFailed(
                "本地仓库没有 origin，且 GitHub 远程仓库不可用。请使用“重新发布”，或在菜单中选择“断开远程连接”。"
            )
        }

        try runGit(
            ["remote", "add", "origin", remote.cloneURL],
            workingDirectory: workingDirectory
        )
        return remote.cloneURL
    }

    private static func gitEnvironment(credential: AccountCredential) throws -> [String: String] {
        let askPassURL = try askPassScriptURL()
        return [
            "GIT_ASKPASS": askPassURL.path,
            "GIT_TERMINAL_PROMPT": "0",
            "GITHUB_DESK_TOKEN": credential.accessToken
        ]
    }

    private static func askPassScriptURL() throws -> URL {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/GitHub Desk/bin", isDirectory: true)
        let scriptURL = directory.appendingPathComponent("git-askpass.sh")

        if !FileManager.default.fileExists(atPath: scriptURL.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let script = """
            #!/bin/sh
            case "$1" in
              *Username*) printf '%s\\n' "x-access-token" ;;
              *Password*) printf '%s\\n' "$GITHUB_DESK_TOKEN" ;;
              *) printf '\\n' ;;
            esac
            """
            try Data(script.utf8).write(to: scriptURL)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)
        }

        return scriptURL
    }

    private static func requireSuccess(_ result: CommandResult) throws {
        guard result.succeeded else {
            throw GitServiceError.commandFailed(result.combinedOutput)
        }
    }
}
