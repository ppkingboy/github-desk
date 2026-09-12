import Foundation

enum SelfTest {
    static func run() -> Int32 {
        let secretFindings = testSecretScanner()
        let projectBootstrap = testProjectBootstrap()
        let cases: [(String, Bool)] = [
            ("sanitize repository name", RepositoryName.sanitize("My Project!") == "my-project"),
            ("transliterate Chinese repository name", RepositoryName.sanitize("项目") == "xiang-mu"),
            ("parse SSH remote", GitRemoteParser.slug(from: "git@github.com:ppkingboy/loginwebtest.git") == "ppkingboy/loginwebtest"),
            ("parse HTTPS remote", GitRemoteParser.slug(from: "https://github.com/ppkingboy/webportspagehub.git") == "ppkingboy/webportspagehub"),
            ("reject GitLab remote", GitRemoteParser.slug(from: "git@gitlab.com:owner/repository.git") == nil),
            ("configure OAuth client", !OAuthConfiguration.clientID.isEmpty),
            ("detect secret", secretFindings),
            ("bootstrap project", projectBootstrap)
        ]

        var failed = 0
        for (name, passed) in cases {
            print("[\(passed ? "PASS" : "FAIL")] \(name)")
            if !passed { failed += 1 }
        }

        print("\(cases.count - failed)/\(cases.count) checks passed")
        return failed == 0 ? 0 : 1
    }

    private static func testSecretScanner() -> Bool {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("github-desk-self-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let fakeToken = "ghp_" + String(repeating: "a", count: 32)
            try Data("token = \(fakeToken)".utf8)
                .write(to: directory.appendingPathComponent("secret.txt"))
            return try !SecretScanner.scan(repositoryURL: directory).isEmpty
        } catch {
            return false
        }
    }

    private static func testProjectBootstrap() -> Bool {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("github-desk-project-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let account = GitHubAccount(
                id: 1,
                name: "Test User",
                login: "test-user",
                avatarURL: nil
            )
            let repository = try GitService.initializeProject(
                root: directory,
                name: "sample-project",
                description: "Self test",
                account: account
            )
            let root = URL(fileURLWithPath: repository.path, isDirectory: true)
            guard FileManager.default.fileExists(atPath: root.appendingPathComponent("README.md").path),
                  FileManager.default.fileExists(atPath: root.appendingPathComponent(".gitignore").path) else {
                return false
            }
            _ = try GitService.standardize(
                repository: repository,
                accountName: account.displayName,
                includeMITLicense: false
            )
            return FileManager.default.fileExists(
                atPath: root.appendingPathComponent(".github/workflows/ci.yml").path
            )
        } catch {
            return false
        }
    }
}
