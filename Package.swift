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
            name: "DiskHealthCore",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("DiskArbitration"),
                .linkedFramework("CoreFoundation")
            ]
        ),
        .executableTarget(
            name: "diskprobe",
            dependencies: ["DiskHealthCore"]
        )
    ]
)
