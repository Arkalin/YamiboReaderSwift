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
    targets: [
        .target(
            name: "YamiboReaderCore"
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
