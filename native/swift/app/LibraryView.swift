import AppKit
import Charts
import SwiftUI
#if SWIFT_PACKAGE
import AtlasCore
#endif

// MARK: - 技能库页（列表 + 详情双栏，统计数字分流到工具条副文案）

struct LibraryPage: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        // 整页交给 AppKit 拼：表是真子视图，不再套进 HStack / VStack / opacity。
        // 那些节点即使用 opacity(1) 也会合成组，滑动就变成「每帧重绘整页」。
        LibrarySplitView(store: store, pin: LibraryPin(store))
            .equatable()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 库页只跟这些字段走。安全复扫 / 外链 / hook 统计发布时 pin 不变，跳过 updateNSView。
@MainActor
private struct LibraryPin: Equatable {
    var epoch: Int
    var selected: String?
    var favorites: Set<String>
    var groupBy: String
    var sortOrder: String
    var category: String
    var platform: String
    var stateFilter: String
    var sourceFilter: String
    var favoritesOnly: Bool
    var search: String
    var checkingInteractive: Bool
    var updating: Bool
    var empty: Bool

    init(_ store: AppStore) {
        epoch = store.libraryEpoch
        selected = store.selectedName
        favorites = store.favorites
        groupBy = store.groupBy
        sortOrder = store.sortOrder
        category = store.category
        platform = store.platform
        stateFilter = store.stateFilter
        sourceFilter = store.sourceFilter
        favoritesOnly = store.favoritesOnly
        search = store.debouncedSearch
        checkingInteractive = store.checkingInteractive
        updating = !store.updatingDirectories.isEmpty
        empty = store.filteredSkills.isEmpty
    }
}

private struct LibrarySplitView: NSViewRepresentable, Equatable {
    var store: AppStore
    var pin: LibraryPin

    static func == (lhs: LibrarySplitView, rhs: LibrarySplitView) -> Bool {
        lhs.pin == rhs.pin
    }

    func makeNSView(context: Context) -> LibrarySplitNSView {
        LibrarySplitNSView(store: store)
    }

    func updateNSView(_ view: LibrarySplitNSView, context: Context) {
        view.refresh(store: store)
    }

    static func dismantleNSView(_ view: LibrarySplitNSView, coordinator: ()) {
        view.detachTable()
    }
}

/// 左：筛选条 + 缓存的 NSScrollView；右：按需展开的详情栏。表跨切页活在 Store 上。
@MainActor
final class LibrarySplitNSView: NSView {
    private var store: AppStore
    private let leftPane = NSView()
    private let listPane = NSView()
    private let filterHost: NSHostingView<AnyView>
    private let inspectorHost: NSHostingView<AnyView>
    private let emptyHost: NSHostingView<AnyView>
    private let chrome = PanelChrome()
    private var showingEmpty = false
    private var showingInspector = false
    private let gap: CGFloat = Theme.Space.s12

    init(store: AppStore) {
        self.store = store
        filterHost = NSHostingView(rootView: AnyView(LibraryFilterBar().environment(store)))
        inspectorHost = NSHostingView(rootView: AnyView(InspectorPanel().environment(store)))
        emptyHost = NSHostingView(rootView: AnyView(EmptyListView().environment(store)))
        super.init(frame: .zero)
        wantsLayer = false

        // 高度跟内容，宽度跟左栏。intrinsic 两边都开时，条会按内容宽度居中，
        // 「全部技能」就离开列表左缘。
        filterHost.sizingOptions = .intrinsicContentSize
        filterHost.setContentHuggingPriority(.defaultLow, for: .horizontal)
        filterHost.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        inspectorHost.sizingOptions = []
        emptyHost.sizingOptions = []

        leftPane.wantsLayer = true
        leftPane.layer?.backgroundColor = Theme.panelNSColor.cgColor
        // 不要圆角 + masksToBounds：会把整张表打成离屏图。
        // 圆角由 PanelChrome 盖在四角上，表还是真子视图。
        leftPane.layer?.masksToBounds = false

        addSubview(leftPane)
        addSubview(inspectorHost)
        filterHost.translatesAutoresizingMaskIntoConstraints = false
        listPane.translatesAutoresizingMaskIntoConstraints = false
        chrome.translatesAutoresizingMaskIntoConstraints = false
        leftPane.addSubview(filterHost)
        leftPane.addSubview(listPane)
        leftPane.addSubview(chrome)
        NSLayoutConstraint.activate([
            filterHost.topAnchor.constraint(equalTo: leftPane.topAnchor),
            filterHost.leadingAnchor.constraint(equalTo: leftPane.leadingAnchor),
            filterHost.trailingAnchor.constraint(equalTo: leftPane.trailingAnchor),
            listPane.topAnchor.constraint(equalTo: filterHost.bottomAnchor),
            listPane.leadingAnchor.constraint(equalTo: leftPane.leadingAnchor),
            listPane.trailingAnchor.constraint(equalTo: leftPane.trailingAnchor),
            listPane.bottomAnchor.constraint(equalTo: leftPane.bottomAnchor),
            chrome.topAnchor.constraint(equalTo: leftPane.topAnchor),
            chrome.leadingAnchor.constraint(equalTo: leftPane.leadingAnchor),
            chrome.trailingAnchor.constraint(equalTo: leftPane.trailingAnchor),
            chrome.bottomAnchor.constraint(equalTo: leftPane.bottomAnchor),
        ])

        showingEmpty = store.filteredSkills.isEmpty
        showingInspector = store.selectedSkill != nil
        inspectorHost.isHidden = !showingInspector
        attachList()
        SkillTableController.shared(for: store).reloadFromStore()
    }

    required init?(coder: NSCoder) { nil }

    override var isOpaque: Bool { false }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        leftPane.layer?.backgroundColor = Theme.panelNSColor.cgColor
        chrome.needsDisplay = true
    }

    func refresh(store: AppStore) {
        self.store = store
        let controller = SkillTableController.shared(for: store)
        controller.reloadFromStore()
        let empty = store.filteredSkills.isEmpty
        if empty != showingEmpty {
            showingEmpty = empty
            attachList()
        }
        let inspector = store.selectedSkill != nil
        if inspector != showingInspector {
            showingInspector = inspector
            inspectorHost.isHidden = !inspector
        }
        needsLayout = true
    }

    func detachTable() {
        SkillTableController.shared(for: store).scroll.removeFromSuperview()
    }

    private func attachList() {
        let scroll = SkillTableController.shared(for: store).scroll
        emptyHost.removeFromSuperview()
        scroll.removeFromSuperview()
        let child = showingEmpty ? emptyHost : scroll
        child.translatesAutoresizingMaskIntoConstraints = true
        child.autoresizingMask = [.width, .height]
        child.frame = listPane.bounds
        listPane.addSubview(child)
    }

    override func layout() {
        super.layout()
        let detailWidth = showingInspector
            ? min(440, max(360, bounds.width * 0.44))
            : 0
        let inspectorX = max(0, bounds.width - detailWidth)
        inspectorHost.frame = showingInspector
            ? NSRect(x: inspectorX, y: 0, width: detailWidth, height: bounds.height)
            : .zero
        leftPane.frame = NSRect(
            x: 0,
            y: 0,
            width: max(0, showingInspector ? inspectorX - gap : bounds.width),
            height: bounds.height
        )
        let child = showingEmpty ? emptyHost : SkillTableController.shared(for: store).scroll
        if child.superview === listPane {
            child.frame = listPane.bounds
        }
    }
}

