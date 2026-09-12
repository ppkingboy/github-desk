import Foundation

struct HealthCheck: Hashable {
    let title: String
    let passed: Bool
}

struct RepositoryHealth: Hashable {
    let checks: [HealthCheck]

    var score: Int {
        guard !checks.isEmpty else { return 0 }
        let passed = checks.filter(\.passed).count
        return Int((Double(passed) / Double(checks.count) * 100).rounded())
    }

    var label: String {
        switch score {
        case 80...: return "良好"
        case 50..<80: return "待完善"
        default: return "需要整理"
        }
    }
}

extension LocalRepository {
    var health: RepositoryHealth {
        let root = URL(fileURLWithPath: path, isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
        let lowercaseFiles = Set(files.map { $0.lowercased() })
        let remoteDescription = remote?.description?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasWorkflow = FileManager.default.fileExists(
            atPath: root.appendingPathComponent(".github/workflows").path
        )

        return RepositoryHealth(checks: [
            HealthCheck(title: "README", passed: lowercaseFiles.contains("readme.md") || lowercaseFiles.contains("readme")),
            HealthCheck(title: "License", passed: lowercaseFiles.contains("license") || lowercaseFiles.contains("license.md")),
            HealthCheck(title: ".gitignore", passed: lowercaseFiles.contains(".gitignore")),
            HealthCheck(title: "项目说明", passed: remoteDescription?.isEmpty == false),
            HealthCheck(title: "Topics", passed: remote?.topics.isEmpty == false),
            HealthCheck(title: "自动化检查", passed: hasWorkflow)
        ])
    }
}
