import Foundation

struct SecretFinding: Hashable {
    let path: String
    let line: Int
    let kind: String
}

enum SecretScanner {
    private static let skippedDirectories: Set<String> = [
        ".git", ".build", ".swiftpm", "DerivedData", "node_modules", "Pods", "dist", "build", "vendor"
    ]

    private static let binaryExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "pdf", "zip", "gz", "tar", "app", "dylib", "so"
    ]

    private static let patterns: [(kind: String, expression: NSRegularExpression)] = [
        ("私钥", try! NSRegularExpression(pattern: #"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"#)),
        ("AWS Access Key", try! NSRegularExpression(pattern: #"\bAKIA[0-9A-Z]{16}\b"#)),
        ("GitHub Token", try! NSRegularExpression(pattern: #"\b(?:gh[pousr]_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,})\b"#)),
        ("OpenAI Key", try! NSRegularExpression(pattern: #"\bsk-[A-Za-z0-9_-]{20,}\b"#)),
        ("Slack Token", try! NSRegularExpression(pattern: #"\bxox[baprs]-[A-Za-z0-9-]{10,}\b"#)),
        ("Google API Key", try! NSRegularExpression(pattern: #"\bAIza[0-9A-Za-z_-]{30,}\b"#)),
        ("客户端密钥", try! NSRegularExpression(pattern: #"(?i)\bclient_secret\s*[:=]\s*["'][^"']{12,}["']"#))
    ]

    static func scan(repositoryURL: URL) throws -> [SecretFinding] {
        guard let enumerator = FileManager.default.enumerator(
            at: repositoryURL,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsPackageDescendants],
            errorHandler: nil
        ) else {
            return []
        }

        var findings: [SecretFinding] = []

        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            let name = fileURL.lastPathComponent

            if values?.isDirectory == true {
                if skippedDirectories.contains(name) || (name.hasPrefix(".") && name != ".env") {
                    enumerator.skipDescendants()
                }
                continue
            }

            guard (values?.fileSize ?? 0) <= 2_000_000 else { continue }
            let ext = fileURL.pathExtension.lowercased()
            guard !binaryExtensions.contains(ext) else { continue }
            guard let data = try? Data(contentsOf: fileURL),
                  let content = String(data: data, encoding: .utf8) else {
                continue
            }

            for (kind, expression) in patterns {
                let range = NSRange(content.startIndex..<content.endIndex, in: content)
                guard let match = expression.firstMatch(in: content, range: range) else { continue }
                let line = content[..<content.index(content.startIndex, offsetBy: match.range.location)]
                    .filter { $0 == "\n" }
                    .count + 1
                findings.append(SecretFinding(
                    path: fileURL.path.replacingOccurrences(of: repositoryURL.path + "/", with: ""),
                    line: line,
                    kind: kind
                ))
            }
        }

        return findings
    }
}
