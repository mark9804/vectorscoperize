// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Vectorscoperize",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Vectorscoperize", targets: ["Vectorscoperize"])
    ],
    targets: [
        .executableTarget(
            name: "Vectorscoperize",
            path: "vectorscoperize",
            exclude: [
            ],
            resources: [
                .process("Assets.xcassets"),
                .process("Shaders")
            ]
        )
    ]
)
