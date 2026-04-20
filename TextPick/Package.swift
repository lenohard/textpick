// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TextPick",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/soffes/HotKey", from: "0.2.0"),
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.4.1"),
    ],
    targets: [
        .executableTarget(
            name: "TextPick",
            dependencies: [
                "HotKey",
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
            ],
            path: "Sources/TextPick"
        ),
    ]
)
