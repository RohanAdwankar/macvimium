// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "macvimium",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "MacVimiumCore", targets: ["MacVimiumCore"]),
        .executable(name: "macvimium", targets: ["macvimium"]),
        .executable(name: "maclick", targets: ["maclick"]),
    ],
    targets: [
        .target(
            name: "MacVimiumCore",
            path: "Sources/MacVimiumCore"
        ),
        .executableTarget(
            name: "macvimium",
            dependencies: ["MacVimiumCore"],
            path: "Sources/macvimium-app"
        ),
        .executableTarget(
            name: "maclick",
            dependencies: ["MacVimiumCore"],
            path: "Sources/maclick"
        ),
    ]
)
