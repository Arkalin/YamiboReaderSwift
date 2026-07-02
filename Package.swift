// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "YamiboReader",
    defaultLocalization: "zh-Hans",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(name: "YamiboReaderCore", targets: ["YamiboReaderCore"]),
        .library(name: "YamiboReaderUI", targets: ["YamiboReaderUI"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1"),
        .package(url: "https://github.com/tid-kijyun/Kanna.git", exact: "6.1.0")
    ],
    targets: [
        .target(
            name: "YamiboReaderCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                "Kanna",
            ],
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
                .product(name: "GRDB", package: "GRDB.swift"),
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
