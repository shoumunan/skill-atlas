import AppKit
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var updates = UpdateChecker.shared
    @FocusState private var searchFocused: Bool
    @State private var entered = false

    var body: some View {
        ZStack {
            AtlasBackdrop()

            if let message = store.fatalError {
                FatalView(message: message)
            } else {
                shell
            }
        }
        .foregroundStyle(Theme.textPrimary)
        .tint(Theme.accent)
        .sheet(item: $store.readerSkill) { skill in
            ReaderSheet(skill: skill)
        }
        .sheet(isPresented: $store.installSheetPresented) {
            InstallSheet()
        }
        .sheet(isPresented: $store.migrationSheetPresented) {
            MigrationSheet()
        }
        .sheet(isPresented: $store.cleanupSheetPresented) {
            CleanupSheet()
        }
        // 素材投递箱（二期 F5）：拖文件进窗口任意位置
        .sheet(item: $store.droppedMaterial) { material in
            DropSheet(fileURL: material.url, matches: material.matches)
        }
        .sheet(item: $store.diffTarget) { skill in
            DiffSheet(skill: skill)
        }
        // 停用被依赖技能的警告（F6 链路数据接管理动作）
        .confirmationDialog(
            LF("「%@」被其他技能依赖", store.disableWarning?.skill.name ?? ""),
            isPresented: Binding(
                get: { store.disableWarning != nil },
                set: { if !$0 { store.disableWarning = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(L("仍要停用"), role: .destructive) {
                if let warning = store.disableWarning {
                    store.setSkillDisabled(warning.skill, disabled: true)
                }
                store.disableWarning = nil
            }
            Button(L("取消"), role: .cancel) { store.disableWarning = nil }
        } message: {
            Text(LF("%@ 依赖它才能工作，停用后这些技能会静默失效。", (store.disableWarning?.dependents ?? []).joined(separator: "、")))
        }
        .onDrop(of: [.fileURL], isTargeted: $store.dropTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    store.receiveDroppedFile(url)
                }
            }
            return true
        }
        .overlay {
            if store.dropTargeted {
                DropTargetOverlay()
            }
        }
        .alert(L("操作未完成"), isPresented: Binding(
            get: { store.actionError != nil },
            set: { if !$0 { store.actionError = nil } }
        )) {
            Button(L("好"), role: .cancel) { store.actionError = nil }
        } message: {
            Text(store.actionError ?? "")
        }
        .confirmationDialog(
            "卸载「\(store.uninstallTarget?.name ?? "")」？",
            isPresented: Binding(
                get: { store.uninstallTarget != nil },
                set: { if !$0 { store.uninstallTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(L("只移除平台挂载")) {
                if let skill = store.uninstallTarget { store.confirmUninstall(skill, trashLibrary: false) }
            }
            Button(L("卸载并移入废纸篓"), role: .destructive) {
                if let skill = store.uninstallTarget { store.confirmUninstall(skill, trashLibrary: true) }
            }
            Button(L("取消"), role: .cancel) { store.uninstallTarget = nil }
        } message: {
            Text(uninstallMessage)
        }
        .task {
            applyLaunchPage()
            AtlasCatalog.migrateLegacyIfNeeded()
            await store.rescan(keepSelection: false)
            UpdateChecker.shared.bootstrap()
        }
        .onAppear {
            store.installKeyMonitor()
            applyLaunchPage()
            DispatchQueue.main.async { applyLaunchPage() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { applyLaunchPage() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                entered = true
            }
        }
        .onChange(of: store.searchFocusRequest) { _, new in
            guard new > 0 else { return }
            store.nav = .library
            DispatchQueue.main.async { searchFocused = true }
        }
    }

    /// 卸载确认文案：被依赖时追加警告
    private var uninstallMessage: String {
        var message = L("会移除本应用建的平台软链。库内目录会先备份再处理。CC Switch 原文件不会删除。")
        if let target = store.uninstallTarget {
            let dependents = ProductionChain.dependents(of: target.directory).filter { directory in
                store.skills.contains { $0.directory == directory && !$0.disabled }
            }
            if !dependents.isEmpty {
                message += LF("\n\n注意：%@ 依赖它，卸载后会静默失效。", dependents.joined(separator: "、"))
            }
        }
        return message
    }

    private func applyLaunchPage() {
        let page = LaunchArgs.value("atlasPage") ?? UserDefaults.standard.string(forKey: "atlasPage")
        guard let page else { return }
        switch page {
        case "overview", "library", "updates": store.nav = .library
        case "health", "doctor": store.nav = .doctor
        case "guide", "howto": store.nav = .guide
        case "settings": store.nav = .settings
        default:
            if let target = NavPage(rawValue: page) { store.nav = target }
        }
    }

    private var shell: some View {
        VStack(spacing: 0) {
            ToolbarStrip(searchFocused: $searchFocused, hasAppUpdate: updates.available != nil)
                .enterEffect(entered, delay: 0)
            HStack(spacing: Theme.Space.s12) {
                SidebarRail()
                    .enterEffect(entered, delay: 0.05)
                PageContainer()
                    .enterEffect(entered, delay: 0.1)
            }
            .padding(.horizontal, Theme.Space.s12)
            .padding(.bottom, Theme.Space.s12)
        }
        .ignoresSafeArea()
    }
}

struct ToolbarStrip: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var searchFocused: FocusState<Bool>.Binding
    var hasAppUpdate: Bool

    var body: some View {
        HStack(spacing: Theme.Space.s12) {
            HStack(spacing: Theme.Space.s8) {
                Image(systemName: store.nav.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 24, height: 24)
                    .background {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Theme.accent.opacity(0.12))
                    }
                VStack(alignment: .leading, spacing: 0) {
                    Text(store.nav.title)
                        .font(Theme.Fonts.rowTitle)
                        .foregroundStyle(Theme.textPrimary)
                    Text(store.pageSubtitle)
                        .font(Theme.Fonts.caption)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textTertiary)
                        .contentTransition(.opacity)
                }
            }
            .id(store.nav)
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 4)))

            Spacer()

            if store.nav == .library {
                SearchCapsule(searchFocused: searchFocused)
                    .frame(width: 300)
                    .transition(.opacity)
            }

            InstallChromeButton()
            RefreshButton()

            if let scannedAt = store.data?.summary.scannedAt {
                HStack(spacing: Theme.Space.s8) {
                    if hasAppUpdate {
                        Button {
                            UpdateChecker.shared.checkFromMenu()
                        } label: {
                            Circle()
                                .fill(Theme.accent)
                                .frame(width: 8, height: 8)
                        }
                        .buttonStyle(.plain)
                        .help(L("发现应用新版本"))
                    }
                    Text(LF("更新于 %@", Format.clock.string(from: scannedAt)))
                        .font(Theme.Fonts.caption)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        // 左缘 = 窗口 inset 12 + 侧栏 176 + 面板间隙 12，与内容面板左边线同线
        .padding(.leading, 200)
        .padding(.trailing, Theme.Space.s12)
        .frame(height: 44)
        .animation(reduceMotion ? nil : Motion.standard, value: store.nav)
    }
}

private struct SearchCapsule: View {
    @EnvironmentObject private var store: AppStore
    var searchFocused: FocusState<Bool>.Binding

    var body: some View {
        let focused = searchFocused.wrappedValue
        HStack(spacing: Theme.Space.s8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(focused ? Theme.accent : Theme.textSecondary)
            TextField(L("搜索技能、用途或任务"), text: $store.search)
                .textFieldStyle(.plain)
                .font(Theme.Fonts.callout)
                .foregroundStyle(Theme.textPrimary)
                .focused(searchFocused)
                .onExitCommand {
                    store.search = ""
                    searchFocused.wrappedValue = false
                }
            if store.search.isEmpty {
                Text("⌘K")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textTertiary)
            } else {
                Button {
                    store.search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(L("清空搜索"))
            }
        }
        .padding(.horizontal, Theme.Space.s12)
        .frame(height: 32)
        .glassChrome(Capsule(style: .continuous))
        // 聚焦环：搜索激活时的强调色描边 + 微光
        .overlay {
            if focused {
                Capsule(style: .continuous)
                    .strokeBorder(Theme.accent.opacity(0.55), lineWidth: 1.5)
                    .shadow(color: Theme.accent.opacity(0.25), radius: 4)
            }
        }
        .help(L("窗口内 ⌘K 聚焦搜索；在任何应用里按 ⌥⌘K 呼出菜单栏快速搜索"))
    }
}

/// 工具栏主操作：安装技能。带文字的强调色玻璃按钮，入口必须一眼可见。
private struct InstallChromeButton: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Button {
            store.installSheetPresented = true
        } label: {
            HStack(spacing: Theme.Space.s4 + 1) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                Text(L("安装技能"))
                    .font(Theme.Fonts.calloutEmphasis)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, Theme.Space.s12 + 2)
            .frame(height: 32)
            .contentShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .accentGlass(Capsule(style: .continuous))
        .help(L("从 GitHub 链接或本地文件夹装入技能库（⌘N）"))
    }
}

