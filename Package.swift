// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "LearningCore",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [.library(name: "LearningCore", targets: ["LearningCore"])],
    dependencies: [
        .package(url: "https://github.com/open-spaced-repetition/swift-fsrs.git",
                 revision: "4fbaf20184d62f82a9f44f343337c61a2c5483e9")
    ],
    targets: [
        .target(name: "LearningCore", dependencies: [.product(name: "FSRS", package: "swift-fsrs")],
                resources: [.process("Resources")]),
        .testTarget(name: "LearningCoreTests", dependencies: ["LearningCore"])
    ]
)