/// 用背景色盖住四角，画出和其他页一样的圆角卡片。不裁切、不合成列表。
private final class PanelChrome: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = false
    }

    required init?(coder: NSCoder) { nil }

    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius = Theme.Radius.panel
        let card = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)
        let field = NSBezierPath(rect: bounds)
        field.append(card)
        field.windingRule = .evenOdd
        Theme.backdropNSColor.setFill()
        field.fill()

        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        NSColor.white.withAlphaComponent(dark ? 0.10 : 0.35).setStroke()
        card.lineWidth = 0.5
        card.stroke()
    }
}

// MARK: - 列表顶栏（筛选 / 排序，不含表本身）

private struct LibraryFilterBar: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            HStack(spacing: Theme.Space.s12) {
                FavoritesTabs()
                Spacer()
                LibraryBillLink()
                HStack(spacing: Theme.Space.s4) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 9, weight: .semibold))
                    Text(L("点右侧图标同步"))
                        .font(Theme.Fonts.caption)
                }
                .foregroundStyle(Theme.textTertiary)
                .fixedSize()
                Text(LF("%lld 个", store.filteredSkills.count))
                    .font(Theme.Fonts.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
                LibraryFilterMenu()
                LibraryDisplayMenu()
            }
            .padding(.horizontal, Theme.Space.s16)
            .padding(.vertical, Theme.Space.s12)

            if store.hasFacetFilters {
                LibraryFilterSummary()
                    .padding(.horizontal, Theme.Space.s16)
                    .padding(.bottom, Theme.Space.s12)
            }

            let multi = SkillTableController.shared(for: store).multi
            if !multi.names.isEmpty {
                BatchBar(names: multi.names)
                    .padding(.horizontal, Theme.Space.s16)
                    .padding(.bottom, Theme.Space.s12)
            }

            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panelFill)
    }
}

/// 多选批量操作条（WP-L 残项）：⌘点按行进入多选。只做收藏与启停，
/// 批量卸载不做（破坏性上限纪律，卸载走单个确认流程）。
private struct BatchBar: View {
    @Environment(AppStore.self) private var store
    var names: Set<String>
    @State private var confirmDisable = false

    var body: some View {
        let targets = store.skills.filter { names.contains($0.name) }
        let disableTargets = targets.filter { $0.origin != .ccSwitch && !$0.managed && !$0.disabled }
        let restoreTargets = targets.filter { $0.disabled }
        let unfavorited = targets.filter { !store.favorites.contains($0.name) }
        HStack(spacing: Theme.Space.s12) {
            Text(LF("已选 %d 个", names.count))
                .font(Theme.Fonts.calloutEmphasis)
                .monospacedDigit()
                .foregroundStyle(Theme.accent)
            batchAction(L("全部收藏"), enabled: !unfavorited.isEmpty) {
                unfavorited.forEach { store.toggleFavorite($0.name) }
            }
            batchAction(L("停用…"), enabled: !disableTargets.isEmpty) {
                confirmDisable = true
            }
            .confirmationDialog(
                LF("停用 %d 个技能？", disableTargets.count),
                isPresented: $confirmDisable,
                titleVisibility: .visible
            ) {
                Button(L("停用这些"), role: .destructive) {
                    disableTargets.forEach { store.setSkillDisabled($0, disabled: true) }
                }
                Button(L("取消"), role: .cancel) {}
            } message: {
                Text(L("只会先停用，文件仍然保留，需要时可以恢复。"))
            }
            batchAction(L("恢复"), enabled: !restoreTargets.isEmpty) {
                restoreTargets.forEach { store.setSkillDisabled($0, disabled: false) }
            }
            Spacer(minLength: 0)
            batchAction(L("清除选择"), enabled: true) {
                store.skillTable?.clearMultiSelection()
            }
        }
        .padding(.horizontal, Theme.Space.s12)
        .frame(height: 36)
        .quietControl(tint: Theme.accent)
    }

    private func batchAction(_ title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(Theme.Fonts.secondaryEmphasis)
            .foregroundStyle(enabled ? Theme.accent : Theme.textTertiary)
            .disabled(!enabled)
    }
}

/// 新手默认只看到一个「筛选」入口。平台、类别、状态、来源仍完整保留，
/// 但不再把六个平台和四组控制项铺满首屏。
private struct LibraryFilterMenu: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var store = store
        let origins = Array(Set(store.skills.map(\.origin.label))).sorted()
        let active = store.hasFacetFilters
        Menu {
            Menu(L("软件")) {
                filterButton(title: L("全部"), value: "全部", selection: $store.platform)
                Divider()
                ForEach(store.visiblePlatforms) { platform in
                    filterButton(
                        title: platform.displayName,
                        value: platform.label,
                        selection: $store.platform
                    )
                }
            }
            Menu(L("类别")) {
                ForEach(["全部"] + store.categories, id: \.self) { option in
                    filterButton(title: L(option), value: option, selection: $store.category)
                }
            }
            Menu(L("状态")) {
                let options = ["全部", "可更新"]
                    + (store.skills.contains(where: \.disabled) ? ["已停用"] : [])
                ForEach(options, id: \.self) { option in
                    filterButton(title: L(option), value: option, selection: $store.stateFilter)
                }
            }
            if origins.count > 1 {
                Menu(L("来源")) {
                    ForEach(["全部"] + origins, id: \.self) { option in
                        filterButton(title: L(option), value: option, selection: $store.sourceFilter)
                    }
                }
            }
            if active {
                Divider()
                Button(L("清除筛选")) { store.clearFacetFilters() }
            }
        } label: {
            menuLabel(
                title: active ? LF("筛选 · %d", store.activeFacetCount) : L("筛选"),
                symbol: "line.3.horizontal.decrease",
                active: active
            )
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .quietControl(tint: active ? Theme.accent : nil)
        .help(L("按软件、类别、状态或来源筛选"))
    }

    private func filterButton(
        title: String,
        value: String,
        selection: Binding<String>
    ) -> some View {
        Button {
            selection.wrappedValue = value
        } label: {
            if selection.wrappedValue == value {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }
}

/// 排序与分组是“怎么看”，合并成一个入口，避免两个菜单与筛选并排竞争。
private struct LibraryDisplayMenu: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var store = store
        let active = store.sortOrder != "名称" || store.groupBy != "不分组"
        Menu {
            Menu(L("排序")) {
                ForEach(["名称", "使用频率", "最近使用"], id: \.self) { option in
                    displayButton(title: option, selection: $store.sortOrder)
                }
            }
            Menu(L("分组")) {
                ForEach(["不分组", "套件", "类别"], id: \.self) { option in
                    displayButton(title: option, selection: $store.groupBy)
                }
            }
        } label: {
            menuLabel(title: L("显示"), symbol: "slider.horizontal.3", active: active)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .quietControl(tint: active ? Theme.accent : nil)
        .help(LF("排序：%@ · 分组：%@", L(store.sortOrder), L(store.groupBy)))
    }

    private func displayButton(title: String, selection: Binding<String>) -> some View {
        Button {
            selection.wrappedValue = title
        } label: {
            if selection.wrappedValue == title {
                Label(L(title), systemImage: "checkmark")
            } else {
                Text(L(title))
            }
        }
    }
}

