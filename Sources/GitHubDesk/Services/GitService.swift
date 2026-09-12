import Foundation

enum GitServiceError: LocalizedError {
    case commandFailed(String)
    case invalidRepository(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message):
            return message
        case .invalidRepository(let path):
            return "无法识别 Git 仓库：\(path)"
        }
    }
}

enum GitService {
    private static let skippedDirectories: Set<String> = [
        ".build",
        ".git",
        ".swiftpm",
        "DerivedData",
        "Library",
        "node_modules",
        "Pods",
        "dist",
        "build"
    ]

    static func scan(root: URL) throws -> [LocalRepository] {
        let repositoryRoots = discoverRepositoryRoots(root: root)
        return repositoryRoots.compactMap { try? inspect(repositoryURL: $0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func publish(
        repository: LocalRepository,
        owner: String,
        repositoryName: String,
        description: String,
        visibility: RepositoryVisibility
    ) throws {
        if !repository.hasCommits {
            let workingDirectory = URL(fileURLWithPath: repository.path)
            try requireSuccess(
                CommandRunner.run(
                    named: "git",
                    arguments: ["add", "-A"],
                    workingDirectory: workingDirectory
                )
            )
            try requireSuccess(
                CommandRunner.run(
                    named: "git",
                    arguments: ["commit", "-m", "Initial commit"],
                    workingDirectory: workingDirectory
                )
            )
        }

        let visibilityFlag = visibility == .publicRepository ? "--public" : "--private"
        var arguments = [
            "repo", "create", "\(owner)/\(repositoryName)",
            visibilityFlag,
            "--source", repository.path,
            "--remote", "origin",
            "--push"
        ]

        let cleanDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanDescription.isEmpty {
            arguments.append(contentsOf: ["--description", cleanDescription])
        }

        let result = try CommandRunner.run(named: "gh", arguments: arguments)
        guard result.succeeded else {
            throw GitServiceError.commandFailed(result.combinedOutput)
        }
    }

    static func clone(repository: GitHubRepository, into root: URL) throws {
        let destination = root.appendingPathComponent(repository.name, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw GitServiceError.commandFailed("目标文件夹已存在：\(destination.path)")
        }

        let result = try CommandRunner.run(
            named: "gh",
            arguments: ["repo", "clone", repository.nameWithOwner, destination.path]
        )
        guard result.succeeded else {
            throw GitServiceError.commandFailed(result.combinedOutput)
        }
    }

    static func pull(repository: LocalRepository) throws {
        try requireSuccess(
            CommandRunner.run(
                named: "git",
                arguments: ["pull", "--rebase=false"],
                workingDirectory: URL(fileURLWithPath: repository.path)
            )
        )
    }

    static func push(repository: LocalRepository) throws {
        try requireSuccess(
            CommandRunner.run(
                named: "git",
                arguments: ["push"],
                workingDirectory: URL(fileURLWithPath: repository.path)
            )
        )
    }

    static func commitAndPush(repository: LocalRepository, message: String) throws {
        let cleanMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanMessage.isEmpty else {
            throw GitServiceError.commandFailed("提交说明不能为空。")
        }

        let workingDirectory = URL(fileURLWithPath: repository.path)
        try requireSuccess(
            CommandRunner.run(
                named: "git",
                arguments: ["add", "-A"],
                workingDirectory: workingDirectory
            )
        )
        try requireSuccess(
            CommandRunner.run(
                named: "git",
                arguments: ["commit", "-m", cleanMessage],
                workingDirectory: workingDirectory
            )
        )
        try requireSuccess(
            CommandRunner.run(
                named: "git",
                arguments: ["push", "-u", "origin", repository.branch],
                workingDirectory: workingDirectory
            )
        )
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
        let statusResult = try CommandRunner.run(
            named: "git",
            arguments: ["status", "--porcelain=v1", "--branch"],
            workingDirectory: repositoryURL
        )
        guard statusResult.succeeded else {
            throw GitServiceError.invalidRepository(repositoryURL.path)
        }

        let statusLines = statusResult.standardOutput.components(separatedBy: .newlines)
        let changedLines = statusLines.dropFirst().filter { !$0.isEmpty }
        let branchResult = try CommandRunner.run(
            named: "git",
            arguments: ["branch", "--show-current"],
            workingDirectory: repositoryURL
        )
        let branch = branchResult.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveBranch = branch.isEmpty ? "HEAD" : branch

        let headResult = try CommandRunner.run(
            named: "git",
            arguments: ["rev-parse", "--verify", "HEAD"],
            workingDirectory: repositoryURL
        )
        let hasCommits = headResult.succeeded

        let upstreamResult = try CommandRunner.run(
            named: "git",
            arguments: ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"],
            workingDirectory: repositoryURL
        )
        let hasUpstream = upstreamResult.succeeded
        var ahead = 0
        var behind = 0

        if hasUpstream {
            let divergenceResult = try CommandRunner.run(
                named: "git",
                arguments: ["rev-list", "--left-right", "--count", "HEAD...@{u}"],
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

        let remoteResult = try CommandRunner.run(
            named: "git",
            arguments: ["remote", "get-url", "origin"],
            workingDirectory: repositoryURL
        )
        let remoteURL = remoteResult.succeeded
            ? remoteResult.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            : nil

        let commitResult = try CommandRunner.run(
            named: "git",
            arguments: ["log", "-1", "--format=%cI"],
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

    private static func requireSuccess(_ result: CommandResult) throws {
        guard result.succeeded else {
            throw GitServiceError.commandFailed(result.combinedOutput)
        }
    }
}
