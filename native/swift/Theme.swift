import AppKit
import SwiftUI
#if canImport(FluidGradient)
// SwiftPM（完整 Xcode）路径：FluidGradient 作为独立模块引入
import FluidGradient
#endif
// 仅 Command Line Tools 环境：构建脚本把 native/vendor/FluidGradient 源码
// 与本目标合并编译，同名类型直接可用，无需 import。

// MARK: - 设计令牌（唯一事实来源，对应 DESIGN.md）
//
// 三层材质体系：
//   L0 背景  = 桌面采样模糊 + FluidGradient 流动环境光 + 白纱
//   L1 内容  = ContentSurface（安静的标准表面，内容从玻璃下透出来）
//   L2 玻璃  = GlassChrome（只给导航与控件层：侧栏、工具条控件、指南页胶囊）
// 玻璃永远不叠玻璃；内容层绝不用玻璃。

enum Theme {
    // 颜色：唯一强调色 + 健康三色，其余全部来自材质与黑/白透明度
    static let accent = Color(hex: 0x0A84FF)
    static let healthy = Color(hex: 0x34C759)
    static let warning = Color(hex: 0xFF9F0A)
    static let error = Color(hex: 0xFF453A)

    /// 中性文本：亮色用黑 .85/.55/.35，暗色相应用白
    static let textPrimary = dynamicInk(0.85)
    static let textSecondary = dynamicInk(0.55)
    static let textTertiary = dynamicInk(0.35)

    private static func dynamicInk(_ alpha: CGFloat) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return (dark ? NSColor.white : NSColor.black).withAlphaComponent(alpha)
        })
    }

    /// 字阶：全应用只允许这 8 档（路径/代码另用 mono 11）
    enum Fonts {
        static let metric = Font.system(size: 28, weight: .semibold, design: .rounded).monospacedDigit()
        static let pageTitle = Font.system(size: 17, weight: .semibold)
        static let panelTitle = Font.system(size: 15, weight: .semibold)
        static let rowTitle = Font.system(size: 13, weight: .semibold)
        static let body = Font.system(size: 13)
        static let callout = Font.system(size: 12)
        static let calloutEmphasis = Font.system(size: 12, weight: .medium)
        static let secondary = Font.system(size: 11)
        static let secondaryEmphasis = Font.system(size: 11, weight: .medium)
        static let caption = Font.system(size: 10, weight: .medium)
        static let mono = Font.system(size: 11, design: .monospaced)
    }

    /// 间距：4pt 网格，只允许下列取值（列表行内边距另设 水平12/垂直10）
    enum Space {
        static let s4: CGFloat = 4
        static let s8: CGFloat = 8
        static let s12: CGFloat = 12
        static let s16: CGFloat = 16
        static let s20: CGFloat = 20
        static let s24: CGFloat = 24
        static let s32: CGFloat = 32
    }

    /// 圆角：嵌套递减；胶囊只给大号突出控件
    enum Radius {
        static let rail: CGFloat = 20
        static let panel: CGFloat = 16
        static let tile: CGFloat = 12
        static let row: CGFloat = 10
        static let control: CGFloat = 8
    }
}

// MARK: - 动效令牌

enum Motion {
    /// 标准弹簧：入场、切页、数字
    static let standard = Animation.spring(response: 0.35, dampingFraction: 0.8)
    /// 控件弹簧：hover、按下、选中胶囊滑动
    static let control = Animation.spring(response: 0.28, dampingFraction: 0.85)
}

/// 启动入场：上浮 12pt + 淡入，按 delay 错峰；Reduce Motion 时直切
struct EnterEffect: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var ready: Bool
    var delay: Double

    func body(content: Content) -> some View {
        let settled = ready || reduceMotion
        content
            .opacity(settled ? 1 : 0)
            .offset(y: settled ? 0 : 12)
            .animation(reduceMotion ? nil : Motion.standard.delay(delay), value: ready)
    }
}

extension View {
    func enterEffect(_ ready: Bool, delay: Double) -> some View {
        modifier(EnterEffect(ready: ready, delay: delay))
    }
}

