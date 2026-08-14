import SwiftUI

// MARK: - 技能库页（列表 + 详情双栏，统计数字分流到工具条副文案与体检页）

struct LibraryPage: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Theme.Space.s12) {
            SkillBrowser()
            // 详情栏按需展开：没选中就收起，列表占满整宽
            if store.selectedSkill != nil {
                InspectorPanel()
                    .frame(width: 440)
                    .transition(reduceMotion
                        ? .opacity
                        : .move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(maxHeight: .infinity)
        .animation(reduceMotion ? nil : Motion.standard, value: store.selectedSkill?.name != nil)
    }
}

// MARK: - 技能列表面板

struct SkillBrowser: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        let skills = store.filteredSkills
        VStack(spacing: 0) {
            UpdatesBanner()
            AdoptBanner()

            // 第一行：视图切换（全部/收藏）＋ 排序 ＋ 计数——「怎么看」的控件
            HStack(spacing: Theme.Space.s12) {
                FavoritesTabs()
                Spacer()
                FilterMenu(label: "分组", selection: $store.groupBy,
                           options: ["不分组", "套件", "类别"], defaultOption: "不分组")
                FilterMenu(label: "排序", selection: $store.sortOrder,
                           options: ["名称", "使用频率", "最近使用"], defaultOption: "名称")
                Text(LF("%lld 项", skills.count))
                    .font(Theme.Fonts.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, Theme.Space.s16)
            .padding(.top, Theme.Space.s16)
            .padding(.bottom, Theme.Space.s12)

            // 第二行：筛选（类别/平台/状态）——「筛哪些」的控件，与第一行分工
            FilterRow()
                .padding(.horizontal, Theme.Space.s16)
                .padding(.bottom, Theme.Space.s12)

            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 1)

            if skills.isEmpty {
                EmptyListView()
            } else {
                // 玻璃列表：透明底 + 悬停/选中胶囊，L1 材质透出来。
                // 禁止 inset List 斑马纹（DESIGN.md §10.6）——不透明条纹像表格软件。
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2, pinnedViews: [.sectionHeaders]) {
                            ForEach(store.groupedSkills(skills), id: \.0) { groupName, groupSkills in
                                Section {
                                    ForEach(groupSkills) { skill in
                                        SkillRowView(skill: skill)
                                            .id(skill.name)
                                            .contextMenu { SkillContextMenu(skill: skill) }
                                    }
                                } header: {
                                    if !groupName.isEmpty {
                                        HStack(spacing: Theme.Space.s4) {
                                            Text(groupName)
                                                .font(Theme.Fonts.secondaryEmphasis)
                                                .foregroundStyle(Theme.textSecondary)
                                            Text("\(groupSkills.count)")
                                                .font(Theme.Fonts.caption)
                                                .monospacedDigit()
                                                .foregroundStyle(Theme.textTertiary)
                                            Spacer()
                                        }
                                        .padding(.horizontal, Theme.Space.s12)
                                        .padding(.top, Theme.Space.s8)
                                        .padding(.bottom, Theme.Space.s4)
                                        .background(.regularMaterial)
                                    }
                                }
                            }
                        }
                        .padding(Theme.Space.s8)
                    }
                    .panelScroll()
                    .onChange(of: store.selectedName) { _, name in
                        guard let name else { return }
                        proxy.scrollTo(name)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 列表顶部更新条（更新页并入技能库后的主入口，参考 CC Switch）：
/// 有可更新技能时出现；点文字筛出可更新，右侧「全部更新」一键快进合并。
private struct UpdatesBanner: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let updatable = store.updatableSkills
        // 只有「有可更新」或用户手动点了检查才出现；后台自动检查完全静默
        if !updatable.isEmpty || store.checkingInteractive {
            VStack(spacing: 0) {
                HStack(spacing: Theme.Space.s8) {
                    if store.checkingInteractive {
                        ProgressView().controlSize(.mini)
                        Text(L("正在对照上游仓库…"))
                            .font(Theme.Fonts.calloutEmphasis)
                            .foregroundStyle(Theme.textSecondary)
                    } else {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                        Button {
                            store.jumpToUpdatable()
                        } label: {
                            Text(LF("%lld 个技能有新版本", updatable.count))
                                .font(Theme.Fonts.calloutEmphasis)
                                .foregroundStyle(Theme.textPrimary)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(L("只看可更新的技能"))
                        Text(L("对照上游 git，快进合并，不覆盖本地改动"))
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    Spacer()
                    if !store.checkingInteractive {
                        Button {
                            Task { await store.checkSkillUpdates(interactive: true) }
                        } label: {
                            Text(L("重新检查"))
                                .font(Theme.Fonts.calloutEmphasis)
                                .foregroundStyle(Theme.textSecondary)
                                .padding(.horizontal, Theme.Space.s8 + 2)
                                .frame(height: 24)
                                .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                        }
                        .buttonStyle(PressableButtonStyle())
                        .quietControl()
                        .disabled(store.checkingSkillUpdates)
                        .help(L("git fetch 对照 origin 分支（⌘U）"))
                        Button {
                            store.updateAllSkills()
                        } label: {
                            HStack(spacing: Theme.Space.s4) {
                                if store.updatingDirectories.isEmpty {
                                    Image(systemName: "arrow.down.circle")
                                        .font(.system(size: 10, weight: .semibold))
                                } else {
                                    ProgressView().controlSize(.mini).tint(.white)
                                }
                                Text(store.updatingDirectories.isEmpty ? L("全部更新") : L("更新中…"))
                                    .font(Theme.Fonts.calloutEmphasis)
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, Theme.Space.s12)
                            .frame(height: 24)
                            .contentShape(Capsule())
                        }
                        .buttonStyle(PressableButtonStyle())
                        .accentGlass(Capsule(style: .continuous))
                        .disabled(!store.updatingDirectories.isEmpty)
                        .help(L("逐个 git pull --ff-only，失败不强制（⇧⌘U）"))
                    }
                }
                .padding(.horizontal, Theme.Space.s16)
                .frame(height: 40)
                .background(Theme.accent.opacity(0.07))
                Rectangle()
                    .fill(Theme.accent.opacity(0.12))
                    .frame(height: 1)
            }
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
        }
    }
}

/// 列表顶部收编条（参照 UpdatesBanner）：发现散装的本地直装技能时出现。
/// 点文字筛出本地安装；右侧「全部收编」批量拷入本库并接管挂载（确认后执行）。
private struct AdoptBanner: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var confirming = false

    var body: some View {
        let adoptable = store.adoptableSkills
        if !adoptable.isEmpty {
            VStack(spacing: 0) {
                HStack(spacing: Theme.Space.s8) {
                    Image(systemName: "square.and.arrow.down.on.square.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                    Button {
                        store.jumpToLocalSkills()
                    } label: {
                        Text(LF("%lld 个本地技能可收进本库", adoptable.count))
                            .font(Theme.Fonts.calloutEmphasis)
                            .foregroundStyle(Theme.textPrimary)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(L("只看本地安装的技能"))
                    Text(L("收编后可开关平台、停用、卸载"))
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.textTertiary)
                    Spacer()
                    Button {
                        confirming = true
                    } label: {
                        HStack(spacing: Theme.Space.s4) {
                            Image(systemName: "square.and.arrow.down.on.square")
                                .font(.system(size: 10, weight: .semibold))
                            Text(L("全部收编"))
                                .font(Theme.Fonts.calloutEmphasis)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, Theme.Space.s12)
                        .frame(height: 24)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(PressableButtonStyle())
                    .accentGlass(Capsule(style: .continuous))
                    .help(L("把全部本地直装技能拷入本库并接管挂载"))
                    .confirmationDialog(
                        LF("把 %lld 个本地技能收进 Skill Atlas 库？", adoptable.count),
                        isPresented: $confirming,
                        titleVisibility: .visible
                    ) {
                        Button(L("收编")) { store.adoptAllLocalSkills() }
                        Button(L("取消"), role: .cancel) {}
                    } message: {
                        Text(confirmMessage(adoptable))
                    }
                }
                .padding(.horizontal, Theme.Space.s16)
                .frame(height: 40)
                .background(Theme.accent.opacity(0.07))
                Rectangle()
                    .fill(Theme.accent.opacity(0.12))
                    .frame(height: 1)
            }
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
        }
    }

    private func confirmMessage(_ adoptable: [Skill]) -> String {
        var text = L("内容拷入 ~/.skill-atlas/skills/，原平台目录替换成指向本库的软链，之后在本应用统一开关平台。")
        let external = adoptable.filter { SkillActions.isExternalSource($0) }.count
        if external > 0 {
            text += LF("其中 %lld 个的实体在平台目录之外，收编后编辑原目录不再生效。", external)
        }
        return text
    }
}

private struct FavoritesTabs: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                            .fill(.background)
                            .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                            .matchedGeometryEffect(id: "fav-thumb", in: tabSpace)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct FilterRow: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        HStack(spacing: Theme.Space.s8 + 2) {
            FilterMenu(label: "类别", selection: $store.category, options: ["全部"] + store.categories)
            PlatformFilterStrip()
            // 健康状态不在列表里标注（入口统一在体检页）；这里只筛安装状态
            FilterMenu(
                label: "状态",
                selection: $store.stateFilter,
                options: ["全部", "可更新"]
                    + (store.skills.contains(where: \.disabled) ? ["已停用"] : [])
            )
            // 只有两种来源并存时才需要来源筛选
            let origins = Array(Set(store.skills.map(\.origin.label))).sorted()
            if origins.count > 1 {
                FilterMenu(label: "来源", selection: $store.sourceFilter,
                           options: ["全部"] + origins)
            }
            Spacer()
            if store.hasActiveFilters {
                Button(L("清除")) { store.clearFilters() }
                    .buttonStyle(.plain)
                    .font(Theme.Fonts.calloutEmphasis)
                    .foregroundStyle(Theme.accent)
            }
        }
    }
}

