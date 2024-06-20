// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "glacier",
    platforms: [
      .iOS(.v14)
    ],
    products: [
        .library(
            name: "glacier",
            targets: ["glacier"]),
    ],
    targets: [
        .target(
            name: "glacier"),
        .testTarget(
            name: "glacierTests",
            dependencies: ["glacier"]),
    ]
)