// MARK: - L0 背景：桌面模糊 + FluidGradient 环境光 + 白纱

/// 窗口底层材质：采样桌面壁纸的系统级模糊
struct WindowBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// L0：给上层玻璃提供「活的」可折射光影。
/// FluidGradient（github.com/Cindori/FluidGradient，MIT）绘制低饱和流动 blobs。
struct AtlasBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            WindowBackdrop()
            if !reduceTransparency {
                FluidGradient(
                    blobs: [
                        Color(hex: 0x9CC7F7),  // sky
                        Color(hex: 0xB4B8F2),  // periwinkle
                        Color(hex: 0xA9E3C6),  // mint
                        Color(hex: 0xBFD5F2),
                    ],
                    highlights: [
                        Color(hex: 0xD6E6FB),
                        Color(hex: 0xDEDCFA),
                        Color(hex: 0xCDEEDD),
                    ],
                    speed: reduceMotion ? 0 : 0.2,
                    blur: 0.75
                )
                .opacity(colorScheme == .dark ? 0.22 : 0.35)
                Color.white.opacity(colorScheme == .dark ? 0.03 : 0.12)
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - L1 内容表面（安静，不抢玻璃的戏）

struct ContentSurface: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var cornerRadius: CGFloat = Theme.Radius.panel

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .clipShape(shape)
            .background {
                shape.fill(.regularMaterial)
                    .overlay {
                        shape.fill(Color.white.opacity(colorScheme == .dark ? 0.05 : 0.45))
                    }
            }
            .overlay {
                shape.strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.10 : 0.35), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.06), radius: 14, y: 8)
    }
}

extension View {
    func contentSurface(cornerRadius: CGFloat = Theme.Radius.panel) -> some View {
        modifier(ContentSurface(cornerRadius: cornerRadius))
    }
}

// MARK: - L2 玻璃 chrome（镜面高光 + 双层阴影 + 内侧顶光）

struct GlassChrome<S: InsettableShape>: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    var shape: S
    var interactive = false

    func body(content: Content) -> some View {
        let dark = colorScheme == .dark
        let veilBoost = interactive && hovering ? 0.08 : 0.0
        content
            .background {
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    // 顶到底的白色渐变纱
                    shape.fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity((dark ? 0.12 : 0.35) + veilBoost),
                                Color.white.opacity((dark ? 0.04 : 0.15) + veilBoost),
                            ],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    // 顶部内侧柔和径向白光（「从内部发光」）
                    shape.fill(
                        RadialGradient(
                            colors: [Color.white.opacity(dark ? 0.10 : 0.20), .clear],
                            center: UnitPoint(x: 0.5, y: 0),
                            startRadius: 0, endRadius: 140
                        )
                    )
                }
            }
            // 发丝整圈
            .overlay {
                shape.strokeBorder(Color.white.opacity(dark ? 0.20 : 0.45), lineWidth: 0.5)
            }
            // 镜面顶边：只亮上缘的 1pt 高光
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(dark ? 0.50 : 0.85), location: 0),
                            .init(color: .clear, location: 0.35),
                        ],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 1
                )
            }
            // 底缘收暗：玻璃厚度的下沿阴影（上缘受光、下缘收暗）
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.6),
                            .init(color: Color.black.opacity(dark ? 0.30 : 0.10), location: 1),
                        ],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 1
                )
            }
            // 环境阴影（大而软）+ 接触阴影（小而实）
            .shadow(color: .black.opacity(hovering && interactive ? 0.14 : 0.10), radius: 18, y: 10)
            .shadow(color: .black.opacity(hovering && interactive ? 0.22 : 0.18), radius: 2, y: 1)
            .scaleEffect(interactive && hovering && !reduceMotion ? 1.01 : 1)
            .animation(reduceMotion ? nil : Motion.control, value: hovering)
            .onHover { inside in
                if interactive { hovering = inside }
            }
    }
}

extension View {
    func glassChrome<S: InsettableShape>(_ shape: S, interactive: Bool = false) -> some View {
        modifier(GlassChrome(shape: shape, interactive: interactive))
    }
}

// MARK: - 安静控件（内容层内的筛选、按钮：绝不用玻璃）