struct FilterMenu: View {
    var label: String
    @Binding var selection: String
    var options: [String]
    var display: (String) -> String = { $0 }
    var defaultOption = "全部"

    var body: some View {
        let active = selection != defaultOption
        Menu {
            ForEach(options, id: \.self) { option in
                Button {
                    selection = option
                } label: {
                    if option == selection {
                        Label(L(display(option)), systemImage: "checkmark")
                    } else {
                        Text(L(display(option)))
                    }
                }
            }
        } label: {
            HStack(spacing: Theme.Space.s4) {
                Text(L(label))
                    .font(Theme.Fonts.callout)
                    .foregroundStyle(Theme.textTertiary)
                Text(L(display(selection)))
                    .font(Theme.Fonts.calloutEmphasis)
                    .foregroundStyle(active ? Theme.accent : Theme.textPrimary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, Theme.Space.s8)
            .frame(height: 28)
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .quietControl(tint: active ? Theme.accent : nil)
    }
}

private struct SkillRowView: View {
    @EnvironmentObject private var store: AppStore
    @State private var hovering = false
    var skill: Skill

    var body: some View {
        let selected = store.selectedName == skill.name
        let favorite = store.favorites.contains(skill.name)
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)

        HStack(spacing: Theme.Space.s12) {
            CategoryIcon(category: skill.category, size: 28, style: .quiet)
            VStack(alignment: .leading, spacing: 2) {
                Text(skill.name)
                    .font(Theme.Fonts.rowTitle)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(shortDescription)
                    .font(Theme.Fonts.secondary)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Theme.Space.s4)
            if hovering || selected {
                CopyIconButton(text: AppStore.callPhrase(for: skill), help: "复制调用语")
            }
            if hovering || favorite || selected {
                Button {
                    store.toggleFavorite(skill.name)
                } label: {
                    Image(systemName: favorite ? "star.fill" : "star")
                        .font(.system(size: 12))
                        .foregroundStyle(favorite ? Theme.accent : Theme.textTertiary)
                        .symbolEffect(.bounce, value: favorite)
                        .frame(width: 24, height: 24)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(favorite ? L("取消收藏") : L("收藏"))
            }
            PlatformStrip(skill: skill, platforms: store.visiblePlatforms)
            // 健康状态不在列表标注（统一去体检页看）；这里只保留安装状态
            if skill.disabled {
                Text(L("已停用"))
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textTertiary)
            } else if skill.updateAvailable {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.accent)
                    .help(L("有新版本，右键或详情页更新"))
            }
        }
        .padding(.horizontal, Theme.Space.s12)
        .padding(.vertical, Theme.Space.s8)
        .contentShape(shape)
        .background {
            shape.fill(
                selected
                    ? Theme.accent.opacity(0.12)
                    : hovering ? Color.primary.opacity(0.04) : Color.clear
            )
        }
        .overlay {
            if selected {
                shape.strokeBorder(Theme.accent.opacity(0.20), lineWidth: 0.5)
            }
        }
        .opacity(skill.disabled ? 0.55 : 1)
        .onHover { hovering = $0 }
        // 点击选中并展开详情；再点一次收起
        .onTapGesture {
            store.selectedName = selected ? nil : skill.name
        }
    }

