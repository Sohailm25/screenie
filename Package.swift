// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SnapText",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "SnapText", targets: ["SnapText"])
    ],
    targets: [
        .executableTarget(
            name: "SnapText",
            path: "Sources/SnapText",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ImageIO"),
                .linkedFramework("Security"),
                .linkedFramework("UniformTypeIdentifiers")
            ]
        ),
        .testTarget(
            name: "SnapTextTests",
            dependencies: ["SnapText"],
            path: "Tests/SnapTextTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
