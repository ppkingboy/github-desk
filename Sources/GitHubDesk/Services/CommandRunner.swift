import Foundation

struct CommandResult {
    let executable: String
    let arguments: [String]
    let exitCode: Int32
    let standardOutput: String
    let standardError: String

    var succeeded: Bool { exitCode == 0 }
    var combinedOutput: String {
        [standardOutput, standardError]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum CommandRunnerError: LocalizedError {
    case executableNotFound(String)
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .executableNotFound(let executable):
            return "找不到命令 \(executable)，请确认 macOS Git 工具可用。"
        case .launchFailed(let message):
            return "命令启动失败：\(message)"
        }
    }
}

enum CommandRunner {
    static func executable(named name: String) -> String? {
        let candidates = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)"
        ]

        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func run(
        executable: String,
        arguments: [String],
        workingDirectory: URL? = nil,
        environment: [String: String] = [:]
    ) throws -> CommandResult {
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            throw CommandRunnerError.executableNotFound(executable)
        }

        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("github-desk-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let outputURL = temporaryDirectory.appendingPathComponent("stdout")
        let errorURL = temporaryDirectory.appendingPathComponent("stderr")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        FileManager.default.createFile(atPath: errorURL.path, contents: nil)

        let outputHandle = try FileHandle(forWritingTo: outputURL)
        let errorHandle = try FileHandle(forWritingTo: errorURL)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        if !environment.isEmpty {
            process.environment = ProcessInfo.processInfo.environment.merging(
                environment,
                uniquingKeysWith: { _, new in new }
            )
        }
        process.standardOutput = outputHandle
        process.standardError = errorHandle
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            try? outputHandle.close()
            try? errorHandle.close()
            throw CommandRunnerError.launchFailed(error.localizedDescription)
        }

        try? outputHandle.close()
        try? errorHandle.close()

        let outputData = try Data(contentsOf: outputURL)
        let errorData = try Data(contentsOf: errorURL)

        return CommandResult(
            executable: executable,
            arguments: arguments,
            exitCode: process.terminationStatus,
            standardOutput: String(decoding: outputData, as: UTF8.self),
            standardError: String(decoding: errorData, as: UTF8.self)
        )
    }

    static func run(
        named executableName: String,
        arguments: [String],
        workingDirectory: URL? = nil,
        environment: [String: String] = [:]
    ) throws -> CommandResult {
        guard let executable = executable(named: executableName) else {
            throw CommandRunnerError.executableNotFound(executableName)
        }
        return try run(
            executable: executable,
            arguments: arguments,
            workingDirectory: workingDirectory,
            environment: environment
        )
    }
}
