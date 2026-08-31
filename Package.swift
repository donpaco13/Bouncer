// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "IslandSwitch",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "IslandSwitch", targets: ["IslandSwitch"])
    ],
    targets: [
        .executableTarget(
            name: "IslandSwitch",
            path: "Sources/IslandSwitch"
        )
    ]
)