private struct LibraryFilterSummary: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        HStack(spacing: Theme.Space.s8) {
            Image(systemName: "line.3.horizontal.decrease.circle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.accent)
            Text(LF("已筛选：%@", store.facetSummary))
                .font(Theme.Fonts.secondary)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
            Spacer(minLength: Theme.Space.s8)
            Button(L("清除筛选")) { store.clearFacetFilters() }
                .buttonStyle(.plain)
                .font(Theme.Fonts.secondaryEmphasis)
                .foregroundStyle(Theme.accent)
        }
        .padding(.horizontal, Theme.Space.s8 + 2)
        .frame(height: 28)
        .quietControl(cornerRadius: Theme.Radius.control, tint: Theme.accent)
    }
}

private func menuLabel(title: String, symbol: String, active: Bool) -> some View {
    HStack(spacing: Theme.Space.s4 + 1) {
        Image(systemName: symbol)
            .font(.system(size: 10, weight: .medium))
        Text(title)
            .font(active ? Theme.Fonts.calloutEmphasis : Theme.Fonts.callout)
    }
    .foregroundStyle(active ? Theme.accent : Theme.textSecondary)
    .padding(.horizontal, Theme.Space.s8 + 2)
    .frame(height: 28)
    .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
}

private struct FavoritesTabs: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Namespace private var tabSpace

    var body: some View {
        HStack(spacing: 2) {
            tab(L("全部技能"), active: !store.favoritesOnly) { store.favoritesOnly = false }
            tab(LF("我的收藏 %d", store.favorites.count), active: store.favoritesOnly) { store.favoritesOnly = true }
        }
        .padding(2)
        .quietControl()
        .animation(reduceMotion ? nil : Motion.control, value: store.favoritesOnly)
    }

    private func tab(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(L(title))
                .font(active ? Theme.Fonts.calloutEmphasis : Theme.Fonts.callout)
                .monospacedDigit()
                .foregroundStyle(active ? Theme.textPrimary : Theme.textSecondary)
                .padding(.horizontal, Theme.Space.s12)
                .frame(height: 24)
                .background {
                    if active {
                        // 同心圆角：外层 8 − 内缩 2 = 6
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Theme.raisedThumb)
                            .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.08), radius: 2, y: 1)
                            .matchedGeometryEffect(id: "fav-thumb", in: tabSpace)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct EmptyListView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let favoritesEmpty = store.favoritesOnly && !store.hasActiveFilters
        VStack(spacing: Theme.Space.s8) {
            Image(systemName: favoritesEmpty ? "star" : "magnifyingglass")
                .font(.system(size: 24))
                .foregroundStyle(Theme.textTertiary)
            Text(favoritesEmpty ? L("还没有收藏") : L("没有找到"))
                .font(Theme.Fonts.rowTitle)
                .foregroundStyle(Theme.textPrimary)
            Text(favoritesEmpty ? L("把光标移到列表上点星标。") : L("换个词试试，或清掉筛选。"))
                .font(Theme.Fonts.secondary)
                .lineSpacing(2)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
            if store.hasActiveFilters {
                Button {
                    store.clearFilters()
                } label: {
                    Text(L("清除筛选"))
                        .font(Theme.Fonts.calloutEmphasis)
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, Theme.Space.s12)
                        .frame(height: 28)
                        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                }
                .buttonStyle(PressableButtonStyle())
                .quietControl(tint: Theme.accent)
                .padding(.top, Theme.Space.s4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 详情面板（L1）

struct InspectorPanel: View {
    @Environment(AppStore.self) private var store
    @State private var showUseHelp = false

    var body: some View {
        VStack(spacing: 0) {
            if let skill = store.selectedSkill {
                InspectorHead(skill: skill)
                Rectangle()
                    .fill(Color.primary.opacity(0.06))
                    .frame(height: 1)
                ScrollView {
                    // v15 首屏顺序：横幅 → 用途/何时 → 使用与成本 → 示例 → 调用（降级）→ 更多设置
                    VStack(alignment: .leading, spacing: Theme.Space.s20) {
                        if store.hasBlockingIssue(skill) {
                            BlockingRepairBanner(skill: skill)
                        }
                        DetailSection(title: "用途") {
                            Text(skill.description)
                                .font(Theme.Fonts.body)
                                .lineSpacing(2)
                                .foregroundStyle(Theme.textPrimary)
                                .textSelection(.enabled)
                        }
                        if !skill.whenToUse.isEmpty {
                            DetailSection(title: "什么时候调用") {
                                Text(skill.whenToUse)
                                    .font(Theme.Fonts.body)
                                    .lineSpacing(2)
                                    .foregroundStyle(Theme.textPrimary)
                                    .textSelection(.enabled)
                            }
                        }
                        UsageTrendSection(skill: skill)
                        ContextCostSection(skill: skill)
                        if !skill.examplePrompts.isEmpty {
                            DetailSection(title: "示例说法") {
                                VStack(spacing: Theme.Space.s8) {
                                    ForEach(skill.examplePrompts, id: \.self) { prompt in
                                        PromptChip(prompt: prompt)
                                    }
                                }
                            }
                        }
                        // v13 的核心桥降为次级动作（v15）：agent 时代复制调用语是人类快捷通道
                        DetailSection(title: "调用", hint: "复制调用语，或直接打开软件") {
                            VStack(alignment: .leading, spacing: Theme.Space.s8) {
                                HStack(spacing: Theme.Space.s8) {
                                    CopyCallButton(skill: skill) { showUseHelp = true }
                                    OpenHostButtons(
                                        platforms: hostPlatforms(for: skill),
                                        phrase: AppStore.callPhrase(for: skill),
                                        onCopied: { showUseHelp = true }
                                    )
                                    Spacer(minLength: 0)
                                }
                                if showUseHelp {
                                    UseMissHelp(skill: skill)
                                }
                            }
                        }
                        // 动作区不进折叠组（DESIGN v15：折叠组只许藏解释，
                        // 不许藏动作）。沙箱试跑 / 停用 / 卸载 / 收编原先要展开
                        // 「更多设置」才够得着，深度 3，违反 ≤2 次点击铁律。
                        ManageSection(skill: skill)
                        AdvisorySecuritySection(skill: skill)
                        DisclosureGroup {
                            VStack(alignment: .leading, spacing: Theme.Space.s20) {
                                TriggerTrySection(skill: skill)
                                DetailSection(title: "安装位置") {
                                    Text(skill.sourcePath)
                                        .font(Theme.Fonts.mono)
                                        .foregroundStyle(Theme.textSecondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .help(skill.sourcePath)
                                }
                                if skill.origin != .local {
                                    let broken = AgentPlatform.allCases.filter {
                                        let status = skill.mount($0).status
                                        return status != .ok && status != .disabled
                                    }
                                    if !broken.isEmpty {
                                        DetailSection(title: "连接状态") {
                                            HStack(alignment: .top, spacing: Theme.Space.s24) {
                                                ForEach(broken, id: \.rawValue) { platform in
                                                    MountLine(label: platform.displayName, mount: skill.mount(platform))
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(.top, Theme.Space.s12)
                        } label: {
                            Text(L("更多信息"))
                                .font(Theme.Fonts.secondaryEmphasis)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .padding(Theme.Space.s20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                // 底部 16pt 安全区：最后一个区块完整露出后才贴边
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    Color.clear.frame(height: Theme.Space.s16)
                }
                .panelScroll()
            } else {
                VStack(alignment: .leading, spacing: Theme.Space.s8) {
                    Text(L("还没选技能"))
                        .font(Theme.Fonts.panelTitle)
                        .foregroundStyle(Theme.textPrimary)
                    Text(L("左边点一下，复制那句话，贴进软件。"))
                        .font(Theme.Fonts.callout)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Theme.Space.s20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentSurface()
        .onChange(of: store.selectedName) { _, _ in showUseHelp = false }
    }

    private func hostPlatforms(for skill: Skill) -> [AgentPlatform] {
        let lit = store.visiblePlatforms.filter { skill.platforms.contains($0.label) }
        let preferred = lit.filter { store.preferredPlatforms.contains($0.rawValue) }
        let pool = preferred.isEmpty ? lit : preferred
        return pool.filter { HostLauncher.canOpen($0) }
    }
}

private struct InspectorHead: View {
    @Environment(AppStore.self) private var store
    var skill: Skill

    var body: some View {
        let favorite = store.favorites.contains(skill.name)
        // 两行布局：名称行（图标 + 名称 + 收藏）与动作行（chips + 主按钮）分摊宽度，避免截断
        VStack(alignment: .leading, spacing: Theme.Space.s12) {
            HStack(spacing: Theme.Space.s12) {
                CategoryIcon(category: skill.category, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(skill.name)
                            .font(Theme.Fonts.pageTitle)
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                            .textSelection(.enabled)
                        if skill.managed {
                            Text(L("固定"))
                                .font(Theme.Fonts.caption)
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                    Text(L(skill.category))
                        .font(Theme.Fonts.secondary)
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    store.toggleFavorite(skill.name)
                } label: {
                    Image(systemName: favorite ? "star.fill" : "star")
                        .font(.system(size: 12))
                        .foregroundStyle(favorite ? Theme.accent : Theme.textSecondary)
                        .symbolEffect(.bounce, value: favorite)
                        .frame(width: 28, height: 28)
                        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                }
                .buttonStyle(PressableButtonStyle())
                .quietControl()
                .help(favorite ? "取消收藏" : "收藏")
                Button {
                    store.selectedName = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 28, height: 28)
                        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                }
                .buttonStyle(PressableButtonStyle())
                .quietControl()
                .help(L("收起详情栏"))
            }
            VStack(alignment: .leading, spacing: Theme.Space.s8) {
                HStack(spacing: Theme.Space.s8) {
                    Text(L("同步到 AI 软件"))
                        .font(Theme.Fonts.secondaryEmphasis)
                        .foregroundStyle(Theme.textSecondary)
                    Text(platformHint)
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.textTertiary)
                    Spacer(minLength: 0)
                }
                if skill.managed {
                    Text(L("由本应用生成并挂到所有平台，不能单独停用。"))
                        .font(Theme.Fonts.secondary)
                        .foregroundStyle(Theme.textTertiary)
                } else {
                    PlatformToggleRow(skill: skill)
                }
                // v15：档位与挂载是首屏主控件（Claude 三档，写走供给单写者）
                if !skill.managed, skill.origin == .atlas, !skill.disabled,
                   skill.platforms.contains(AgentPlatform.claude.label) {
                    DetailTierControl(skill: skill)
                }
            }
        }
        .padding(.horizontal, Theme.Space.s20)
        .padding(.vertical, Theme.Space.s16)
    }

    private var platformHint: String {
        switch skill.origin {
        case .atlas: return L("点击图标即可开关")
        case .ccSwitch: return L("由 CC Switch 管理")
        case .local: return L("收进本库后可以开关")
        }
    }

}

/// 详情页「使用情况」块：调用会话数 / 最近使用 / 平台分布（来自本机会话日志索引）
/// v15 合并区：使用统计 + 触发趋势一个屋檐（WP-L）。hook 是 Claude 主源，
/// 回扫补历史（mergeHookStats 已按此合并）；来源在 hint 里如实标注。
private struct UsageTrendSection: View {
    @Environment(AppStore.self) private var store
    @Environment(UsageIndexState.self) private var usageIndex
    var skill: Skill

    var body: some View {
        let hookOn = HookTelemetry.installed()
        let counts = HookTelemetry.weeklyCounts(directory: skill.directory, skillName: skill.name)
        DetailSection(title: "使用", hint: hookOn ? "实时记录，回扫补历史" : "来自本机会话日志回扫") {
            VStack(alignment: .leading, spacing: Theme.Space.s12) {
                if usageIndex.indexing {
                    HStack(spacing: Theme.Space.s8) {
                        ProgressView().controlSize(.small)
                        Text(LF("正在索引使用记录… %d%%", Int(usageIndex.progress * 100)))
                            .font(Theme.Fonts.secondary)
                            .monospacedDigit()
                            .foregroundStyle(Theme.textSecondary)
                    }
                } else if let record = store.usage[skill.directory] {
                    HStack(alignment: .top, spacing: Theme.Space.s24) {
                        usageStat(value: "\(record.total)", label: "调用会话")
                        usageStat(
                            value: record.lastUsed.map { Format.day.string(from: $0) } ?? L("未知"),
                            label: "最近使用"
                        )
                        usageStat(
                            value: "Claude \(record.claudeSessions) · Codex \(record.codexSessions)",
                            label: "平台分布"
                        )
                    }
                } else {
                    Text(L("未发现使用记录"))
                        .font(Theme.Fonts.secondary)
                        .foregroundStyle(Theme.textSecondary)
                }
                if hookOn, counts.filter({ $0 > 0 }).count >= 2 {
                    Chart(Array(counts.enumerated()), id: \.offset) { item in
                        BarMark(
                            x: .value(L("周"), item.offset),
                            y: .value(L("次"), item.element)
                        )
                        .foregroundStyle(Theme.accent)
                    }
                    .chartXAxis(.hidden)
                    .frame(height: 56)
                } else if !hookOn {
                    Text(L("接入使用记录后，这里会显示每周调用次数。"))
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .help(store.usageIndexInfo)
    }

    private func usageStat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(Theme.Fonts.calloutEmphasis)
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
            Text(L(label))
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.textTertiary)
        }
    }
}

/// 详情页 Claude 档位控件（v15 TierSegment 的详情宿主；写走供给单写者 ADR-11）
private struct DetailTierControl: View {
    @Environment(AppStore.self) private var store
    var skill: Skill
    @State private var tier: SlimTier = .core

    var body: some View {
        HStack(spacing: Theme.Space.s8) {
            Text(L("怎么用它"))
                .font(Theme.Fonts.secondaryEmphasis)
                .foregroundStyle(Theme.textSecondary)
            TierSegment(tier: tier, accessibilityName: skill.name) { apply($0) }
            Text(L("只对 Claude Code 生效。"))
                .help(L("这三档是 Claude Code 自己的开关，别的软件没有中间档。要让别的软件也少装几个，去设置里给场景勾上那些软件。"))
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.textTertiary)
            Spacer(minLength: 0)
        }
        .onAppear(perform: reload)
        .onChange(of: skill.name) { _, _ in reload() }
    }

    private func reload() {
        let settings = (try? ProfileWriter.readSettings(at: ProfileWriter.userSettingsURL)) ?? [:]
        let raw = (settings["skillOverrides"] as? [String: Any])?[skill.name] as? String
        switch raw {
        case ProfileExclusion.userInvocableOnly.rawValue: tier = .userInvocable
        case ProfileExclusion.off.rawValue: tier = .off
        default: tier = .core
        }
    }

    private func apply(_ new: SlimTier) {
        guard new != tier else { return }
        let assignment: SupplyAssignment
        switch new {
        case .core: assignment = .core
        case .userInvocable: assignment = .userInvocable
        case .off: assignment = .off
        }
        do {
            try SupplyWriter.write(
                assignments: [skill.name: assignment],
                target: ProfileWriter.userSettingsURL
            )
            Oplog.append(op: "supply-tier", target: skill.directory, ok: true,
                         detail: "\(skill.name) -> \(new.rawValue)")
            tier = new
            store.invalidateSupply()
        } catch {
            store.actionError = error.localizedDescription
        }
    }
}

private struct TriggerTrySection: View {
    @Environment(AppStore.self) private var store
    var skill: Skill
    @State private var phrase = ""
    @State private var result = ""

    var body: some View {
        DetailSection(title: "触发模拟") {
            HStack(spacing: Theme.Space.s8) {
                TextField(L("试一句会不会唤起它"), text: $phrase)
                    .textFieldStyle(.plain)
                    .font(Theme.Fonts.secondary)
                    .padding(.horizontal, Theme.Space.s8)
                    .frame(height: 28)
                    .quietControl(cornerRadius: Theme.Radius.control)
                Button(L("模拟")) {
                    let atRisk = Set(store.doctorReport.atRisk.map(\.skill.name))
                    let ranked = TriggerLab.simulate(
                        phrase: phrase, skills: store.skills, usage: store.usage, atRiskNames: atRisk
                    )
                    if let index = ranked.firstIndex(where: { $0.skill.directory == skill.directory }) {
                        result = LF("第 %d 名，分 %d", index + 1, ranked[index].score)
                    } else if ranked.isEmpty {
                        result = L("没有候选")
                    } else {
                        result = LF("前 8 名里没有。第一是 %@", ranked[0].skill.name)
                    }
                }
                .buttonStyle(PressableButtonStyle())
                .quietControl()
            }
            if !result.isEmpty {
                Text(result)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }
}

private struct ContextCostSection: View {
    @Environment(AppStore.self) private var store
    var skill: Skill

    var body: some View {
        let report = store.doctorReport
        let entry = report.entries.first { $0.skill.name == skill.name }
        let verbose = report.verbose.first { $0.skill.name == skill.name }
        DetailSection(title: "介绍占了多少", hint: "估算") {
            VStack(alignment: .leading, spacing: Theme.Space.s8) {
                if let entry {
                    Text(LF("介绍大约 %lld 字", entry.chars))
                        .font(Theme.Fonts.callout)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                    if report.atRisk.contains(where: { $0.skill.name == skill.name }) {
                        Text(L("介绍偏长，用得少时可能看不见。写出技能名还能用。"))
                            .font(Theme.Fonts.secondary)
                            .foregroundStyle(Theme.warning)
                    }
                }
                if let verbose {
                    Text(L("介绍可以再短一点，好给别的技能留位置。"))
                        .font(Theme.Fonts.secondary)
                        .foregroundStyle(Theme.textSecondary)
                    HStack(alignment: .top, spacing: Theme.Space.s8) {
                        Text(verbose.suggestion)
                            .font(Theme.Fonts.body)
                            .foregroundStyle(Theme.textPrimary)
                            .textSelection(.enabled)
                        CopyIconButton(text: verbose.suggestion, help: L("复制缩短建议"))
                    }
                    .padding(Theme.Space.s8)
                    .quietControl(cornerRadius: Theme.Radius.tile)
                }
            }
        }
    }
}

/// 详情页「管理」块：Atlas 技能可开关平台 / 停用；CC Switch 只读；
/// 本地直装可「收进 Skill Atlas 库」接管，也可停用
private struct ManageSection: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var skill: Skill

    var body: some View {
        DetailSection(title: "管理") {
            switch skill.origin {
            case .ccSwitch:
                Text(L("还在 CC Switch 里。要在这里开关，先去设置里迁进来。"))
                    .font(Theme.Fonts.secondary)
                    .foregroundStyle(Theme.textTertiary)
                fileButtons
            case .atlas:
                atlasControls
            case .local:
                VStack(alignment: .leading, spacing: Theme.Space.s12) {
                    if !skill.disabled {
                        adoptControls
                    }
                    HStack(spacing: Theme.Space.s8) {
                        localDisableControls
                        uninstallButton
                    }
                    fileButtons
                }
            }
        }
    }

    /// 本地直装的主动作：收进本库接管。拷入 ~/.skill-atlas/skills/、原散装目录
    /// 替换成指向本库的软链；重扫后 origin 变 atlas，上方平台 logo 开关解锁。
    private var adoptControls: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s8) {
            Button {
                store.adoptLocalSkill(skill)
            } label: {
                HStack(spacing: Theme.Space.s4) {
                    Image(systemName: "square.and.arrow.down.on.square")
                        .font(.system(size: 11, weight: .semibold))
                    Text(L("收进本库"))
                        .font(Theme.Fonts.calloutEmphasis)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, Theme.Space.s12)
                .frame(height: 28)
                .background {
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .fill(Theme.accent)
                }
                .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            }
            .buttonStyle(PressableButtonStyle())
            .help(L("拷进本库，之后可以在这里开关平台"))
            // 实体在平台目录之外（软链指向开发目录等）：收编是拷贝快照，live-edit 会断开
            if SkillActions.isExternalSource(skill) {
                Text(LF("文件不在常用技能目录里（%@）。收进来会拷一份，之后改原来的位置不会生效。", displaySourcePath))
                    .font(Theme.Fonts.secondary)
                    .foregroundStyle(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var displaySourcePath: String {
        skill.sourcePath.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    private var atlasControls: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s8) {
            VStack(alignment: .leading, spacing: Theme.Space.s8) {
                Text(L("在哪些软件里使用"))
                    .font(Theme.Fonts.secondaryEmphasis)
                    .foregroundStyle(Theme.textSecondary)
                if skill.managed {
                    Text(L("由本应用生成并挂到所有平台，不能单独停用。"))
                        .font(Theme.Fonts.secondary)
                        .foregroundStyle(Theme.textTertiary)
                } else {
                    PlatformToggleRow(skill: skill)
                }
            }
            if skill.updateAvailable {
                Button {
                    store.requestUpdate(skill)
                } label: {
                    Text(L("有新版本…"))
                        .font(Theme.Fonts.calloutEmphasis)
                        .foregroundStyle(.white)
                        .padding(.horizontal, Theme.Space.s12)
                        .frame(height: 28)
                        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                }
                .buttonStyle(PressableButtonStyle())
                .accentGlass(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                .help(L("先看改了什么，确认后再更新"))
            }
            HStack(spacing: Theme.Space.s8) {
                localDisableControls
                uninstallButton
            }
            Button {
                store.requestSandbox(skill)
            } label: {
                Text(L("沙箱试跑"))
                    .font(Theme.Fonts.calloutEmphasis)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, Theme.Space.s12)
                    .frame(height: 28)
            }
            .buttonStyle(PressableButtonStyle())
            .quietControl()
            .help(L("开一个只装这一个技能的会话。不是安全沙箱。"))
            fileButtons
            if SkillBackup.latest(directory: skill.directory) != nil {
                Button {
                    store.requestRollback(skill)
                } label: {
                    Text(L("回滚"))
                        .font(Theme.Fonts.calloutEmphasis)
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, Theme.Space.s12)
                        .frame(height: 28)
                }
                .buttonStyle(PressableButtonStyle())
                .quietControl()
                .help(L("恢复到最近一次备份"))
            }
        }
    }

    private var fileButtons: some View {
        HStack(spacing: Theme.Space.s8) {
            Button {
                store.readerSkill = skill
            } label: {
                Text(L("查看说明"))
                    .font(Theme.Fonts.calloutEmphasis)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, Theme.Space.s12)
                    .frame(height: 28)
                    .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            }
            .buttonStyle(PressableButtonStyle())
            .quietControl()
            .help(L("阅读 SKILL.md"))
            Button {
                store.openFolder(skill.sourcePath)
            } label: {
                Text(L("打开目录"))
                    .font(Theme.Fonts.calloutEmphasis)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, Theme.Space.s12)
                    .frame(height: 28)
                    .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            }
            .buttonStyle(PressableButtonStyle())
            .quietControl()
        }
    }

    private var uninstallButton: some View {
        Button(L("卸载…"), role: .destructive) {
            store.requestUninstall(skill)
        }
        .help(L("从软件里拿掉。文件可以留着，也可以扔掉。"))
    }

    @ViewBuilder
    private var localDisableControls: some View {
        if skill.disabled {
            Button {
                withAnimation(reduceMotion ? nil : Motion.standard) {
                    store.setSkillDisabled(skill, disabled: false)
                }
            } label: {
                Text(L("恢复"))
                    .font(Theme.Fonts.calloutEmphasis)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Theme.Space.s12)
                    .frame(height: 28)
            }
            .buttonStyle(PressableButtonStyle())
            .accentGlass(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            .help(L("重新给软件用，文件还在"))
        } else {
            Button {
                withAnimation(reduceMotion ? nil : Motion.standard) {
                    store.requestDisable(skill)
                }
            } label: {
                Text(L("停用"))
                    .font(Theme.Fonts.calloutEmphasis)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, Theme.Space.s12)
                    .frame(height: 28)
            }
            .buttonStyle(PressableButtonStyle())
            .quietControl()
            .help(L("先不用。文件还在，随时恢复。"))
        }
    }
}

/// 详情页主按钮：一键复制该技能的调用语，成功后勾选反馈
private struct CopyCallButton: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var copied = false
    var skill: Skill
    var onCopied: () -> Void = {}

    var body: some View {
        Button {
            store.copyToPasteboard(AppStore.callPhrase(for: skill))
            onCopied()
            withAnimation(reduceMotion ? nil : Motion.control) { copied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                withAnimation(reduceMotion ? nil : Motion.control) { copied = false }
            }
        } label: {
            HStack(spacing: Theme.Space.s4) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                Text(copied ? L("已复制") : L("复制调用语"))
                    .font(Theme.Fonts.calloutEmphasis)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, Theme.Space.s12)
            .frame(height: 28)
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .accentGlass(
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous),
            tint: copied ? Theme.healthy : Theme.accent
        )
        .help(LF("复制：%@", AppStore.callPhrase(for: skill)))
    }
}

private struct DetailSection<Content: View>: View {
    var title: String
    var hint: String?
    @ViewBuilder var content: Content

    init(title: String, hint: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.hint = hint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s8) {
            HStack(spacing: Theme.Space.s8) {
                Text(L(title))
                    .font(Theme.Fonts.secondaryEmphasis)
                    .foregroundStyle(Theme.textSecondary)
                if let hint {
                    Text(L(hint))
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            content
        }
    }
}

private struct PromptChip: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var copied = false
    var prompt: String

    var body: some View {
        HStack(spacing: Theme.Space.s8) {
            Text("“\(prompt)”")
                .font(Theme.Fonts.callout)
                .lineSpacing(2)
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            Button {
                store.copyToPasteboard(prompt)
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
            .help(L("复制示例"))
        }
        .padding(.horizontal, Theme.Space.s12)
        .padding(.vertical, Theme.Space.s8)
        .quietControl(cornerRadius: Theme.Radius.row)
    }
}

private struct MountLine: View {
    var label: String
    var mount: Mount

    var body: some View {
        let tint: Color = mount.status == .ok
            ? Theme.healthy
            : mount.status == .disabled ? Color.secondary.opacity(0.45) : Theme.error
        HStack(spacing: Theme.Space.s8) {
            StatusDot(tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(Theme.Fonts.calloutEmphasis)
                    .foregroundStyle(Theme.textPrimary)
                Text(mount.status.label)
                    .font(Theme.Fonts.secondary)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }
}

/// 只有挡住「用」的问题才出现在详情首屏：挂载失败，或高风险写法。
private struct BlockingRepairBanner: View {
    @Environment(AppStore.self) private var store
    var skill: Skill

    var body: some View {
        let critical = store.criticalFindings(for: skill)
        VStack(alignment: .leading, spacing: Theme.Space.s8) {
            HStack(alignment: .top, spacing: Theme.Space.s8) {
                Image(systemName: critical.isEmpty ? "link.badge.plus" : "lock.shield")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(critical.isEmpty ? Theme.warning : Theme.error)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: Theme.Space.s4) {
                    Text(critical.isEmpty
                         ? L("这个 Skill 现在连不上 AI 软件")
                         : LF("先确认“%@”里的高风险写法", skill.name))
                        .font(Theme.Fonts.rowTitle)
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(bannerDetail(critical: critical))
                        .font(Theme.Fonts.secondary)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: Theme.Space.s12) {
                        if let finding = critical.first {
                            Button(L("打开原文")) { store.openFinding(finding, in: skill) }
                        } else {
                            Button(L("打开目录")) { store.openFolder(skill.sourcePath) }
                        }
                        Button(L("去「检查」看这一条")) { store.openInbox(for: skill) }
                    }
                    .buttonStyle(.plain)
                    .font(Theme.Fonts.secondaryEmphasis)
                    .foregroundStyle(Theme.accent)
                }
            }
        }
        .padding(Theme.Space.s12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                .fill((critical.isEmpty ? Theme.warning : Theme.error).opacity(0.06))
        }
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                .strokeBorder((critical.isEmpty ? Theme.warning : Theme.error).opacity(0.16), lineWidth: 0.5)
        }
    }

    private func bannerDetail(critical: [SecurityFinding]) -> String {
        if let finding = critical.first {
            return finding.beginnerNote + " " + L("先别把敏感资料交给它。上面点软件图标就能同步。")
        }
        let problem = skill.problems.first ?? L("它与 AI 软件的连接需要确认。")
        return problem + " " + L("上面点软件图标就能同步。")
    }
}

private struct UseMissHelp: View {
    @Environment(AppStore.self) private var store
    var skill: Skill

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s4) {
            Text(L("调用语里写出技能名更稳。确认上面已经点亮你正在用的软件。"))
                .font(Theme.Fonts.secondary)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            // 这里原来挂着「去收件箱看这一条」——复制调用语根本不产生任何
            // 收件箱条目，点过去只会是一屏不相干的事项。改成真正能帮上忙的：
            // 用一句话验证它会不会被唤到。
            Button(L("试一句话，看它会不会被唤到")) {
                store.simulatePhrase = AppStore.callPhrase(for: skill)
                store.nav = .add
            }
            .buttonStyle(.plain)
            .font(Theme.Fonts.secondaryEmphasis)
            .foregroundStyle(Theme.accent)
        }
        .padding(.top, Theme.Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// 警告级安全命中不抢首屏。需要时在「更多设置」里打开原文核对。
private struct AdvisorySecuritySection: View {
    @Environment(AppStore.self) private var store
    var skill: Skill

    var body: some View {
        let findings = store.advisoryFindings(for: skill)
        if findings.isEmpty {
            EmptyView()
        } else {
            DetailSection(title: "安全扫描", hint: "命中不等于有问题。") {
                VStack(alignment: .leading, spacing: Theme.Space.s8) {
                    ForEach(findings.prefix(8)) { finding in
                        FindingRow(finding: finding) {
                            store.openFinding(finding, in: skill)
                        }
                    }
                }
                .padding(Theme.Space.s12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .quietControl(cornerRadius: Theme.Radius.tile)
            }
        }
    }
}

// MARK: - 更新 diff 预览（三期 1：技能文本变更 = 行为变更，先看再更）

// MARK: - 更新审阅（G1）：diff 强制审阅 + 本地改动警示 + 备份后更新

/// unified diff 上色渲染（单技能审阅与批量审阅共用）
struct DiffTextView: View {
    var diff: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(diff.split(separator: "\n", omittingEmptySubsequences: false).enumerated()), id: \.offset) { _, line in
                    diffLine(String(line))
                }
            }
            .padding(Theme.Space.s8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .quietControl(cornerRadius: Theme.Radius.tile)
        .panelScroll()
    }

    private func diffLine(_ line: String) -> some View {
        let color: Color
        if line.hasPrefix("+") && !line.hasPrefix("+++") { color = Theme.healthy }
        else if line.hasPrefix("-") && !line.hasPrefix("---") { color = Theme.error }
        else if line.hasPrefix("@@") { color = Theme.accent }
        else { color = Theme.textSecondary }
        return Text(line.isEmpty ? " " : line)
            .font(Theme.Fonts.mono)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 本地改动警示块：说明补丁保护机制，列出 git status 行
struct DirtyNotice: View {
    var lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s4) {
            Label(
                LF("本地改过 %d 处。更新前自动备份并导出补丁；能干净重放才重放，否则保持纯上游版（补丁在 skill-patches，可回滚）。", lines.count),
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(Theme.Fonts.calloutEmphasis)
            .foregroundStyle(Theme.warning)
            ForEach(Array(lines.prefix(6).enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(Theme.Fonts.mono)
                    .foregroundStyle(Theme.textSecondary)
            }
            if lines.count > 6 {
                Text(LF("…共 %d 行改动", lines.count))
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(Theme.Space.s8 + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .fill(Theme.warning.opacity(0.10))
        }
    }
}

/// 单技能更新审阅 sheet：看到 diff 才能确认——没有不经审阅的更新
struct UpdateReviewSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private var review: AppStore.UpdateReview? { store.updateReview }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1)
            content.padding(Theme.Space.s20)
        }
        .frame(width: 640, height: 560)
        .background(.regularMaterial)
    }

    private var header: some View {
        HStack(spacing: Theme.Space.s12) {
            Image(systemName: "plus.forwardslash.minus")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 28, height: 28)
                .background {
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .fill(Theme.accent.opacity(0.12))
                }
            VStack(alignment: .leading, spacing: 1) {
                Text(review?.skill.name ?? "")
                    .font(Theme.Fonts.panelTitle)
                    .foregroundStyle(Theme.textPrimary)
                Text(L("上游变更审阅 · 确认后先备份再更新"))
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 28, height: 28)
                    .quietControl()
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, Theme.Space.s20)
        .padding(.vertical, Theme.Space.s16)
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s12) {
            if let review, review.loaded {
                if !review.dirty.isEmpty {
                    DirtyNotice(lines: review.dirty)
                }
                if !review.stat.isEmpty {
                    Text(review.stat)
                        .font(Theme.Fonts.mono)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(6)
                        .padding(Theme.Space.s8 + 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .quietControl(cornerRadius: Theme.Radius.control)
                }
                if review.diff.isEmpty {
                    emptyDiff
                } else {
                    DiffTextView(diff: review.diff)
                }
            } else {
                HStack(spacing: Theme.Space.s8) {
                    ProgressView().controlSize(.small)
                    Text(L("正在对照上游…"))
                        .font(Theme.Fonts.secondary)
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack {
                Spacer()
                Button {
                    store.confirmUpdate()
                } label: {
                    HStack(spacing: Theme.Space.s4) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 11, weight: .semibold))
                        Text(L("备份并更新"))
                            .font(Theme.Fonts.calloutEmphasis)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, Theme.Space.s16)
                    .frame(height: 28)
                    .contentShape(Capsule())
                }
                .buttonStyle(PressableButtonStyle())
                .accentGlass(Capsule(style: .continuous))
                .keyboardShortcut(.defaultAction)
                .disabled(review?.loaded != true)
            }
        }
    }

    private var emptyDiff: some View {
        VStack(spacing: Theme.Space.s8) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 22))
                .foregroundStyle(Theme.textTertiary)
            Text(L("上游没有文本变更（可能只是提交记录前移）"))
                .font(Theme.Fonts.secondary)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 批量更新审阅 sheet：逐技能折叠 diff；本地改过的默认跳过，只能去详情页单独审阅
struct BatchUpdateSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private var reviews: [AppStore.UpdateReview] { store.batchReviews ?? [] }
    private var cleanCount: Int { reviews.filter { $0.dirty.isEmpty }.count }
    private var dirtyCount: Int { reviews.count - cleanCount }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1)
            content.padding(Theme.Space.s20)
        }
        .frame(width: 680, height: 600)
        .background(.regularMaterial)
    }

    private var header: some View {
        HStack(spacing: Theme.Space.s12) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 28, height: 28)
                .background {
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .fill(Theme.accent.opacity(0.12))
                }
            VStack(alignment: .leading, spacing: 1) {
                Text(L("批量更新审阅"))
                    .font(Theme.Fonts.panelTitle)
                    .foregroundStyle(Theme.textPrimary)
                Text(L("逐个展开看 diff · 每个技能更新前自动备份"))
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 28, height: 28)
                    .quietControl()
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, Theme.Space.s20)
        .padding(.vertical, Theme.Space.s16)
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s12) {
            if reviews.isEmpty {
                HStack(spacing: Theme.Space.s8) {
                    ProgressView().controlSize(.small)
                    Text(L("正在逐个对照上游…"))
                        .font(Theme.Fonts.secondary)
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.s8) {
                        ForEach(reviews) { review in
                            reviewRow(review)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .panelScroll()
                if dirtyCount > 0 {
                    Text(LF("%d 个技能本地有改动，本次跳过。可在详情页「审阅并更新…」单独处理。", dirtyCount))
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.warning)
                }
            }
            HStack {
                Spacer()
                Button {
                    store.confirmBatchUpdate()
                } label: {
                    HStack(spacing: Theme.Space.s4) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 11, weight: .semibold))
                        Text(LF("备份并更新 %d 个", cleanCount))
                            .font(Theme.Fonts.calloutEmphasis)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, Theme.Space.s16)
                    .frame(height: 28)
                    .contentShape(Capsule())
                }
                .buttonStyle(PressableButtonStyle())
                .accentGlass(Capsule(style: .continuous))
                .keyboardShortcut(.defaultAction)
                .disabled(cleanCount == 0)
            }
        }
    }

    private func reviewRow(_ review: AppStore.UpdateReview) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: Theme.Space.s8) {
                if !review.dirty.isEmpty {
                    DirtyNotice(lines: review.dirty)
                }
                if review.diff.isEmpty {
                    Text(L("上游没有文本变更（可能只是提交记录前移）"))
                        .font(Theme.Fonts.secondary)
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    DiffTextView(diff: review.diff)
                        .frame(height: 220)
                }
            }
            .padding(.top, Theme.Space.s4)
        } label: {
            HStack(spacing: Theme.Space.s8) {
                Text(review.skill.name)
                    .font(Theme.Fonts.calloutEmphasis)
                    .foregroundStyle(Theme.textPrimary)
                if !review.dirty.isEmpty {
                    Label(L("本地有改动，跳过"), systemImage: "exclamationmark.triangle.fill")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.warning)
                }
                Spacer()
                Text(review.stat.split(separator: "\n").last.map(String.init) ?? "")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
        }
        .padding(Theme.Space.s8 + 2)
        .quietControl(cornerRadius: Theme.Radius.control)
    }
}
