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
        ),
        .library(
            name: "BenchmarkCore",
            targets: ["BenchmarkCore"]
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
            name: "CBenchIO",
            publicHeadersPath: "include"
        ),
        .target(
            name: "BenchmarkCore",
            dependencies: ["DiskHealthCore", "CBenchIO"]
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
            dependencies: ["DiskHealthCore", "BenchmarkCore"]
        ),
        .executableTarget(
            name: "DiskHealthApp",
            dependencies: ["DiskHealthCore", "BenchmarkCore"]
        ),
        .testTarget(
            name: "BenchmarkCoreTests",
            dependencies: ["BenchmarkCore"]
        ),
        .testTarget(
            name: "DiskHealthCoreTests",
            dependencies: ["DiskHealthCore"],
            resources: [
                .copy("Fixtures")
            ]
        ),
        .testTarget(
            name: "DiskHealthAppTests",
            dependencies: ["DiskHealthApp"]
        ),
        // All tests use Swift Testing. Without Xcode: scripts/test.sh.
        .testTarget(
            name: "AmanDiskTests",
            dependencies: ["DiskHealthCore", "BenchmarkCore", "DiskHealthApp"]
        )
    ]
)