private struct RefreshButton: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            Task { await store.rescan() }
        } label: {
            Group {
                // repeatForever 动画在 macOS 上无法可靠取消（曾导致图标永转），
                // 改用 TimelineView 按时间驱动：scanning 一停视图即换回静态，物理上不可能卡住
                if store.scanning && !reduceMotion {
                    TimelineView(.animation) { timeline in
                        let angle = timeline.date.timeIntervalSinceReferenceDate
                            .truncatingRemainder(dividingBy: 0.9) / 0.9 * 360
                        icon.rotationEffect(.degrees(angle))
                    }
                } else {
                    icon
                }
            }
            .frame(width: 32, height: 32)
            .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .glassChrome(Circle(), interactive: true)
        .disabled(store.scanning)
        .help(L("重新扫描（⌘R）"))
    }

    private var icon: some View {
        Image(systemName: "arrow.clockwise")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.textPrimary)
    }
}

/// 侧栏：文字导航列表（图标 + 标签，参考 CC Switch），宽 176。
struct SidebarRail: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var navSpace

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BrandRow()
                .padding(.horizontal, Theme.Space.s16)
                .padding(.top, Theme.Space.s16)
                .padding(.bottom, Theme.Space.s20)

            VStack(spacing: 2) {
                ForEach(NavPage.allCases) { page in
                    RailItem(page: page, namespace: navSpace)
                }
            }
            .padding(.horizontal, Theme.Space.s8)

            Spacer()

            HStack(spacing: Theme.Space.s8) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.healthy)
                Text(L("CC Switch 数据只读"))
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, Theme.Space.s16)
            .padding(.bottom, Theme.Space.s16)
            .help(L("不改动 CC Switch 原文件。本应用只管理自己的技能库，随时可撤销迁移。"))
        }
        .frame(width: 176)
        .frame(maxHeight: .infinity)
        .glassChrome(RoundedRectangle(cornerRadius: Theme.Radius.rail, style: .continuous))
        .animation(reduceMotion ? nil : Motion.control, value: store.nav)
    }
}

