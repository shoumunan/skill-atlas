import AppKit
import SwiftUI

// MARK: - 平台真 logo（DESIGN.md §10.4，v7 彩色芯片版）
//
// LobeHub Icons（MIT，github.com/lobehub/lobe-icons）打进 Resources/logos/：
//   Claude    = claude-color.svg（品牌橙，原色渲染）
//   Codex     = openai.svg（OpenAI 标准黑，模板渲染随明暗反色）
//   Gemini    = gemini-color.svg（官方四色渐变，原色渲染）
//   Grok      = xai.svg（xAI 官方 X 标，模板渲染随明暗反色）
//   WorkBuddy = workbuddy-trim.png（从官方 app icon 提炼的单色线稿。原图是「绿底 +
//               白线」的完整 app 图标，自带底板、满饱和，混在一排「透明底细笔画标」
//               里过重。流水线：workbuddy.png（母版，留着重制用）
//               → tools/glyphify.swift 按白度抠出线稿成透明底模板图
//               → tools/trimglyph.swift 裁掉透明边并居中进正方画布
//               → 淡底 + 青色线稿（#2BB3A3），和其余芯片同一套语言
//               → glyphScale 0.60 与其余标同墨量）
//   OpenClaw  = openclaw.svg（自绘原创「三道爪痕」glyph，非官方商标——OpenClaw 的
//               龙虾标带商标风险且官方无 press kit，用抽象爪痕规避；模板渲染反色）
// UI 只展示这六个平台；OpenCode / Hermes 仅保留数据兼容，不再出现在界面上。

extension AgentPlatform {
    /// 界面展示名（`label` 是 skills.platforms 的存储键，不能改）
    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .gemini: return "Gemini"
        case .grokbuild: return "Grok"
        case .workbuddy: return "WorkBuddy"
        case .openclaw: return "OpenClaw"
        case .opencode: return "OpenCode"
        case .hermes: return "Hermes"
        }
    }
}

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
        case .workbuddy: return Spec(
            file: "workbuddy-trim", template: true,
            tint: Color(hex: 0x2BB3A3),
            glyphScale: 0.60,
            tintedGlyph: true
        )
        case .openclaw: return Spec(file: "openclaw", template: true, tint: Color(hex: 0xE8503A), glyphScale: 0.66)
        case .opencode, .hermes: return nil
        }
    }

    private static var cache: [String: NSImage] = [:]

    static func image(for platform: AgentPlatform) -> NSImage? {
        guard let spec = spec(for: platform) else { return nil }
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
                ? LF("停用 %@ 挂载（删软链）", platform.displayName)
                : LF("启用 %@ 挂载（建软链）", platform.displayName)
        }
        switch skill.origin {
        case .ccSwitch: return LF("%@：%@（CC Switch 只读，先迁移）", platform.displayName, lit ? L("已启用") : L("未启用"))
        case .local: return LF("%@：%@（详情页「管理」收进本库后可开关）", platform.displayName, lit ? L("本地直装") : L("未挂载"))
        case .atlas: return LF("%@：已停用技能不参与挂载", platform.displayName)
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

struct PlatformFilterStrip: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        // 只给图标，第一次打开的人认不出是哪个平台；宽度够就带上名称，
        // 详情栏展开/窗口变窄时自动退回纯图标（父级用 layoutPriority 保证
        // 右侧菜单先拿到空间，这里拿到的才是真实剩余宽度）
        ViewThatFits(in: .horizontal) {
            strip(labeled: true)     // 宽：图标 + 名称
            strip(labeled: false)    // 中：纯图标
            compactMenu              // 窄：退成下拉，与类别/状态/来源同款
        }
    }

    /// 极窄时的兜底：复用 FilterMenu，菜单里逐行列出平台名（名称照样看得到）
    private var compactMenu: some View {
        @Bindable var store = store
        return FilterMenu(
            label: "平台",
            selection: $store.platform,
            options: ["全部"] + store.visiblePlatforms.map(\.label),
            display: { key in
                AgentPlatform.allCases.first { $0.label == key }?.displayName ?? key
            }
        )
    }

    private func strip(labeled: Bool) -> some View {
        let filtering = store.platform != "全部"
        return HStack(spacing: 2) {
            ForEach(store.visiblePlatforms) { platform in
                let active = store.platform == platform.label
                Button {
                    store.platform = active ? "全部" : platform.label
                } label: {
                    HStack(spacing: Theme.Space.s4 + 1) {
                        // 没在筛选时全部点亮（品牌色本身就是识别信息）；
                        // 一旦筛选，只有选中的保持点亮，其余去色让状态一眼可读
                        PlatformLogo(platform: platform, size: 18, lit: !filtering || active)
                        if labeled {
                            Text(platform.displayName)
                                .font(active ? Theme.Fonts.secondaryEmphasis : Theme.Fonts.secondary)
                                .foregroundStyle(
                                    active ? Theme.accent : (filtering ? Theme.textTertiary : Theme.textSecondary)
                                )
                                .fixedSize()
                        }
                    }
                    .padding(.horizontal, labeled ? Theme.Space.s4 + 2 : 2)
                    .frame(height: 24)
                    .background {
                        if active {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Theme.accent.opacity(0.12))
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .help(active ? LF("清除 %@ 筛选", platform.displayName) : LF("只看 %@", platform.displayName))
            }
        }
        .padding(.horizontal, 3)
        .frame(height: 28)
        // 容器比之前更轻：只留极淡底表明「这一组是一套开关」，不再上发丝边
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        }
    }
}
