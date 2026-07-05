// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "YamiboReader",
    defaultLocalization: "zh-Hans",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(name: "YamiboReaderCore", targets: ["YamiboReaderCore"]),
        .library(name: "YamiboReaderUI", targets: ["YamiboReaderUI"]),
        .library(name: "YamiboReaderTestSupport", targets: ["YamiboReaderTestSupport"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1"),
        .package(url: "https://github.com/tid-kijyun/Kanna.git", exact: "6.1.0"),
        .package(url: "https://github.com/kean/Nuke", exact: "13.0.6")
    ],
    targets: [
        .target(
            name: "YamiboReaderCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                "Kanna",
                .product(name: "Nuke", package: "Nuke"),
            ],
            resources: [
                .process("Resources")
            ]
        ),
        .target(
            name: "YamiboReaderUI",
            dependencies: [
                "YamiboReaderCore",
                .product(name: "NukeUI", package: "Nuke"),
            ]
        ),
        .target(
            name: "YamiboReaderTestSupport",
            dependencies: [
                "YamiboReaderCore",
            ]
        ),
        .testTarget(
            name: "YamiboReaderCoreTests",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                "YamiboReaderCore",
                "YamiboReaderTestSupport",
            ]
        ),
        .testTarget(
            name: "YamiboReaderUITests",
            dependencies: [
                "YamiboReaderCore",
                "YamiboReaderUI",
                "YamiboReaderTestSupport",
            ]
        )
    ]
)