private struct BrandRow: View {
    private static let appIcon: NSImage = {
        if let path = Bundle.main.path(forResource: "SkillAtlas", ofType: "icns"),
           let image = NSImage(contentsOfFile: path) {
            return image
        }
        return NSApp.applicationIconImage
    }()

    var body: some View {
        HStack(spacing: Theme.Space.s8 + 2) {
            Image(nsImage: Self.appIcon)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .frame(width: 30, height: 30)
                .scaleEffect(1024.0 / 824.0)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text("Skill Atlas")
                    .font(Theme.Fonts.rowTitle)
                    .foregroundStyle(Theme.textPrimary)
                Text(L("技能管理"))
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .help("Skill Atlas")
    }
}

private struct RailItem: View {
    @EnvironmentObject private var store: AppStore
    @State private var hovering = false
    var page: NavPage
    var namespace: Namespace.ID

    var body: some View {
        let active = store.nav == page
        let count = badge
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.control + 1, style: .continuous)
        Button {
            store.nav = page
        } label: {
            HStack(spacing: Theme.Space.s8 + 2) {
                Image(systemName: page.symbol)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 20)
                Text(page.title)
                    .font(active ? Theme.Fonts.calloutEmphasis : Theme.Fonts.callout)
                Spacer(minLength: 0)
                if count > 0 {
                    Text(count > 99 ? "99+" : "\(count)")
                        .font(Theme.Fonts.caption)
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, Theme.Space.s4 + 1)
                        .frame(minWidth: 17)
                        .frame(height: 16)
                        .background(Capsule().fill(badgeTint))
                }
            }
            .foregroundStyle(active ? Theme.accent : Theme.textSecondary)
            .padding(.horizontal, Theme.Space.s8 + 2)
            .frame(height: 34)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    if active {
                        shape
                            .fill(Theme.accent.opacity(0.13))
                            .overlay {
                                // 选中胶囊自己的镜面顶边，和玻璃语言一致
                                shape.strokeBorder(
                                    LinearGradient(
                                        stops: [
                                            .init(color: Theme.accent.opacity(0.35), location: 0),
                                            .init(color: Theme.accent.opacity(0.10), location: 1),
                                        ],
                                        startPoint: .top, endPoint: .bottom
                                    ),
                                    lineWidth: 0.5
                                )
                            }
                            .matchedGeometryEffect(id: "nav-selection", in: namespace)
                    } else if hovering {
                        shape.fill(Color.primary.opacity(0.05))
                    }
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(page.help)
    }

    private var badge: Int {
        switch page {
        case .library: return store.updatableSkills.count
        case .doctor: return store.doctorBadgeCount
        default: return 0
        }
    }

    private var badgeTint: Color {
        page == .doctor ? Theme.warning : Theme.accent
    }
}

