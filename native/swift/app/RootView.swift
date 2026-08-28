import AppKit
import SwiftUI
#if SWIFT_PACKAGE
import AtlasCore
#endif

struct RootView: View {
    @Environment(AppStore.self) private var store
    @ObservedObject private var updates = UpdateChecker.shared
    @FocusState private var searchFocused: Bool
    /// 全屏时不再忽略顶部安全区（只让菜单栏），窗口模式忽略以便工具条对齐交通灯。
    @State private var isFullscreen = false

    var body: some View {
        @Bindable var store = store
        Group {
            if let message = store.fatalError {
                FatalView(message: message)
            } else {
                shell
            }
        }
        .background(AtlasBackdrop())
        .foregroundStyle(Theme.textPrimary)
        .tint(Theme.accent)
        .sheet(item: $store.readerSkill) { skill in
            ReaderSheet(skill: skill)
        }
        .sheet(isPresented: $store.installSheetPresented) {
            InstallSheet()
        }
        .sheet(item: $store.pendingReview) { request in
            PendingReviewSheet(token: request.token)
        }
        .sheet(isPresented: $store.hookConsentPresented) {
            HookConsentSheet()
        }
        .sheet(item: $updates.session) { _ in
            AppUpdateSheet()
        }
        .sheet(isPresented: $store.migrationSheetPresented) {
            MigrationSheet()
        }
        .sheet(isPresented: $store.cleanupSheetPresented) {
            CleanupSheet()
        }
        .sheet(isPresented: Binding(
            get: { store.updateReview != nil },
            set: { if !$0 { store.updateReview = nil } }
        )) {
            UpdateReviewSheet()
        }
        .sheet(isPresented: Binding(
            get: { store.batchReviews != nil },
            set: { if !$0 { store.batchReviews = nil } }
        )) {
            BatchUpdateSheet()
        }
        // 描述开药（三期 G2）
        .sheet(isPresented: Binding(
            get: { store.prescription != nil },
            set: { if !$0 { store.prescription = nil } }
        )) {
            PrescriptionSheet()
        }
        // 场景 Profile（三期 G8）
        .sheet(isPresented: $store.profileSheetPresented) {
            ProfileSheet()
        }
        .sheet(isPresented: Binding(
            get: { store.profileRequest != nil },
            set: { if !$0 { store.profileRequest = nil } }
        )) {
            ProfileApplySheet()
        }
        .alert(L("场景已更新"), isPresented: Binding(
            get: { store.profileNotice != nil },
            set: { if !$0 { store.profileNotice = nil } }
        )) {
            Button(L("好"), role: .cancel) { store.profileNotice = nil }
        } message: {
            Text(store.profileNotice ?? "")
        }
        // 回滚确认（G1）：明说恢复到哪个备份、当前状态也会拍快照
        .confirmationDialog(
            LF("把「%@」回滚到备份？", store.rollbackRequest?.skill.name ?? ""),
            isPresented: Binding(
                get: { store.rollbackRequest != nil },
                set: { if !$0 { store.rollbackRequest = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(L("回滚"), role: .destructive) { store.confirmRollback() }
            Button(L("取消"), role: .cancel) { store.rollbackRequest = nil }
        } message: {
            Text(LF("恢复到 %@。回滚前会先给当前状态拍快照，这一步本身也可回滚。", store.rollbackRequest?.backupName ?? ""))
        }
        .alert(L("更新结果"), isPresented: Binding(
            get: { store.updateNotice != nil },
            set: { if !$0 { store.updateNotice = nil } }
        )) {
            Button(L("好"), role: .cancel) { store.updateNotice = nil }
        } message: {
            Text(store.updateNotice ?? "")
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
            Button(L("只从软件里拿掉")) {
                if let skill = store.uninstallTarget { store.confirmUninstall(skill, trashLibrary: false) }
            }
            Button(L("连文件一起扔掉"), role: .destructive) {
                if let skill = store.uninstallTarget { store.confirmUninstall(skill, trashLibrary: true) }
            }
            Button(L("取消"), role: .cancel) { store.uninstallTarget = nil }
        } message: {
            Text(L("软件里会看不到它。文件可以留着，也可以扔进废纸篓。"))
        }
        .confirmationDialog(
            LF("试跑「%@」？", store.sandboxTarget?.name ?? ""),
            isPresented: Binding(
                get: { store.sandboxTarget != nil },
                set: { if !$0 { store.sandboxTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(L("开始试跑")) { store.confirmSandbox() }
            Button(L("取消"), role: .cancel) { store.sandboxTarget = nil }
        } message: {
            if let skill = store.sandboxTarget {
                Text(SkillSandbox.plan(for: skill).caveats.joined(separator: "\n"))
            }
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
        }
        .onChange(of: store.searchFocusRequest) { _, new in
            guard new > 0 else { return }
            store.nav = .library
            DispatchQueue.main.async { searchFocused = true }
        }
    }

    private func applyLaunchPage() {
        let page = LaunchArgs.value("atlasPage") ?? UserDefaults.standard.string(forKey: "atlasPage")
        guard let page else { return }
        switch page {
        case "overview", "library", "updates", "health", "doctor", "guide", "howto":
            store.nav = .library
        case "settings":
            store.nav = .settings
        default:
            if let target = NavPage(rawValue: page) { store.nav = target }
        }
    }

    private var shell: some View {
        VStack(spacing: 0) {
            ToolbarStrip(searchFocused: $searchFocused, hasAppUpdate: updates.available != nil)
            HStack(spacing: Theme.Space.s12) {
                SidebarRail()
                PageContainer()
            }
            .padding(.horizontal, Theme.Space.s12)
            .padding(.bottom, Theme.Space.s12)
        }
        // 窗口：盖住标题栏，和交通灯同一条中线。全屏：尊重安全区，标题贴在菜单栏下，不再垫一条空灰边。
        .ignoresSafeArea(edges: isFullscreen ? [] : .top)
        .background(FullscreenTopInset(isFullscreen: $isFullscreen))
    }
}

struct ToolbarStrip: View {
    @Environment(AppStore.self) private var store
    var searchFocused: FocusState<Bool>.Binding
    var hasAppUpdate: Bool

    var body: some View {
        HStack(spacing: Theme.Space.s12) {
            // 页面身份：只留文字。图标章与侧栏当前页图标是同一个符号，画两遍纯属重复；
            // 侧栏高亮行已经回答了「我在哪一页」，这里负责「这页现在什么情况」。
            VStack(alignment: .leading, spacing: 1) {
                Text(store.nav.title)
                    .font(Theme.Fonts.panelTitle)
                    .foregroundStyle(Theme.textPrimary)
                Text(store.pageSubtitle)
                    .font(Theme.Fonts.secondary)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
            }

            Spacer()

            // 搜索、安装、刷新只服务「技能库」主任务。别的页面不重复放主操作，
            // 避免每一屏都像控制台。
            if store.nav == .library {
                SearchCapsule(searchFocused: searchFocused)
                    .frame(minWidth: 220, idealWidth: 300, maxWidth: 300)
                InstallChromeButton()
                RefreshButton()
            }

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
        }
        .padding(.leading, Theme.Layout.contentLeading)
        .padding(.trailing, Theme.Space.s12)
        .frame(height: Theme.Layout.toolbar)
    }
}

private struct SearchCapsule: View {
    @Environment(AppStore.self) private var store
    var searchFocused: FocusState<Bool>.Binding

    var body: some View {
        @Bindable var store = store
        let focused = searchFocused.wrappedValue
        HStack(spacing: Theme.Space.s8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(focused ? Theme.accent : Theme.textSecondary)
            TextField(L("搜索技能或要做的事"), text: $store.search)
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
        .help(L("⌘K 搜索；别处按 ⌥⌘K"))
    }
}

/// 安装是次要动作；主任务仍是搜索与使用已有技能。
private struct InstallChromeButton: View {
    @Environment(AppStore.self) private var store

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
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, Theme.Space.s12 + 2)
            .frame(height: 32)
            .contentShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .glassChrome(Capsule(style: .continuous), interactive: true)
        .help(L("装一个新技能（⌘N）"))
    }
}

private struct RefreshButton: View {
    @Environment(AppStore.self) private var store
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
    @Environment(AppStore.self) private var store
    @Namespace private var navSpace

    /// 本机是否有 CC Switch 痕迹（决定底部信任锚点讲哪句承诺）
    private var hasCCSwitchTrace: Bool {
        store.data?.summary.hasCCSwitch == true || store.data?.summary.migrated == true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BrandRow()
                .padding(.horizontal, Theme.Space.s16)
                .padding(.top, Theme.Space.s16)
                .padding(.bottom, Theme.Space.s20)

            // v15 两组六项：库（有什么 / 怎么获得）+ 运营（供给 / 裁决 / 沉淀），设置钉在底部
            VStack(alignment: .leading, spacing: 2) {
                railGroupLabel(L("库"))
                RailItem(page: .library, namespace: navSpace)
                RailItem(page: .discover, namespace: navSpace)
                railGroupLabel(L("运营"))
                    .padding(.top, Theme.Space.s12)
                RailItem(page: .supply, namespace: navSpace)
                RailItem(page: .inbox, namespace: navSpace)
                RailItem(page: .studio, namespace: navSpace)
            }
            .padding(.horizontal, Theme.Space.s8)

            Spacer()

            VStack(spacing: 2) {
                RailItem(page: .settings, namespace: navSpace)
            }
            .padding(.horizontal, Theme.Space.s8)
            .padding(.bottom, Theme.Space.s8)

            // 信任锚点按用户场景给：CC Switch 用户看「数据只读」承诺；
            // 纯本地用户看「收编须确认」承诺——各自最关心的边界
            HStack(spacing: Theme.Space.s8) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.healthy)
                Text(hasCCSwitchTrace ? L("原来的文件不动") : L("先不改你已有的技能"))
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, Theme.Space.s16)
            .padding(.bottom, Theme.Space.s16)
            .help(hasCCSwitchTrace
                ? L("CC Switch 里的原文件不会被改。随时可以撤回来。")
                : L("已经装在软件里的技能，只有你点「收进本库」才会接管。"))
        }
        .frame(width: Theme.Layout.sidebar)
        .frame(maxHeight: .infinity)
        .glassChrome(RoundedRectangle(cornerRadius: Theme.Radius.rail, style: .continuous))
    }

    private func railGroupLabel(_ text: String) -> some View {
        Text(text)
            .font(Theme.Fonts.caption)
            .foregroundStyle(Theme.textTertiary)
            .padding(.horizontal, Theme.Space.s8 + 2)
            .padding(.bottom, 2)
            .accessibilityAddTraits(.isHeader)
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
                Text(L("装好就能用"))
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .help("Skill Atlas")
    }
}

private struct RailItem: View {
    @Environment(AppStore.self) private var store
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
                        .background(Capsule().fill(Theme.accent))
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
        // v15：徽标只挂收件箱，真源 = 聚合器同一口径（已裁决的不计）
        page == .inbox ? store.inboxBadgeCount : 0
    }
}

private struct PageContainer: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        Group {
            if store.data == nil {
                SkeletonPage()
            } else {
                switch store.nav {
                case .library:
                    if store.skills.isEmpty { OnboardingView() } else { LibraryPage() }
                case .discover:
                    DiscoverPage()
                case .supply:
                    SupplyPage()
                case .inbox:
                    InboxPage()
                case .studio:
                    StudioPage()
                case .settings:
                    SettingsPage()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
    @Environment(AppStore.self) private var store
    @State private var appChoicesExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s16) {
            VStack(alignment: .leading, spacing: Theme.Space.s8) {
                Text(L("还没有技能"))
                    .font(Theme.Fonts.panelTitle)
                    .foregroundStyle(Theme.textPrimary)
                Text(L("先装一个。我们会按你常用的软件准备好。"))
                    .font(Theme.Fonts.body)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 0) {
                ForEach(Array(StarterSkill.allCases.enumerated()), id: \.element.id) { index, starter in
                    if index > 0 {
                        Rectangle()
                            .fill(Color.primary.opacity(0.06))
                            .frame(height: 1)
                            .padding(.leading, Theme.Space.s12)
                    }
                    starterRow(starter)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
            .quietControl(cornerRadius: Theme.Radius.tile)

            DisclosureGroup(isExpanded: $appChoicesExpanded) {
                PlatformPrefStrip()
                    .padding(.top, Theme.Space.s12)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("装到哪些软件"))
                        .font(Theme.Fonts.secondaryEmphasis)
                        .foregroundStyle(Theme.textSecondary)
                    Text(L("已经按这台 Mac 上的常用软件选好"))
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .padding(Theme.Space.s12)
            .quietControl(cornerRadius: Theme.Radius.tile)

            HStack(spacing: Theme.Space.s12) {
                Button(L("我有链接…")) {
                    store.installSheetPresented = true
                }
                .buttonStyle(.link)
                .font(Theme.Fonts.secondaryEmphasis)
                .help(L("粘贴链接或选文件夹（⌘N）"))
                if store.canMigrate {
                    Button(L("从 CC Switch 迁入…")) {
                        store.migrationSheetPresented = true
                    }
                    .buttonStyle(.link)
                    .font(Theme.Fonts.secondaryEmphasis)
                    .help(L("把以前用 CC Switch 管的技能收进来"))
                }
            }
        }
        .frame(maxWidth: 420, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.Space.s32)
        .contentSurface()
    }

    private func starterRow(_ starter: StarterSkill) -> some View {
        Button {
            store.beginInstall(url: starter.url)
        } label: {
            HStack(spacing: Theme.Space.s12) {
                Image(systemName: starter.symbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(L(starter.title))
                        .font(Theme.Fonts.rowTitle)
                        .foregroundStyle(Theme.textPrimary)
                    Text(L(starter.blurb))
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer(minLength: Theme.Space.s8)
                Text(L("装"))
                    .font(Theme.Fonts.secondaryEmphasis)
                    .foregroundStyle(Theme.accent)
            }
            .padding(.horizontal, Theme.Space.s12)
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .help(LF("装「%@」", L(starter.title)))
    }
}

struct CopyIconButton: View {
    @Environment(AppStore.self) private var store
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
    @Environment(AppStore.self) private var store
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