extension View {
    /// 黑 .04 填充 + 发丝描边（暗色自动转白），radius 8
    func quietControl(cornerRadius: CGFloat = Theme.Radius.control, tint: Color? = nil) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .background {
                shape.fill(tint.map { AnyShapeStyle($0.opacity(0.12)) } ?? AnyShapeStyle(Color.primary.opacity(0.04)))
            }
            .overlay {
                shape.strokeBorder(tint?.opacity(0.24) ?? Color.primary.opacity(0.08), lineWidth: 0.5)
            }
    }
}

// MARK: - 强调色玻璃按钮底（主操作专用：安装、全部更新、复制调用语）

/// Liquid Glass 语言下的主按钮材质：强调色纵向渐变（上亮下实）
/// + 镜面顶边 + 品牌色环境阴影 + 接触阴影。文字一律白色。
struct AccentGlass<S: InsettableShape>: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var shape: S
    var tint: Color = Theme.accent

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    shape.fill(
                        LinearGradient(
                            stops: [
                                .init(color: tint.opacity(colorScheme == .dark ? 0.95 : 1), location: 0),
                                .init(color: tint, location: 1),
                            ],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    // 顶部内侧白光：让按钮像被同一光源照亮的玻璃
                    shape.fill(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.28), location: 0),
                                .init(color: .clear, location: 0.55),
                            ],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                }
            }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.55), location: 0),
                            .init(color: .white.opacity(0.08), location: 0.5),
                        ],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
            }
            .shadow(color: tint.opacity(0.35), radius: 6, y: 3)
            .shadow(color: .black.opacity(0.10), radius: 1, y: 1)
    }
}

extension View {
    func accentGlass<S: InsettableShape>(_ shape: S, tint: Color = Theme.accent) -> some View {
        modifier(AccentGlass(shape: shape, tint: tint))
    }
}

// MARK: - Shimmer 骨架（灵感来自开源 swiftui-shimmer：github.com/markiv/SwiftUI-Shimmer）

struct Shimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -0.6

    func body(content: Content) -> some View {
        if reduceMotion {
            content.opacity(0.6)
        } else {
            content
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .black.opacity(0.45), location: phase - 0.35),
                            .init(color: .black, location: phase),
                            .init(color: .black.opacity(0.45), location: phase + 0.35),
                        ],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                }
                .onAppear {
                    withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                        phase = 1.6
                    }
                }
        }
    }
}

extension View {
    func shimmer() -> some View { modifier(Shimmer()) }
}

// MARK: - 共享小组件

/// 分类图标（半径 = 尺寸 30% 连续圆角方块），两档色量：
/// - `.solid`：白色符号 + 实色底 + 顶光，用于单实例展示（详情头部、总览 tile、指南 cell）
/// - `.quiet`：分类色淡底 + 分类色 glyph，用于密集重复场景（技能列表行、健康行、最近安装、推荐行），
///   避免相邻行实色方块穿插成彩虹墙；暗色下淡底提到 24% 保证 glyph 对比
struct CategoryIcon: View {
    enum Style { case solid, quiet }

    @Environment(\.colorScheme) private var colorScheme
    var category: String
    var size: CGFloat = 30
    var style: Style = .solid

    var body: some View {
        let meta = Categories.meta(for: category)
        let shape = RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
        switch style {
        case .solid:
            shape
                .fill(
                    LinearGradient(
                        colors: [meta.tint.opacity(0.88), meta.tint],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .overlay {
                    // 图标自己的镜面顶光
                    shape.fill(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.28), location: 0),
                                .init(color: .clear, location: 0.55),
                            ],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                }
                .overlay {
                    Image(systemName: meta.symbol)
                        .font(.system(size: size * 0.5, weight: .medium))
                        .foregroundStyle(.white)
                }
                .overlay {
                    shape.strokeBorder(Color.white.opacity(0.35), lineWidth: 0.5)
                }
                .frame(width: size, height: size)
                .shadow(color: meta.tint.opacity(0.35), radius: 3, y: 1.5)
        case .quiet:
            shape
                .fill(meta.tint.opacity(colorScheme == .dark ? 0.24 : 0.15))
                .overlay {
                    Image(systemName: meta.symbol)
                        .font(.system(size: size * 0.5, weight: .medium))
                        .foregroundStyle(meta.tint)
                }
                .frame(width: size, height: size)
        }
    }
}

