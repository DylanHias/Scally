// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ScallyKit",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "ScallyKit", targets: ["ScallyKit"])
    ],
    targets: [
        .target(
            name: "ScallyKit",
            resources: [
                .copy("Resources/RealESRNet.mlpackage"),
                .copy("Resources/NomosWebPhoto.mlpackage"),
                .copy("Resources/NomosPLKSR.mlpackage"),
                .copy("Resources/MoSR.mlpackage"),
            ]
        ),
        .testTarget(name: "ScallyKitTests", dependencies: ["ScallyKit"])
    ]
)
