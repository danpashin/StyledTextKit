// swift-tools-version: 5.4

import PackageDescription

let package = Package(
    name: "StyledTextKit",
    platforms: [
        .iOS(.v12),
    ],
    products: [
        .library(name: "StyledTextKit", targets: ["StyledTextKit"])
    ],
    targets: [
        .target(name: "StyledTextKit", path: "Source", exclude: ["Info.plist"])
    ]
)
