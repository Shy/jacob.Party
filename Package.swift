// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "JasonPartyServer",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.99.0"),
        .package(path: "/Users/shy/Documents/Temporal/swift-temporal-sdk")
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
