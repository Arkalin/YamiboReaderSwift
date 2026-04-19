// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "YamiboReaderSwiftPort",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "YamiboReaderCore", targets: ["YamiboReaderCore"]),
        .library(name: "YamiboReaderUI", targets: ["YamiboReaderUI"])
    ],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.13.4")
    ],
    targets: [
        .target(
            name: "YamiboReaderCore",
            dependencies: ["SwiftSoup"]
        ),
        .target(
            name: "YamiboReaderUI",
            dependencies: ["YamiboReaderCore"]
        ),
        .testTarget(
            name: "YamiboReaderCoreTests",
            dependencies: ["YamiboReaderCore"]
        ),
        .testTarget(
            name: "YamiboReaderUITests",
            dependencies: [
                "YamiboReaderCore",
                "YamiboReaderUI",
            ]
        )
    ]
)
