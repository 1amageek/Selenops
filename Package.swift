// swift-tools-version:6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Selenops",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "Selenops", targets: ["Selenops"]),
        .executable(name: "selenops-cli", targets: ["selenopsCLI"])
    ],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.7.7"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.7.0")
    ],
    targets: [
        .target(
            name: "Selenops",
            dependencies: ["SwiftSoup"]),
        .executableTarget(
            name: "selenopsCLI",
            dependencies: [
                "Selenops",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]),
        .testTarget(
            name: "SelenopsTests",
            dependencies: ["Selenops"]
        )
    ]
)
