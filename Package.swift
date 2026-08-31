// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Bouncer",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Bouncer", targets: ["Bouncer"])
    ],
    targets: [
        .executableTarget(
            name: "Bouncer",
            path: "Sources/Bouncer"
        )
    ]
)
