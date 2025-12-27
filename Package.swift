// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Vectoscoperize",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Vectoscoperize", targets: ["Vectoscoperize"])
    ],
    targets: [
        .executableTarget(
            name: "Vectoscoperize",
            path: "vectoscoperize",
            exclude: [
            ],
            resources: [
                .process("Assets.xcassets"),
                .process("Shaders")
            ]
        )
    ]
)
