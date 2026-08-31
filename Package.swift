// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Bouncer",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Bouncer", targets: ["Bouncer"])
    ],
    targets: [
        // La logique vit dans une bibliothèque, seule façon qu'une target de test puisse
        // l'importer : une target exécutable n'est pas importable.
        .target(name: "BouncerCore", path: "Sources/BouncerCore"),
        .executableTarget(name: "Bouncer", dependencies: ["BouncerCore"], path: "Sources/Bouncer"),
        .testTarget(name: "BouncerTests", dependencies: ["BouncerCore"], path: "Tests/BouncerTests"),
    ]
)
