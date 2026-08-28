import AppKit
import SwiftUI
#if SWIFT_PACKAGE
import AtlasCore
#endif

// MARK: - 平台真 logo（DESIGN.md §10.4，v7 彩色芯片版）
//
// LobeHub Icons（MIT，github.com/lobehub/lobe-icons）打进 Resources/logos/：
//   Claude    = claude-color.svg（品牌橙，原色渲染）
//   Codex     = openai.svg（OpenAI 标准黑，模板渲染随明暗反色）
//   Gemini    = gemini-color.svg（官方四色渐变，原色渲染）
//   Grok      = xai.svg（xAI 官方 X 标，模板渲染随明暗反色）
//   Cursor    = cursor.svg（Simple Icons 官方晶标，模板渲染随明暗反色）
//   WorkBuddy = workbuddy-trim.png（从官方 app icon 提炼的单色线稿。原图是「绿底 +
//               白线」的完整 app 图标，自带底板、满饱和，混在一排「透明底细笔画标」
//               里过重。流水线：workbuddy.png（母版，留着重制用）
//               → tools/glyphify.swift 按白度抠出线稿成透明底模板图
//               → tools/trimglyph.swift 裁掉透明边并居中进正方画布
//               → 淡底 + 青色线稿（#2BB3A3），和其余芯片同一套语言
//               → glyphScale 0.60 与其余标同墨量）
//   OpenClaw  = openclaw.svg（自绘原创「三道爪痕」glyph，非官方商标——OpenClaw 的
//               龙虾标带商标风险且官方无 press kit，用抽象爪痕规避；模板渲染反色）
//   Qwen      = qwen.svg（LobeHub 单色版。官方彩色版带 linearGradient，CoreSVG
//               渲染不出渐变 defs，所以取单色版 + 品牌紫上色）
//   Doubao    = doubao.svg（LobeHub 单色版，同上，品牌蓝上色）
//   OpenCode  = opencode.svg（LobeHub，官方方中方标，本就是单色）
//   Hermes    = hermes.svg（自绘原创「带翼信使杖」glyph。LobeHub 收的官方标是
//               插画风人物头像，18pt 下糊成一团，也进不了这排几何标的体系）
// 十一个平台全部有标，没有首字母灰块——一排图标里混两个字母块，
// 用户看到的是「这两个没做完」。

enum PlatformBrand {
    struct Spec {
        var file: String
        /// 模板渲染：黑标品牌（OpenAI / xAI）跟随明暗反色；彩标品牌原色渲染
        var template: Bool
        /// 品牌色：芯片底色、点亮描边用
        var tint: Color
        /// 品牌渐变：模板 glyph 用它上色（Gemini 官方蓝紫红；
        /// NSImage 渲染不了 SVG 渐变 defs，所以渐变在 SwiftUI 层做）
        var gradient: [Color]? = nil
        /// glyph 占芯片的比例：按各标的视觉重量配平——
        /// 双子星是细四角星视觉偏小，放大；X 标粗壮，略缩
        var glyphScale: CGFloat = 0.62
        /// 线稿跟品牌色走（WorkBuddy）：淡底 + 青色标，和 Claude/Codex 同一套芯片语言。
        /// 不要实色底板——满饱和绿块会在一排淡色芯片里独重。
        var tintedGlyph: Bool = false
    }

    static func spec(for platform: AgentPlatform) -> Spec? {
        switch platform {
        case .claude: return Spec(file: "claude-color", template: false, tint: Color(hex: 0xD97757))
        case .codex: return Spec(file: "openai", template: true, tint: Color(hex: 0x10A37F))
        case .gemini: return Spec(
            file: "googlegemini", template: true, tint: Color(hex: 0x4285F4),
            gradient: [Color(hex: 0x4285F4), Color(hex: 0x9B72CB), Color(hex: 0xD96570)],
            glyphScale: 0.78
        )
        case .grokbuild: return Spec(file: "xai", template: true, tint: Color(hex: 0x8E8E93), glyphScale: 0.58)
        case .cursor: return Spec(file: "cursor", template: true, tint: Color(hex: 0x5B6CFF), glyphScale: 0.64)
        case .workbuddy: return Spec(
            file: "workbuddy-trim", template: true,
            tint: Color(hex: 0x2BB3A3),
            glyphScale: 0.60,
            tintedGlyph: true
        )
        case .openclaw: return Spec(file: "openclaw", template: true, tint: Color(hex: 0xE8503A), glyphScale: 0.66)
        case .qwenwork: return Spec(
            file: "qwen", template: true, tint: Color(hex: 0x615CED),
            glyphScale: 0.62, tintedGlyph: true
        )
        case .doubao: return Spec(
            file: "doubao", template: true, tint: Color(hex: 0x1E37FC),
            glyphScale: 0.60, tintedGlyph: true
        )
        // 方中方标墨量重，缩到 0.52 才和邻座同重
        case .opencode: return Spec(file: "opencode", template: true, tint: Color(hex: 0x2F9E5F), glyphScale: 0.52)
        // 自绘 glyph 没有「官方色」可对，色相取这一排里还空着的青铜位
        case .hermes: return Spec(file: "hermes", template: true, tint: Color(hex: 0xC08A3E), glyphScale: 0.70)
        }
    }

    private static var cache: [String: NSImage] = [:]

    static func image(for platform: AgentPlatform) -> NSImage? {
        guard let spec = spec(for: platform), !spec.file.isEmpty else { return nil }
        if let cached = cache[spec.file] { return cached }
        let image = loadSVG(named: spec.file)
        if let image {
            image.isTemplate = spec.template
            cache[spec.file] = image
        }
        return image
    }

