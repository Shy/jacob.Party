// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "JasonPartyServer",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.99.0"),
        .package(url: "https://github.com/apple/swift-temporal-sdk.git", from: "0.3.0")
    ],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "Temporal", package: "swift-temporal-sdk")
            ]
        )
    ]
)
