// swift-tools-version:5.9
// 三 target：AtlasCore（引擎，禁 UI 框架）+ atlas（CLI）+ SkillAtlas（App）。
// 引擎类型用 package 访问（同包可见；swiftc 兜底路径下 package ≡ internal）。
// 唯一第三方依赖 FluidGradient（MIT，Cindori）：L0 背景的流动渐变光影。
import PackageDescription

let package = Package(
    name: "SkillAtlas",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/Cindori/FluidGradient.git", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "AtlasCore",
            path: "swift/core"
        ),
        .executableTarget(
            name: "atlas",
            dependencies: ["AtlasCore"],
            path: "swift/cli"
        ),
        .executableTarget(
            name: "SkillAtlas",
            dependencies: [
                "AtlasCore",
                .product(name: "FluidGradient", package: "FluidGradient"),
            ],
            path: "swift/app"
        ),
    ]
)
