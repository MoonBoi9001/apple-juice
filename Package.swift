// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "apple-juice",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        .executableTarget(
            name: "apple-juice",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/AppleJuice"
        ),
        .testTarget(
            name: "AppleJuiceTests",
            dependencies: ["apple-juice"],
            path: "Tests/AppleJuiceTests"
        ),
    ]
)
