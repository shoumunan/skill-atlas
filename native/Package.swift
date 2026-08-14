// swift-tools-version:5.9
// Skill Atlas 原生版：SwiftPM 构建，仅一个可执行 target。
// 唯一第三方依赖 FluidGradient（MIT，Cindori）：L0 背景的流动渐变光影。
import PackageDescription

let package = Package(
    name: "SkillAtlas",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/Cindori/FluidGradient.git", from: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "SkillAtlas",
            dependencies: [
                .product(name: "FluidGradient", package: "FluidGradient"),
            ],
            path: "swift"
        ),
    ]
)
