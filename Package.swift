// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "macvimium",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "macvimium", targets: ["macvimium"]),
    ],
    targets: [
        .executableTarget(
            name: "macvimium"),
    ]
)
