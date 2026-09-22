// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "DiskHealth",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "DiskHealthCore",
            targets: ["DiskHealthCore"]
        )
    ],
    targets: [
        .target(
            name: "CDiskIO",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreFoundation")
            ]
        ),
        .target(
            name: "DiskHealthCore",
            dependencies: ["CDiskIO"],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("DiskArbitration"),
                .linkedFramework("CoreFoundation")
            ]
        ),
        .executableTarget(
            name: "diskprobe",
            dependencies: ["DiskHealthCore"]
        ),
        .executableTarget(
            name: "DiskHealthApp",
            dependencies: ["DiskHealthCore"]
        ),
        .testTarget(
            name: "DiskHealthCoreTests",
            dependencies: ["DiskHealthCore"],
            resources: [
                .copy("Fixtures")
            ]
        )
    ]
)
