// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "GitHubDesk",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "GitHubDesk", targets: ["GitHubDesk"])
    ],
    targets: [
        .executableTarget(
            name: "GitHubDesk",
            path: "Sources/GitHubDesk"
        )
    ]
)
