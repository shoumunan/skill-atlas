import AppKit
import SwiftUI
#if SWIFT_PACKAGE
import AtlasCore
#endif

// MARK: - 设计令牌（唯一事实来源，对应 DESIGN.md）
//
// 三层材质体系：
//   L0 背景  = 系统桌面采样模糊 + 白纱（不再叠自绘流动渐变）
//   L1 内容  = ContentSurface（安静的标准表面，内容从玻璃下透出来）
//   L2 玻璃  = GlassChrome（只给导航与控件层：侧栏、工具条控件、指南页胶囊）
// 玻璃永远不叠玻璃；内容层绝不用玻璃。

enum Theme {
    // 颜色：唯一强调色 + 健康三色，其余全部来自材质与黑/白透明度
    static let accent = Color(hex: 0x0A84FF)
    static let healthy = Color(hex: 0x34C759)
    static let warning = Color(hex: 0xFF9F0A)
    static let error = Color(hex: 0xFF453A)
    /// 中性语义色（长期未用这类「不是问题、只是没动静」的状态）。
    /// 健康三色表示要处理，这个表示不必处理，别混用。
    static let idle = Color(hex: 0x8E8E93)
    /// 列表面板实色。滑动时必须不透明，半透明/阴影会逼整表每帧离屏合成。
    static let panelNSColor = NSColor(name: nil) { appearance in
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return dark
            ? NSColor(calibratedRed: 0.16, green: 0.16, blue: 0.17, alpha: 1)
            : .white
    }
    static let panelFill = Color(nsColor: panelNSColor)
    /// 和 AtlasBackdrop 同一色，窗口底露出来时不要另一层系统灰。
    static let backdropNSColor = NSColor(name: nil) { appearance in
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return dark
            ? NSColor(calibratedRed: 0.11, green: 0.11, blue: 0.12, alpha: 1)
            : NSColor(calibratedRed: 0.94, green: 0.94, blue: 0.95, alpha: 1)
    }

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

    /// 外壳布局常量（工具条高度与交通灯光学中线必须同源，否则红绿灯错位）
    enum Layout {
        /// 工具条高度：标题簇需要呼吸，44pt 会把标题压在窗口上沿
        static let toolbar: CGFloat = 54
        static let sidebar: CGFloat = 176
        /// 工具条标题左缘 = 窗口 inset 12 + 侧栏 176 + 面板间隙 12，与内容面板左边线同线
        static var contentLeading: CGFloat { Theme.Space.s12 + sidebar + Theme.Space.s12 }
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

// MARK: - L0 背景：系统桌面模糊 + 白纱

/// L0：实色底。桌面模糊会让每次 SwiftUI 排版都逼 WindowServer
/// 整窗重采样壁纸——主线程其实在睡觉，人手上却觉得「整窗发肉」。
struct AtlasBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        (colorScheme == .dark
            ? Color(red: 0.11, green: 0.11, blue: 0.12)
            : Color(red: 0.94, green: 0.94, blue: 0.95))
        .ignoresSafeArea()
    }
}

// MARK: - L1 内容表面（安静，不抢玻璃的戏）

struct ContentSurface: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var cornerRadius: CGFloat = Theme.Radius.panel

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        // 大面板不用 .regularMaterial：列表/详情几乎铺满窗口，材质会整块
        // 采样桌面模糊，Store 每发布一次就逼 WindowServer 重绘。实色纱便宜得多。
        content
            .background {
                shape.fill(Theme.panelFill)
            }
            .overlay {
                shape.strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.10 : 0.35), lineWidth: 0.5)
            }
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
                    shape.fill(dark
                        ? Color(red: 0.14, green: 0.14, blue: 0.15)
                        : Color.white)
                    shape.fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity((dark ? 0.10 : 0.28) + veilBoost),
                                Color.white.opacity((dark ? 0.03 : 0.10) + veilBoost),
                            ],
                            startPoint: .top, endPoint: .bottom
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
            .shadow(color: .black.opacity(hovering && interactive ? 0.10 : 0.06), radius: 6, y: 3)
            .shadow(color: .black.opacity(0.10), radius: 1, y: 1)
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

