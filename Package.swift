// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Screenie",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Screenie", targets: ["Screenie"])
    ],
    targets: [
        .executableTarget(
            name: "Screenie",
            path: "Sources/Screenie",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ImageIO"),
                .linkedFramework("Security"),
                .linkedFramework("UniformTypeIdentifiers")
            ]
        ),
        .testTarget(
            name: "ScreenieTests",
            dependencies: ["Screenie"],
            path: "Tests/ScreenieTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
