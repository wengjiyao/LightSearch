// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "LightSearch",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "LightSearch",
            targets: ["LightSearch"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/stephencelis/SQLite.swift", from: "0.15.0")
    ],
    targets: [
        .executableTarget(
            name: "LightSearch",
            dependencies: [
                .product(name: "SQLite", package: "SQLite.swift")
            ],
            path: "LightSearch",
            resources: [
                .copy("Resources")
            ]
        )
    ]
)