// MARK: - 面板内滚动区

/// 面板内 ScrollView 统一处理：隐藏系统滚动条（用户可能设置「始终显示」，
/// 常驻轨道会压在圆角面板边上），滚动暗示交给底部边缘渐隐
struct PanelScroll: ViewModifier {
    var fadeBottom: CGFloat = Theme.Space.s16

    func body(content: Content) -> some View {
        content
            // .hidden 会被系统「始终显示滚动条」设置覆盖，.never 才是强制隐藏
            .scrollIndicators(.never)
            .mask {
                VStack(spacing: 0) {
                    Rectangle().fill(Color.black)
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: fadeBottom)
                }
            }
    }
}

extension View {
    func panelScroll(fadeBottom: CGFloat = Theme.Space.s16) -> some View {
        modifier(PanelScroll(fadeBottom: fadeBottom))
    }
}

/// 面板标题：标题 + 一行副文案
struct PanelHead: View {
    var title: String
    var subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s4) {
            Text(L(title))
                .font(Theme.Fonts.panelTitle)
                .foregroundStyle(Theme.textPrimary)
            Text(L(subtitle))
                .font(Theme.Fonts.secondary)
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

struct StatusDot: View {
    var tint: Color

    var body: some View {
        Circle()
            .fill(tint)
            .frame(width: 8, height: 8)
            .shadow(color: tint.opacity(0.5), radius: 2)
    }
}

/// 健康徽标（高密度小控件 → 圆角矩形，不用胶囊）
struct HealthFlag: View {
    var health: Health

    var body: some View {
        Text(health.label)
            .font(Theme.Fonts.caption)
            .foregroundStyle(health.tint)
            .padding(.horizontal, Theme.Space.s8)
            .frame(height: 20)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .fill(health.tint.opacity(0.12))
            }
    }
}

/// 按压 0.97 缩放的通用按钮样式
struct PressableButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(reduceMotion ? nil : Motion.control, value: configuration.isPressed)
    }
}

// MARK: - 窗口配置

/// hiddenTitleBar + 空 NSToolbar + unifiedCompact：交通灯下移到 44pt 工具条光学中线。
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let probe = NSView()
        DispatchQueue.main.async {
            guard let window = probe.window else { return }
            window.identifier = NSUserInterfaceItemIdentifier("atlasWindow")
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            window.styleMask.insert(.fullSizeContentView)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.minSize = NSSize(width: 1000, height: 660)
            let spacer = NSToolbar(identifier: "AtlasTitlebarSpacer")
            spacer.allowsUserCustomization = false
            window.toolbar = spacer
            window.toolbarStyle = .unifiedCompact
            let spec = LaunchArgs.value("atlasWindow") ?? UserDefaults.standard.string(forKey: "atlasWindow")
            if let spec, let size = Self.parseSize(spec) {
                window.setContentSize(size)
                window.center()
            } else {
                window.setFrameAutosaveName("SkillAtlasMain")
            }
            Self.alignTrafficLights(window)
            NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification,
                                                   object: window, queue: .main) { note in
                guard let win = note.object as? NSWindow else { return }
                Self.alignTrafficLights(win)
            }
        }
        return probe
    }

    static func alignTrafficLights(_ window: NSWindow) {
        let buttons: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        for type in buttons {
            guard let button = window.standardWindowButton(type),
                  let titlebar = button.superview else { continue }
            let y = titlebar.frame.height - 22 - button.frame.height / 2
            button.setFrameOrigin(NSPoint(x: button.frame.origin.x, y: y))
        }
    }

    static func parseSize(_ spec: String) -> NSSize? {
        let parts = spec.lowercased().split(separator: "x")
        guard parts.count == 2, let width = Double(parts[0]), let height = Double(parts[1]) else { return nil }
        return NSSize(width: width, height: height)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
