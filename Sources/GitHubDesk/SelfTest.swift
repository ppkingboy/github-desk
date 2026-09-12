import Foundation

enum SelfTest {
    static func run() -> Int32 {
        let cases: [(String, Bool)] = [
            ("sanitize repository name", RepositoryName.sanitize("My Project!") == "my-project"),
            ("transliterate Chinese repository name", RepositoryName.sanitize("项目") == "xiang-mu"),
            ("parse SSH remote", GitRemoteParser.slug(from: "git@github.com:ppkingboy/loginwebtest.git") == "ppkingboy/loginwebtest"),
            ("parse HTTPS remote", GitRemoteParser.slug(from: "https://github.com/ppkingboy/webportspagehub.git") == "ppkingboy/webportspagehub"),
            ("reject GitLab remote", GitRemoteParser.slug(from: "git@gitlab.com:owner/repository.git") == nil)
        ]

        var failed = 0
        for (name, passed) in cases {
            print("[\(passed ? "PASS" : "FAIL")] \(name)")
            if !passed { failed += 1 }
        }

        print("\(cases.count - failed)/\(cases.count) checks passed")
        return failed == 0 ? 0 : 1
    }
}