    private var shortDescription: String {
        var clean = skill.description.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        for prefix in ["Use this skill", "Use when", "当任务", "用于"] where clean.lowercased().hasPrefix(prefix.lowercased()) {
            clean = String(clean.dropFirst(prefix.count))
            break
        }
        clean = clean.trimmingCharacters(in: .whitespaces)
        return clean.count > 60 ? String(clean.prefix(60)) + "…" : clean
    }
}

/// 右键菜单：高频操作全部 ≤2 次点击（DESIGN.md §10.2）
struct SkillContextMenu: View {
    @EnvironmentObject private var store: AppStore
    var skill: Skill

    var body: some View {
        Button(L("复制调用语")) { store.copyToPasteboard(AppStore.callPhrase(for: skill)) }
        Button(L("查看完整说明")) {
            store.select(skill.name)
            store.readerSkill = skill
        }
        Divider()
        if skill.origin == .atlas && !skill.disabled {
            Menu("平台") {
                ForEach(AgentPlatform.allCases) { platform in
                    let enabled = skill.platforms.contains(platform.label)
                    Button {
                        store.setPlatform(skill, platform: platform, enabled: !enabled)
                    } label: {
                        if enabled {
                            Label(platform.label, systemImage: "checkmark")
                        } else {
                            Text(platform.label)
                        }
                    }
                }
            }
        }
        if skill.origin == .local && !skill.disabled {
            Button(L("收进 Skill Atlas 库")) { store.adoptLocalSkill(skill) }
        }
        if skill.origin == .atlas && skill.updateAvailable {
            Button(L("查看变更")) { store.showDiff(for: skill) }
            Button(L("更新到最新")) { store.pullSkill(skill) }
        }
        Button(store.favorites.contains(skill.name) ? L("取消收藏") : L("收藏")) {
            store.toggleFavorite(skill.name)
        }
        Button(L("在访达中显示")) { store.openFolder(skill.sourcePath) }
        if skill.origin != .ccSwitch {
            Divider()
            Button(skill.disabled ? L("恢复") : L("停用")) {
                if skill.disabled {
                    store.setSkillDisabled(skill, disabled: false)
                } else {
                    store.requestDisable(skill)
                }
            }
            Button(L("卸载…"), role: .destructive) { store.requestUninstall(skill) }
        }
    }
}

