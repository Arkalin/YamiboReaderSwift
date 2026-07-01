// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "YamiboReader",
    defaultLocalization: "zh-Hans",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "YamiboReaderCore", targets: ["YamiboReaderCore"]),
        .library(name: "YamiboReaderUI", targets: ["YamiboReaderUI"])
    ],
    dependencies: [
        .package(url: "https://github.com/tid-kijyun/Kanna.git", exact: "6.1.0")
    ],
    targets: [
        .target(
            name: "YamiboReaderCore",
            dependencies: ["Kanna"],
            resources: [
                .process("Resources")
            ]
        ),
        .target(
            name: "YamiboReaderUI",
            dependencies: ["YamiboReaderCore"]
        ),
        .testTarget(
            name: "YamiboReaderCoreTests",
            dependencies: [
                "YamiboReaderCore",
            ]
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
