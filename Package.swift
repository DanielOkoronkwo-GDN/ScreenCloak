// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "ScreenCloak",
    platforms: [
        .iOS("18.0")
    ],
    products: [
        .library(
            name: "ScreenCloak",
            targets: ["ScreenCloak"]
        ),
    ],
    targets: [
        .target(
            name: "ScreenCloak"
        ),
        .testTarget(
            name: "ScreenCloakTests",
            dependencies: ["ScreenCloak"]
        ),
    ]
)