struct EmptyListView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        let favoritesEmpty = store.favoritesOnly && !store.hasActiveFilters
        VStack(spacing: Theme.Space.s8) {
            Image(systemName: favoritesEmpty ? "star" : "magnifyingglass")
                .font(.system(size: 24))
                .foregroundStyle(Theme.textTertiary)
            Text(favoritesEmpty ? L("还没有收藏") : L("没有找到匹配的 Skill"))
                .font(Theme.Fonts.rowTitle)
                .foregroundStyle(Theme.textPrimary)
            Text(favoritesEmpty ? L("把光标移到列表条目上点星标，收藏常用 Skill。") : L("试试更短的关键词，或清除筛选条件。"))
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
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(spacing: 0) {
            if let skill = store.selectedSkill {
                InspectorHead(skill: skill)
                Rectangle()
                    .fill(Color.primary.opacity(0.06))
                    .frame(height: 1)
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.s20) {
                        DetailSection(title: "用途", hint: "它能帮你做什么") {
                            Text(skill.description)
                                .font(Theme.Fonts.body)
                                .lineSpacing(2)
                                .foregroundStyle(Theme.textPrimary)
                                .textSelection(.enabled)
                        }
                        DetailSection(title: "什么时候调用") {
                            Text(skill.whenToUse)
                                .font(Theme.Fonts.body)
                                .lineSpacing(2)
                                .foregroundStyle(Theme.textPrimary)
                                .textSelection(.enabled)
                        }
                        DetailSection(title: "示例说法", hint: "可直接复制后修改") {
                            VStack(spacing: Theme.Space.s8) {
                                ForEach(skill.examplePrompts, id: \.self) { prompt in
                                    PromptChip(prompt: prompt)
                                }
                            }
                        }
                        UsageSection(skill: skill)
                        ContextCostSection(skill: skill)
                        DetailSection(title: "安装位置", hint: LF("最近更新 %@", Format.day(fromUnix: skill.updatedAt))) {
                            VStack(alignment: .leading, spacing: Theme.Space.s8) {
                                Text(skill.sourcePath)
                                    .font(Theme.Fonts.mono)
                                    .foregroundStyle(Theme.textSecondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .padding(.horizontal, Theme.Space.s8)
                                    .frame(height: 28)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .quietControl()
                                    .help(skill.sourcePath)
                                HStack(spacing: Theme.Space.s8) {
                                    Button {
                                        store.readerSkill = skill
                                    } label: {
                                        Label(L("查看完整说明"), systemImage: "doc.text")
                                            .font(Theme.Fonts.calloutEmphasis)
                                            .foregroundStyle(Theme.textPrimary)
                                            .padding(.horizontal, Theme.Space.s12)
                                            .frame(height: 28)
                                            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                                    }
                                    .buttonStyle(PressableButtonStyle())
                                    .quietControl()
                                    .help(L("在应用内阅读 SKILL.md"))
                                    openFolderButton(skill)
                                }
                            }
                        }
                        if skill.origin == .local {
                            DetailSection(title: "安装方式") {
                                HStack(alignment: .top, spacing: Theme.Space.s24) {
                                    ForEach(skill.platforms, id: \.self) { platform in
                                        HStack(spacing: Theme.Space.s8) {
                                            StatusDot(tint: Theme.healthy)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(platform == "Claude" ? "Claude Code" : platform)
                                                    .font(Theme.Fonts.calloutEmphasis)
                                                    .foregroundStyle(Theme.textPrimary)
                                                Text(L("本地安装"))
                                                    .font(Theme.Fonts.secondary)
                                                    .foregroundStyle(Theme.textSecondary)
                                            }
                                        }
                                    }
                                }
                            }
                        } else {
                            DetailSection(title: "挂载状态") {
                                HStack(alignment: .top, spacing: Theme.Space.s24) {
                                    MountLine(label: "Codex", mount: skill.mountCodex)
                                    MountLine(label: "Claude Code", mount: skill.mountClaude)
                                }
                            }
                        }
                        OutputsSection(skill: skill)
                        ChainSection(skill: skill)
                        SecuritySection(skill: skill)
                        ManageSection(skill: skill)
                        HealthNote(skill: skill)
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
                VStack(spacing: Theme.Space.s8) {
                    Image(systemName: "square.dashed")
                        .font(.system(size: 24))
                        .foregroundStyle(Theme.textTertiary)
                    Text(L("选择一个 Skill 查看详情"))
                        .font(Theme.Fonts.secondary)
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentSurface()
    }

    private func openFolderButton(_ skill: Skill) -> some View {
        Button {
            store.openFolder(skill.sourcePath)
        } label: {
            Label(L("打开目录"), systemImage: "folder")
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

private struct InspectorHead: View {
    @EnvironmentObject private var store: AppStore
    var skill: Skill

    var body: some View {
        let favorite = store.favorites.contains(skill.name)
        // 两行布局：名称行（图标 + 名称 + 收藏）与动作行（chips + 主按钮）分摊宽度，避免截断
        VStack(alignment: .leading, spacing: Theme.Space.s12) {
            HStack(spacing: Theme.Space.s12) {
                CategoryIcon(category: skill.category, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(skill.name)
                        .font(Theme.Fonts.pageTitle)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .textSelection(.enabled)
                    Text(skill.repo)
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
            PlatformToggleRow(skill: skill)
            HStack(spacing: Theme.Space.s8) {
                CategoryChip(category: skill.category)
                Text(skill.origin.label)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, Theme.Space.s8)
                    .frame(height: 20)
                    .quietControl()
                    .help(originHelp(skill.origin))
                if skill.disabled {
                    Text(L("已停用"))
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.horizontal, Theme.Space.s8)
                        .frame(height: 20)
                        .quietControl()
                        .help(L("目录已移入 .disabled/，平台不会再加载"))
                }
                Spacer()
                LaunchButton(skill: skill)
                CopyCallButton(skill: skill)
            }
        }
        .padding(.horizontal, Theme.Space.s20)
        .padding(.vertical, Theme.Space.s16)
    }

    private func originHelp(_ origin: SkillOrigin) -> String {
        switch origin {
        case .atlas: return L("由 Skill Atlas 管理，可在本页开关平台")
        case .ccSwitch: return L("由 CC Switch 统一管理（本应用只读）")
        case .local: return L("直接安装在平台技能目录。可在下方「管理」区收进本库接管")
        }
    }
}

/// 详情页「使用情况」块：调用会话数 / 最近使用 / 平台分布（来自本机会话日志索引）
private struct UsageSection: View {
    @EnvironmentObject private var store: AppStore
    var skill: Skill

    var body: some View {
        DetailSection(title: "使用情况", hint: "来自本机会话日志") {
            if store.usageIndexing {
                HStack(spacing: Theme.Space.s8) {
                    ProgressView().controlSize(.small)
                    Text(LF("正在索引使用记录… %d%%", Int(store.usageProgress * 100)))
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

private struct ContextCostSection: View {
    @EnvironmentObject private var store: AppStore
    var skill: Skill

    var body: some View {
        let report = store.doctorReport
        let entry = report.entries.first { $0.skill.name == skill.name }
        let verbose = report.verbose.first { $0.skill.name == skill.name }
        DetailSection(title: "上下文成本", hint: "估算") {
            VStack(alignment: .leading, spacing: Theme.Space.s8) {
                if let entry {
                    Text(LF("上架约 %lld token · 描述 %lld 字", entry.tokens, entry.chars))
                        .font(Theme.Fonts.callout)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                    if report.atRisk.contains(where: { $0.skill.name == skill.name }) {
                        Text(L("按当前使用频率，这份描述有被 listing budget 丢掉的风险。"))
                            .font(Theme.Fonts.secondary)
                            .foregroundStyle(Theme.warning)
                    }
                }
                if let verbose {
                    Text(L("描述超过 1 句或 200 字，建议缩短以免挤占预算。"))
                        .font(Theme.Fonts.secondary)
                        .foregroundStyle(Theme.textSecondary)
                    HStack(alignment: .top, spacing: Theme.Space.s8) {
                        Text(verbose.suggestion)
                            .font(Theme.Fonts.body)
                            .foregroundStyle(Theme.textPrimary)
                            .textSelection(.enabled)
                        CopyIconButton(text: verbose.suggestion, help: "复制缩短建议")
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
    @EnvironmentObject private var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var skill: Skill

    var body: some View {
        DetailSection(title: "管理") {
            switch skill.origin {
            case .ccSwitch:
                Text(L("在 CC Switch 中管理（本应用对尚未迁出的 CC Switch 技能保持只读）"))
                    .font(Theme.Fonts.secondary)
                    .foregroundStyle(Theme.textTertiary)
            case .atlas:
                atlasControls
            case .local:
                VStack(alignment: .leading, spacing: Theme.Space.s12) {
                    if !skill.disabled {
                        adoptControls
                    }
                    localDisableControls
                    uninstallButton
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
                    Text(L("收进 Skill Atlas 库"))
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
            .help(L("拷入 ~/.skill-atlas/skills/ 并接管挂载（原目录替换成指向本库的软链）"))
            Text(L("收编后由本应用管理：内容拷入本库，原平台目录换成指向本库的软链，平台 logo 变成可点开关。"))
                .font(Theme.Fonts.secondary)
                .foregroundStyle(Theme.textTertiary)
            // 实体在平台目录之外（软链指向开发目录等）：收编是拷贝快照，live-edit 会断开
            if SkillActions.isExternalSource(skill) {
                Text(LF("注意：此技能的实体在平台目录之外（%@）。收编会拷贝一份进库，之后编辑原目录不再对平台生效。", displaySourcePath))
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
        VStack(alignment: .leading, spacing: Theme.Space.s12) {
            Text(L("点上方 logo 开关平台挂载（建/删软链）。有新版本时列表顶部会出现更新条。"))
                .font(Theme.Fonts.secondary)
                .foregroundStyle(Theme.textTertiary)
            if skill.updateAvailable {
                HStack(spacing: Theme.Space.s8) {
                    Button {
                        store.showDiff(for: skill)
                    } label: {
                        Label(L("查看变更"), systemImage: "plus.forwardslash.minus")
                            .font(Theme.Fonts.calloutEmphasis)
                            .foregroundStyle(Theme.textPrimary)
                            .padding(.horizontal, Theme.Space.s12)
                            .frame(height: 28)
                            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                    }
                    .buttonStyle(PressableButtonStyle())
                    .quietControl()
                    .help(L("更新前先看上游改了什么（SKILL.md diff）"))
                    Button {
                        store.pullSkill(skill)
                    } label: {
                        Label(L("更新到最新"), systemImage: "arrow.down.circle")
                            .font(Theme.Fonts.calloutEmphasis)
                    }
                    .buttonStyle(.borderedProminent)
                    .help(L("git pull --ff-only，失败不强制。主入口在「更新」页。"))
                }
            }
            localDisableControls
            uninstallButton
        }
    }

    private var uninstallButton: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s8) {
            Button(L("卸载…"), role: .destructive) {
                store.requestUninstall(skill)
            }
            Text(L("先移除本应用建的软链。可选把库内目录移入废纸篓。CC Switch 原目录不删。"))
                .font(Theme.Fonts.secondary)
                .foregroundStyle(Theme.textTertiary)
        }
    }

    @ViewBuilder
    private var localDisableControls: some View {
        if skill.disabled {
            VStack(alignment: .leading, spacing: Theme.Space.s8) {
                Button {
                    withAnimation(reduceMotion ? nil : Motion.standard) {
                        store.setSkillDisabled(skill, disabled: false)
                    }
                } label: {
                    HStack(spacing: Theme.Space.s4) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text(L("恢复"))
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
                Text(skill.origin == .atlas
                    ? L("把目录从 ~/.skill-atlas/skills/.disabled/ 移回库内，并按启用位重建软链。")
                    : L("把目录从 .disabled/ 移回原位，平台恢复加载。"))
                    .font(Theme.Fonts.secondary)
                    .foregroundStyle(Theme.textTertiary)
            }
        } else {
            VStack(alignment: .leading, spacing: Theme.Space.s8) {
                Button {
                    withAnimation(reduceMotion ? nil : Motion.standard) {
                        store.requestDisable(skill)
                    }
                } label: {
                    Label(L("停用"), systemImage: "pause")
                        .font(Theme.Fonts.calloutEmphasis)
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, Theme.Space.s12)
                        .frame(height: 28)
                        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                }
                .buttonStyle(PressableButtonStyle())
                .quietControl()
                Text(skill.origin == .atlas
                    ? L("移入 ~/.skill-atlas/skills/.disabled/，并去掉平台软链；随时可恢复，不删除文件。")
                    : L("把目录移入同根的 .disabled/，平台不再加载；随时可恢复，不删除任何文件。"))
                    .font(Theme.Fonts.secondary)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }
}

/// 详情页主按钮：一键复制该技能的调用语，成功后勾选反馈
private struct CopyCallButton: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var copied = false
    var skill: Skill

    var body: some View {
        Button {
            store.copyToPasteboard(AppStore.callPhrase(for: skill))
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

private struct CategoryChip: View {
    @EnvironmentObject private var store: AppStore
    var category: String

    var body: some View {
        // 色彩收敛：分类色只保留在头部图标上，chip 用中性安静样式
        Button {
            store.jumpToCategory(category)
        } label: {
            Text(L(category))
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, Theme.Space.s8)
                .frame(height: 20)
                .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .quietControl()
        .help(L("查看该分类的全部技能"))
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
    @EnvironmentObject private var store: AppStore
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

/// 详情页健康提醒：只在真有问题时出现（健康时不占版面），入口指向体检页。
private struct HealthNote: View {
    @EnvironmentObject private var store: AppStore
    var skill: Skill

    var body: some View {
        if !skill.problems.isEmpty {
            HStack(alignment: .top, spacing: Theme.Space.s8) {
                Image(systemName: skill.health == .error ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(skill.health.tint)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: Theme.Space.s4) {
                    Text(LF("%@ · %lld 项需处理", skill.health.label, skill.problems.count))
                        .font(Theme.Fonts.rowTitle)
                        .foregroundStyle(Theme.textPrimary)
                    Text(skill.problems.joined(separator: "；"))
                        .font(Theme.Fonts.secondary)
                        .lineSpacing(2)
                        .foregroundStyle(Theme.textSecondary)
                    Button {
                        store.nav = .doctor
                    } label: {
                        Text(L("到体检页查看全部问题"))
                            .font(Theme.Fonts.secondaryEmphasis)
                            .foregroundStyle(Theme.accent)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Theme.Space.s12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                    .fill(skill.health.tint.opacity(0.08))
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                    .strokeBorder(skill.health.tint.opacity(0.16), lineWidth: 0.5)
            }
        }
    }
}


// MARK: - 发起会话（二期 F2）

/// 详情头的发起按钮：弹出主题输入，自动建体裁目录并开 Terminal 会话
private struct LaunchButton: View {
    @EnvironmentObject private var store: AppStore
    @State private var presented = false
    var skill: Skill

    var body: some View {
        Button {
            presented = true
        } label: {
            HStack(spacing: Theme.Space.s4) {
                Image(systemName: "play.fill")
                    .font(.system(size: 10, weight: .semibold))
                Text("发起会话")
                    .font(Theme.Fonts.calloutEmphasis)
            }
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, Theme.Space.s12)
            .frame(height: 28)
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .quietControl()
        .help(SkillLauncher.genre(for: skill).map {
            LF("自动建 projects/%@/日期_主题/ 目录，并在该目录开 Terminal 会话", $0)
        } ?? L("在工作根目录开 Terminal 会话并预填调用语"))
        .popover(isPresented: $presented, arrowEdge: .bottom) {
            LaunchPopover(skill: skill, presented: $presented)
        }
    }
}

private struct LaunchPopover: View {
    @EnvironmentObject private var store: AppStore
    @Binding var presented: Bool
    @State private var topic = ""
    @State private var errorText: String?
    @FocusState private var topicFocused: Bool
    var skill: Skill

    init(skill: Skill, presented: Binding<Bool>) {
        self.skill = skill
        self._presented = presented
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s12) {
            HStack(spacing: Theme.Space.s8) {
                CategoryIcon(category: skill.category, size: 24, style: .quiet)
                Text(skill.name)
                    .font(Theme.Fonts.rowTitle)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
            }
            TextField(L("主题（用于目录名和调用语，可留空）"), text: $topic)
                .textFieldStyle(.plain)
                .font(Theme.Fonts.body)
                .padding(.horizontal, Theme.Space.s8 + 2)
                .frame(height: 30)
                .quietControl()
                .focused($topicFocused)
                .onSubmit { launch() }
            let recents = SkillLauncher.recentTopics(for: skill)
            if !recents.isEmpty {
                HStack(spacing: Theme.Space.s4) {
                    ForEach(recents.prefix(3), id: \.self) { recent in
                        Button {
                            topic = recent
                        } label: {
                            Text(recent)
                                .font(Theme.Fonts.caption)
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                                .padding(.horizontal, Theme.Space.s8)
                                .frame(height: 20)
                                .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .quietControl()
                    }
                }
            }
            Text(directoryPreview)
                .font(Theme.Fonts.mono)
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
            if let errorText {
                Text(errorText)
                    .font(Theme.Fonts.secondary)
                    .foregroundStyle(Theme.error)
            }
            HStack {
                Button {
                    store.copyToPasteboard(SkillLauncher.command(for: skill, topic: topic))
                    presented = false
                } label: {
                    Text("仅复制命令")
                        .font(Theme.Fonts.calloutEmphasis)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, Theme.Space.s12)
                        .frame(height: 26)
                        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                }
                .buttonStyle(PressableButtonStyle())
                .quietControl()
                Spacer()
                Button {
                    launch()
                } label: {
                    HStack(spacing: Theme.Space.s4) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10, weight: .semibold))
                        Text("发起")
                            .font(Theme.Fonts.calloutEmphasis)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, Theme.Space.s12 + 2)
                    .frame(height: 26)
                    .contentShape(Capsule())
                }
                .buttonStyle(PressableButtonStyle())
                .accentGlass(Capsule(style: .continuous))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.Space.s16)
        .frame(width: 340)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { topicFocused = true }
        }
    }

    private var directoryPreview: String {
        SkillLauncher.sessionDirectory(for: skill, topic: topic).path
            .replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    private func launch() {
        do {
            _ = try SkillLauncher.launch(skill: skill, topic: topic)
            presented = false
        } catch {
            errorText = error.localizedDescription
        }
    }
}

// MARK: - 详情安全区块（二期 F3 复扫结果）

private struct SecuritySection: View {
    @EnvironmentObject private var store: AppStore
    var skill: Skill

    var body: some View {
        if let findings = store.securityDisplay[skill.directory], !findings.isEmpty {
            DetailSection(title: "安全扫描", hint: "静态规则，命中不等于恶意，逐条核对原文") {
                VStack(alignment: .leading, spacing: Theme.Space.s8) {
                    ForEach(findings.prefix(8)) { finding in
                        FindingRow(finding: finding)
                    }
                }
                .padding(Theme.Space.s12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .quietControl(cornerRadius: Theme.Radius.tile)
            }
        }
    }
}


// MARK: - 最近产出（二期 F4：产出物回链）

private struct OutputsSection: View {
    @EnvironmentObject private var store: AppStore
    @State private var records: [OutputRecord] = []
    var skill: Skill

    var body: some View {
        Group {
            if SkillLauncher.genre(for: skill) != nil {
                DetailSection(title: "最近产出", hint: "来自 projects 目录，点击打开") {
                    if records.isEmpty {
                        Text("还没有产出记录。用「发起会话」跑一单，目录会自动合规。")
                            .font(Theme.Fonts.secondary)
                            .foregroundStyle(Theme.textTertiary)
                    } else {
                        VStack(spacing: 2) {
                            ForEach(records) { record in
                                OutputRow(record: record, skill: skill)
                            }
                        }
                    }
                }
            }
        }
        .onAppear { records = OutputLinker.recentOutputs(for: skill) }
        .onChange(of: skill.name) { _, _ in records = OutputLinker.recentOutputs(for: skill) }
    }
}

private struct OutputRow: View {
    @EnvironmentObject private var store: AppStore
    @State private var hovering = false
    var record: OutputRecord
    var skill: Skill

    var body: some View {
        HStack(spacing: Theme.Space.s8) {
            Image(systemName: "folder.fill")
                .font(.system(size: 11))
                .foregroundStyle(Theme.accent.opacity(0.7))
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(record.topic)
                    .font(Theme.Fonts.callout)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(record.latestDeliverable ?? LF("%lld 个文件", record.fileCount))
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: Theme.Space.s4)
            if hovering {
                Button {
                    _ = try? SkillLauncher.launch(skill: skill, topic: record.topic)
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L("用同一主题重跑一次"))
            }
            Text(displayDate)
                .font(Theme.Fonts.caption)
                .monospacedDigit()
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.horizontal, Theme.Space.s8)
        .padding(.vertical, Theme.Space.s4 + 1)
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .fill(hovering ? Color.primary.opacity(0.04) : Color.clear)
        }
        .onHover { hovering = $0 }
        .onTapGesture { OutputLinker.open(record) }
        .help(record.directory.path)
    }

    private var displayDate: String {
        let text = record.dateText
        guard text.count == 8 else { return text }
        return "\(text.dropFirst(4).prefix(2))/\(text.suffix(2))"
    }
}

// MARK: - 生产链路（二期 F6：上游/下游/依赖）

private struct ChainSection: View {
    @EnvironmentObject private var store: AppStore
    var skill: Skill

    var body: some View {
        if ProductionChain.hasChain(skill.directory) {
            DetailSection(title: "生产链路", hint: "每跳有人工审校，不自动编排") {
                VStack(alignment: .leading, spacing: Theme.Space.s8) {
                    chainRow(label: L("上游"), directories: ProductionChain.upstream(of: skill.directory))
                    chainRow(label: L("下游"), directories: ProductionChain.downstream(of: skill.directory))
                    chainRow(label: L("依赖"), directories: ProductionChain.dependencies(of: skill.directory))
                    chainRow(label: L("被依赖"), directories: ProductionChain.dependents(of: skill.directory))
                }
            }
        }
    }

    @ViewBuilder
    private func chainRow(label: String, directories: [String]) -> some View {
        if !directories.isEmpty {
            HStack(alignment: .top, spacing: Theme.Space.s8) {
                Text(label)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 44, alignment: .leading)
                    .padding(.top, 3)
                HStack(spacing: Theme.Space.s4) {
                    ForEach(directories, id: \.self) { directory in
                        let target = store.skills.first { $0.directory == directory }
                        Button {
                            if let target { store.select(target.name) }
                        } label: {
                            HStack(spacing: Theme.Space.s4) {
                                if let target {
                                    CategoryIcon(category: target.category, size: 16, style: .quiet)
                                }
                                Text(directory)
                                    .font(Theme.Fonts.caption)
                                    .foregroundStyle(target == nil ? Theme.textTertiary : Theme.textPrimary)
                            }
                            .padding(.horizontal, Theme.Space.s8)
                            .frame(height: 22)
                            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .quietControl()
                        .disabled(target == nil)
                        .help(target == nil ? L("未安装") : LF("查看 %@", directory))
                    }
                }
            }
        }
    }
}


// MARK: - 更新 diff 预览（三期 1：技能文本变更 = 行为变更，先看再更）

struct DiffSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    var skill: Skill

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1)
            content.padding(Theme.Space.s20)
        }
        .frame(width: 640, height: 520)
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
                Text(skill.name)
                    .font(Theme.Fonts.panelTitle)
                    .foregroundStyle(Theme.textPrimary)
                Text("上游变更预览 · 本地改动不会被覆盖（快进合并）")
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
            if let diff = store.diffContent {
                if !diff.stat.isEmpty {
                    Text(diff.stat)
                        .font(Theme.Fonts.mono)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(6)
                        .padding(Theme.Space.s8 + 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .quietControl(cornerRadius: Theme.Radius.control)
                }
                if diff.diff.isEmpty {
                    emptyDiff
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(diff.diff.split(separator: "\n", omittingEmptySubsequences: false).enumerated()), id: \.offset) { _, line in
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
            } else {
                HStack(spacing: Theme.Space.s8) {
                    ProgressView().controlSize(.small)
                    Text("正在对照上游…")
                        .font(Theme.Fonts.secondary)
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack {
                Spacer()
                Button {
                    store.pullSkill(skill)
                    dismiss()
                } label: {
                    HStack(spacing: Theme.Space.s4) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 11, weight: .semibold))
                        Text("更新到最新")
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
            }
        }
    }

    private var emptyDiff: some View {
        VStack(spacing: Theme.Space.s8) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 22))
                .foregroundStyle(Theme.textTertiary)
            Text("上游没有文本变更（可能只是提交记录前移）")
                .font(Theme.Fonts.secondary)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