private struct PageContainer: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Group {
                if store.data == nil {
                    SkeletonPage()
                } else {
                    switch store.nav {
                    case .library:
                        if store.skills.isEmpty { OnboardingView() } else { LibraryPage() }
                    case .doctor: DoctorPage()
                    case .guide: GuidePage()
                    case .settings: SettingsPage()
                    }
                }
            }
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 10)))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(reduceMotion ? nil : Motion.standard, value: store.nav)
        .animation(reduceMotion ? nil : Motion.standard, value: store.data == nil)
    }
}

struct SkeletonPage: View {
    var body: some View {
        VStack(spacing: Theme.Space.s12) {
            HStack(spacing: Theme.Space.s24) {
                ForEach(0..<4, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: Theme.Space.s8) {
                        skeletonBar(width: 64, height: 24)
                        skeletonBar(width: 96, height: 10)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .shimmer()
            .padding(Theme.Space.s20)
            .contentSurface()

            VStack(spacing: Theme.Space.s16) {
                ForEach(0..<10, id: \.self) { index in
                    HStack(spacing: Theme.Space.s12) {
                        RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                            .frame(width: 30, height: 30)
                        VStack(alignment: .leading, spacing: Theme.Space.s4) {
                            skeletonBar(width: 120 + CGFloat(index % 3) * 40, height: 10)
                            skeletonBar(width: 220 + CGFloat(index % 4) * 30, height: 8)
                        }
                        Spacer()
                    }
                }
                Spacer(minLength: 0)
            }
            .shimmer()
            .padding(Theme.Space.s20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .contentSurface()
        }
    }

    private func skeletonBar(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: height / 2, style: .continuous)
            .fill(Color.primary.opacity(0.06))
            .frame(width: width, height: height)
    }
}

struct OnboardingView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(spacing: Theme.Space.s20) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Theme.accent)
            Text(L("技能库还是空的"))
                .font(Theme.Fonts.panelTitle)
            Text(L("从 GitHub 或本地文件夹装入第一个技能，或把 CC Switch 里已有的技能收进来。"))
                .font(Theme.Fonts.body)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            HStack(spacing: Theme.Space.s8) {
                Button(L("安装技能…")) {
                    store.installSheetPresented = true
                }
                .buttonStyle(.borderedProminent)
                .help(L("装入本应用技能库（⌘N）"))
                if store.canMigrate {
                    Button(L("从 CC Switch 迁入…")) {
                        store.migrationSheetPresented = true
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.Space.s32)
        .contentSurface()
    }
}

struct CopyIconButton: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var copied = false
    var text: String
    var help: String = L("复制")

    var body: some View {
        Button {
            store.copyToPasteboard(text)
            withAnimation(reduceMotion ? nil : Motion.control) { copied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                withAnimation(reduceMotion ? nil : Motion.control) { copied = false }
            }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 11, weight: copied ? .semibold : .regular))
                .foregroundStyle(copied ? Theme.healthy : Theme.textSecondary)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

struct FatalView: View {
    @EnvironmentObject private var store: AppStore
    var message: String

    var body: some View {
        VStack(spacing: Theme.Space.s12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28))
                .foregroundStyle(Theme.warning)
            Text(L("扫描技能时出错"))
                .font(Theme.Fonts.panelTitle)
                .foregroundStyle(Theme.textPrimary)
            Text(message)
                .font(Theme.Fonts.body)
                .lineSpacing(2)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Button {
                Task { await store.rescan() }
            } label: {
                Text(L("重试"))
                    .font(Theme.Fonts.calloutEmphasis)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Theme.Space.s20)
                    .frame(height: 32)
                    .background(Capsule(style: .continuous).fill(Theme.accent))
                    .contentShape(Capsule())
            }
            .buttonStyle(PressableButtonStyle())
        }
        .padding(Theme.Space.s32)
        .frame(maxWidth: 460)
        .contentSurface()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}


/// 拖文件悬停时的全窗提示浮层
private struct DropTargetOverlay: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
                .strokeBorder(Theme.accent.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                .background {
                    RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
                        .fill(Theme.accent.opacity(0.06))
                }
                .padding(Theme.Space.s16)
            VStack(spacing: Theme.Space.s8) {
                Image(systemName: "tray.and.arrow.down.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Theme.accent)
                Text("松手投递素材")
                    .font(Theme.Fonts.panelTitle)
                    .foregroundStyle(Theme.textPrimary)
                Text("按文件名和类型匹配技能，带路径发起会话")
                    .font(Theme.Fonts.secondary)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(Theme.Space.s24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
        }
        .allowsHitTesting(false)
    }
}
