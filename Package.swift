// swift-tools-version:6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Selenops",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "Selenops", targets: ["Selenops"])
        //        .executable(name: "selenops-cli", targets: ["selenopsCLI"])
    ],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", .upToNextMinor(from: "2.7.5")),
        .package(url: "https://github.com/apple/swift-argument-parser.git", .upToNextMinor(from: "1.5.0"))
    ],
    targets: [
        .target(
            name: "Selenops",
            dependencies: ["SwiftSoup"]),
        //        .target(
        //            name: "selenopsCLI",
        //            dependencies: ["ArgumentParser", "Selenops", "SwiftToolsSupport"])
            .testTarget(
                name: "SelenopsTests",
                dependencies: ["Selenops"]
            )
    ]
)
