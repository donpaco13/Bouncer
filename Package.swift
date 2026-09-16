// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Bouncer",
    // Requis par SwiftPM dès qu'une target porte des `.lproj` : c'est la langue de repli
    // pour toute locale que le catalogue ne couvre pas. L'anglais est la voix du produit.
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Bouncer", targets: ["Bouncer"])
    ],
    dependencies: [
        // Error monitoring seul : pas de tracing/profiling, cf. main.swift.
        .package(url: "https://github.com/getsentry/sentry-cocoa", from: "9.28.0")
    ],
    targets: [
        // La logique vit dans une bibliothèque, seule façon qu'une target de test puisse
        // l'importer : une target exécutable n'est pas importable.
        .target(
            name: "BouncerCore",
            path: "Sources/BouncerCore",
            // Le catalogue de chaînes des DEUX targets (cf. Localisation.swift).
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "Bouncer",
            dependencies: [
                "BouncerCore",
                .product(name: "Sentry", package: "sentry-cocoa"),
            ],
            path: "Sources/Bouncer",
            resources: [.process("Resources")]
        ),
        .testTarget(name: "BouncerTests", dependencies: ["BouncerCore"], path: "Tests/BouncerTests"),
    ]
)