    /// 先找 .svg，找不到再找 .png（WorkBuddy 这类 CoreSVG 渲染不了的标走栅格版）
    private static func loadSVG(named file: String) -> NSImage? {
        let directories = ["logos", "platform-icons"]
        let types = ["svg", "png"]
        for type in types {
            for directory in directories {
                if let path = Bundle.main.path(forResource: file, ofType: type, inDirectory: directory),
                   let image = NSImage(contentsOfFile: path) {
                    return image
                }
            }
        }
        let fallbacks = types.flatMap { type in
            [
                Bundle.main.resourceURL?.appendingPathComponent("logos/\(file).\(type)"),
                Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/logos/\(file).\(type)"),
            ]
        }
        for url in fallbacks.compactMap({ $0 }) {
            if let image = NSImage(contentsOf: url) { return image }
        }
        return nil
    }
}

/// 平台 logo 芯片：彩色品牌标 + 品牌色淡底（点亮），置灰去色（未挂载）。
/// 列表 18 / 详情 26 / 筛选 22，同一套组件。
struct PlatformLogo: View {
    @Environment(\.colorScheme) private var colorScheme
    var platform: AgentPlatform
    var size: CGFloat = 18
    var lit: Bool = true
    /// 芯片底：logo 独立出现时用；紧凑处（菜单等）可关掉只留 glyph
    var chip: Bool = true

    var body: some View {
        let spec = PlatformBrand.spec(for: platform)
        let dark = colorScheme == .dark
        let shape = RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)

        Group {
            if let image = PlatformBrand.image(for: platform), let spec {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .foregroundStyle(glyphStyle(spec: spec))
                    .saturation(lit ? 1 : 0)
                    .opacity(lit ? 1 : (spec.template ? 0.55 : 0.4))
            } else {
                // 资源缺失兜底：首字母
                Text(String(platform.displayName.prefix(1)))
                    .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                    .foregroundStyle(lit ? Theme.textPrimary : Theme.textTertiary)
            }
        }
        .frame(width: size * (spec?.glyphScale ?? 0.62), height: size * (spec?.glyphScale ?? 0.62))
        .frame(width: chip ? size : size * 0.72, height: chip ? size : size * 0.72)
        .clipShape(shape)
        .background {
            if chip {
                shape.fill(chipFill(spec: spec, dark: dark))
            }
        }
        .overlay {
            if chip {
                shape.strokeBorder(
                    lit ? (spec?.tint ?? .primary).opacity(dark ? 0.30 : 0.20) : Color.primary.opacity(0.06),
                    lineWidth: 0.5
                )
            }
        }
        .accessibilityLabel("\(platform.displayName)\(lit ? "" : "（未挂载）")")
    }

    /// 模板 glyph 上色：点亮时用品牌渐变（Gemini）或主文本色（OpenAI / xAI），
    /// 置灰时统一三级文本色；彩标（Claude）走原图色，这里的样式不生效
    private func glyphStyle(spec: PlatformBrand.Spec) -> AnyShapeStyle {
        guard lit else { return AnyShapeStyle(Theme.textTertiary) }
        if spec.tintedGlyph { return AnyShapeStyle(spec.tint) }
        if let gradient = spec.gradient {
            return AnyShapeStyle(
                LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
            )
        }
        return AnyShapeStyle(Theme.textPrimary)
    }

    private func chipFill(spec: PlatformBrand.Spec?, dark: Bool) -> Color {
        guard lit, let spec else { return Color.primary.opacity(dark ? 0.07 : 0.04) }
        return spec.tint.opacity(dark ? 0.20 : 0.12)
    }
}

/// 列表行内可点击的挂载开关。Atlas 技能单击即建/删软链；其它来源只展示。
struct PlatformStrip: View {
    @Environment(AppStore.self) private var store
    var skill: Skill
    var platforms: [AgentPlatform]
    var size: CGFloat = 18
    var interactive: Bool = true

    var body: some View {
        HStack(spacing: Theme.Space.s4) {
            ForEach(platforms) { platform in
                let lit = skill.platforms.contains(platform.label)
                let togglable = interactive && skill.origin == .atlas && !skill.disabled
                Button {
                    guard togglable else { return }
                    store.setPlatform(skill, platform: platform, enabled: !lit)
                } label: {
                    PlatformLogo(platform: platform, size: size, lit: lit)
                        .contentShape(Rectangle().inset(by: -2))
                }
                .buttonStyle(.plain)
                .disabled(!togglable)
                .help(helpText(platform: platform, lit: lit, togglable: togglable))
            }
        }
        .opacity(skill.disabled ? 0.4 : 1)
    }

    private func helpText(platform: AgentPlatform, lit: Bool, togglable: Bool) -> String {
        if togglable {
            return lit
                ? LF("关掉 %@", platform.displayName)
                : LF("点亮 %@", platform.displayName)
        }
        switch skill.origin {
        case .ccSwitch: return LF("%@：先迁进来才能开关", platform.displayName)
        case .local: return LF("%@：收进本库后才能开关", platform.displayName)
        case .atlas: return LF("%@：已停用，先恢复", platform.displayName)
        }
    }
}

/// 详情头部：logo 开关，无文字 chip
struct PlatformToggleRow: View {
    @Environment(AppStore.self) private var store
    var skill: Skill
    var size: CGFloat = 26

    var body: some View {
        PlatformStrip(skill: skill, platforms: store.visiblePlatforms, size: size, interactive: true)
    }
}