/// v15 写操作回执行：成功报数字变化，失败报原因（DESIGN.md v15）
struct ReceiptLine: View {
    var text: String
    var failed: Bool = false
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(spacing: Theme.Space.s8) {
            Image(systemName: failed ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(failed ? Theme.warning : Theme.healthy)
            Text(text)
                .font(Theme.Fonts.secondary)
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 20, height: 20)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(L("知道了"))
            }
        }
        .padding(.horizontal, Theme.Space.s12)
        .padding(.vertical, Theme.Space.s8)
        .quietControl(tint: failed ? Theme.warning : Theme.healthy)
    }
}

/// v15 空态原语：图标 + 一句话 +（可选说明）+ 恰好一个动作（DESIGN.md v15）
struct EmptyStateBlock: View {
    var symbol: String
    var title: String
    var caption: String?
    var actionTitle: String
    var action: () -> Void

    var body: some View {
        VStack(spacing: Theme.Space.s12) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
            Text(title)
                .font(Theme.Fonts.panelTitle)
                .foregroundStyle(Theme.textPrimary)
            if let caption {
                Text(caption)
                    .font(Theme.Fonts.body)
                    .lineSpacing(2)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(action: action) {
                Text(actionTitle)
                    .font(Theme.Fonts.calloutEmphasis)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Theme.Space.s20)
                    .frame(height: 32)
                    .background(Capsule(style: .continuous).fill(Theme.accent))
                    .contentShape(Capsule())
            }
            .buttonStyle(PressableButtonStyle())
            .padding(.top, Theme.Space.s4)
        }
        .padding(Theme.Space.s32)
        .frame(maxWidth: 460)
        .contentSurface()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

/// hiddenTitleBar + 空 NSToolbar + unifiedCompact：交通灯下移到工具条光学中线（Theme.Layout.toolbar / 2）。
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
            window.isOpaque = true
            window.backgroundColor = Theme.backdropNSColor
            window.minSize = NSSize(width: 1000, height: 660)
            let spacer = NSToolbar(identifier: "AtlasTitlebarSpacer")
            spacer.allowsUserCustomization = false
            // 全屏时交通灯进菜单栏，空 toolbar 再占一层就是顶上那条灰边。
            if window.styleMask.contains(.fullScreen) {
                window.toolbar = nil
            } else {
                window.toolbar = spacer
                window.toolbarStyle = .unifiedCompact
            }
            NotificationCenter.default.addObserver(
                forName: NSWindow.willEnterFullScreenNotification, object: window, queue: .main
            ) { note in
                (note.object as? NSWindow)?.toolbar = nil
            }
            NotificationCenter.default.addObserver(
                forName: NSWindow.didExitFullScreenNotification, object: window, queue: .main
            ) { note in
                guard let win = note.object as? NSWindow else { return }
                win.toolbar = spacer
                win.toolbarStyle = .unifiedCompact
                Self.alignTrafficLights(win)
            }
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
            // 目标：按钮中心落在工具条光学中线。系统标题栏容器高度有限，
            // 工具条抬高后可能算出负值，钳到 0 保证按钮不出界（宁可略高不可错位）
            let y = max(0, titlebar.frame.height - Theme.Layout.toolbar / 2 - button.frame.height / 2)
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

/// 探测是否全屏。窗口模式忽略顶部安全区；全屏时撤掉空 toolbar，只让系统菜单栏。
struct FullscreenTopInset: NSViewRepresentable {
    @Binding var isFullscreen: Bool

    func makeNSView(context: Context) -> Probe {
        let probe = Probe()
        probe.onChange = { isFullscreen = $0 }
        return probe
    }

    func updateNSView(_ probe: Probe, context: Context) {
        probe.onChange = { isFullscreen = $0 }
        probe.publish()
    }

    final class Probe: NSView {
        var onChange: ((Bool) -> Void)?
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach { NotificationCenter.default.removeObserver($0) }
            observers = []
            guard let window else {
                publish()
                return
            }
            let names: [Notification.Name] = [
                NSWindow.didEnterFullScreenNotification,
                NSWindow.didExitFullScreenNotification,
            ]
            for name in names {
                observers.append(NotificationCenter.default.addObserver(
                    forName: name, object: window, queue: .main
                ) { [weak self] _ in
                    self?.publish()
                })
            }
            publish()
        }

        func publish() {
            onChange?(window?.styleMask.contains(.fullScreen) == true)
        }
    }
}
