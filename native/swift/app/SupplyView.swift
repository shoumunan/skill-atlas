import SwiftUI
#if SWIFT_PACKAGE
import AtlasCore
#endif

// MARK: - 供给（v15 一级页，WP-S）
//
// 回答「哪个 AI、哪个项目带哪些技能进场，花多少 token」。签名布局：左范围轨
// ScopeRail + 右档位板。档位（三档）仅 Claude 有；其他平台是挂载二态；项目范围
// 按 ADR-13 只做登记与场景包绑定。写 skillOverrides 一律经 SupplyWriter（ADR-11），
// 场景包应用/解绑复用 AppStore 既有确认流程与回执文案。

struct SupplyPage: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var supply = SupplyStore()

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.s12) {
            ScopeRail(supply: supply)
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.s16) {
                    if let receipt = supply.receipt {
                        ReceiptLine(text: receipt.text, failed: receipt.failed) {
                            supply.receipt = nil
                        }
                        .receiptTransition(reduceMotion: reduceMotion)
                    }
                    switch supply.scope {
                    case .platform(let platform):
                        if platform == .claude {
                            ClaudeScopeView(supply: supply)
                        } else {
                            PlatformScopeView(platform: platform)
                        }
                    case .project(let path):
                        ProjectScopeView(supply: supply, path: path)
                    }
                }
                .padding(Theme.Space.s20)
                .animation(reduceMotion ? nil : Motion.standard, value: supply.receipt)
                // 可读宽度上限：宽窗不拉成仪表盘（DESIGN ⑤），
                // 否则档位选择器会被甩到离技能名一千多点远
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .panelScroll()
            .contentSurface()
        }
        .onAppear {
            store.loadProfiles()
            supply.reloadOverrides()
            supply.normalizeScope(appStore: store)
        }
        // 体检异步重算落地后：补回执数字，并让三档分组跟着新的 overrides 重排。
        // 场景包 / 瘦身草案走的是全局确认 sheet，回到本页时也靠这条刷新。
        .onChange(of: store.doctorReport.totalTokens) { _, _ in
            supply.reloadOverrides()
            supply.settleReceiptIfNeeded(appStore: store)
        }
        .onChange(of: store.profiles.activeProfileID) { _, _ in
            supply.reloadOverrides()
        }
        .sheet(isPresented: Binding(
            get: { supply.slimPresented },
            set: { supply.slimPresented = $0; if !$0 { supply.reloadOverrides() } }
        )) {
            SlimDraftSheet()
        }
    }
}

// MARK: - 左范围轨

private struct ScopeRail: View {
    @Environment(AppStore.self) private var store
    @Bindable var supply: SupplyStore

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s4) {
            railHeader(L("平台"))
            ForEach(store.visiblePlatforms) { platform in
                platformRow(platform)
            }

            railHeader(L("项目"))
                .padding(.top, Theme.Space.s12)
            let projects = supply.projects(appStore: store)
            if projects.isEmpty {
                Text(L("还没有登记项目"))
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, Theme.Space.s8 + 2)
                    .padding(.vertical, Theme.Space.s4)
            } else {
                ForEach(projects) { project in
                    projectRow(project)
                }
            }
            Button {
                supply.addProject(appStore: store)
            } label: {
                HStack(spacing: Theme.Space.s4 + 1) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                    Text(L("添加项目…"))
                        .font(Theme.Fonts.callout)
                }
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, Theme.Space.s8 + 2)
                .frame(height: 28)
                .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            }
            .buttonStyle(PressableButtonStyle())
            .help(L("选择一个项目目录，把场景包钉在它的会话上"))

            Spacer(minLength: 0)
        }
        .padding(Theme.Space.s8)
        .frame(width: 210)
        .frame(maxHeight: .infinity, alignment: .top)
        .contentSurface()
    }

    private func railHeader(_ text: String) -> some View {
        Text(text)
            .font(Theme.Fonts.caption)
            .foregroundStyle(Theme.textTertiary)
            .padding(.horizontal, Theme.Space.s8 + 2)
            .padding(.bottom, 2)
            .accessibilityAddTraits(.isHeader)
    }

    private func platformRow(_ platform: AgentPlatform) -> some View {
        let selected = supply.scope == .platform(platform)
        let isClaude = platform == .claude
        let tokens = store.doctorReport.totalTokens
        return scopeButton(selected: selected) {
            supply.scope = .platform(platform)
        } label: {
            HStack(spacing: Theme.Space.s8) {
                PlatformLogo(platform: platform, size: 16, lit: true)
                Text(platform.displayName)
                    .font(selected ? Theme.Fonts.calloutEmphasis : Theme.Fonts.callout)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if isClaude, tokens > 0 {
                    Text(LF("%d tok", tokens))
                        .font(Theme.Fonts.caption)
                        .monospacedDigit()
                        .foregroundStyle(tokens > 10_000 ? Theme.warning : Theme.textTertiary)
                }
            }
        }
        .help(isClaude
            ? L("Claude 供给分三档，右侧可逐技能改档")
            : L("该平台按挂载供给，档位仅对 Claude 生效"))
    }

    private func projectRow(_ project: SupplyProject) -> some View {
        let selected = supply.scope == .project(project.path)
        let bound = store.profiles.bindings.contains { $0.directory == project.path }
        return scopeButton(selected: selected) {
            supply.scope = .project(project.path)
        } label: {
            HStack(spacing: Theme.Space.s8) {
                Image(systemName: "folder")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 16)
                Text(URL(fileURLWithPath: project.path).lastPathComponent)
                    .font(selected ? Theme.Fonts.calloutEmphasis : Theme.Fonts.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                if bound {
                    StatusDot(tint: Theme.healthy)
                }
            }
        }
        .help(project.path)
    }

    private func scopeButton(
        selected: Bool,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> some View
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.control + 1, style: .continuous)
        return Button(action: action) {
            label()
                .foregroundStyle(selected ? Theme.accent : Theme.textSecondary)
                .padding(.horizontal, Theme.Space.s8 + 2)
                .frame(height: 30)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    if selected {
                        shape.fill(Theme.accent.opacity(0.13))
                    }
                }
                .contentShape(shape)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Claude 档位板

private struct ClaudeScopeView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var supply: SupplyStore

    var body: some View {
        // 一次分桶：原先是「排序一次 + 每档全量过滤一次」，三档就要扫三遍全库
        let buckets = tierBuckets
        VStack(alignment: .leading, spacing: Theme.Space.s16) {
            billHeader
            presetRow
            tierGroup(L("完整挂载"), members: buckets[.core] ?? [],
                      hint: L("描述进每个会话的自动清单"))
            tierGroup(L("仅用户可调"), members: buckets[.userInvocable] ?? [],
                      hint: L("不进自动清单，仍可用 /名字 调用"))
            tierGroup(L("不挂载"), members: buckets[.off] ?? [],
                      hint: L("从 Claude 清单里完全拿掉"))
        }
    }

    private var tierBuckets: [SlimTier: [Skill]] {
        let claudeLabel = AgentPlatform.claude.label
        let sorted = store.skills
            .filter { !$0.disabled && $0.platforms.contains(claudeLabel) }
            .sorted { (store.usage[$0.directory]?.total ?? 0) > (store.usage[$1.directory]?.total ?? 0) }
        return Dictionary(grouping: sorted) { supply.tier(for: $0) }
    }

    private var billHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Theme.Space.s8) {
                    Text(LF("%d tok", store.doctorReport.totalTokens))
                        .font(Theme.Fonts.panelTitle)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(reduceMotion ? nil : Motion.standard, value: store.doctorReport.totalTokens)
                        .foregroundStyle(store.doctorReport.totalTokens > 10_000 ? Theme.warning : Theme.textPrimary)
                    Text(L("估算"))
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.horizontal, Theme.Space.s4 + 1)
                        .frame(height: 16)
                        .quietControl()
                }
                Text(L("每个 Claude 会话开场读技能清单的成本。档位只对 Claude Code 生效。"))
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            AtlasPrimaryButton(title: L("瘦身草案…")) { supply.slimPresented = true }
                .help(L("按使用次数自动分档，逐条确认后应用"))
        }
    }

    private var presetRow: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s8) {
            Text(L("场景包"))
                .font(Theme.Fonts.secondaryEmphasis)
                .foregroundStyle(Theme.textSecondary)
            HStack(spacing: Theme.Space.s8) {
                PresetChip(
                    title: L("全部技能"),
                    applied: store.profiles.activeProfileID == nil
                ) {
                    store.revertDefaultProfile()
                }
                ForEach(store.profiles.profiles) { profile in
                    PresetChip(
                        title: profile.name,
                        applied: store.profiles.activeProfileID == profile.id
                    ) {
                        store.requestProfileApply(profile, directory: nil)
                    }
                }
                Button {
                    store.loadProfiles()
                    store.profileSheetPresented = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 26, height: 26)
                        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                }
                .buttonStyle(PressableButtonStyle())
                .quietControl()
                .help(L("管理场景…"))
            }
        }
    }

    private func tierGroup(_ title: String, members: [Skill], hint: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s8) {
            HStack(spacing: Theme.Space.s8) {
                Text(title)
                    .font(Theme.Fonts.secondaryEmphasis)
                    .foregroundStyle(Theme.textSecondary)
                Text("\(members.count)")
                    .font(Theme.Fonts.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
                Text(hint)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            if members.isEmpty {
                Text(L("这一档暂时没有技能"))
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.vertical, Theme.Space.s4)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(members.enumerated()), id: \.element.id) { index, skill in
                        if index > 0 {
                            Rectangle()
                                .fill(Color.primary.opacity(0.06))
                                .frame(height: 1)
                                .padding(.leading, Theme.Space.s12)
                        }
                        TierRow(supply: supply, skill: skill)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
                .quietControl(cornerRadius: Theme.Radius.tile)
            }
        }
    }
}

/// 场景包标签（v15 PresetChip：未应用 / 已应用 ✓）
private struct PresetChip: View {
    var title: String
    var applied: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.s4) {
                if applied {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                }
                Text(title)
                    .font(applied ? Theme.Fonts.calloutEmphasis : Theme.Fonts.callout)
                    .lineLimit(1)
            }
            .foregroundStyle(applied ? Theme.accent : Theme.textSecondary)
            .padding(.horizontal, Theme.Space.s12)
            .frame(height: 26)
            .background {
                Capsule(style: .continuous)
                    .fill(applied ? Theme.accent.opacity(0.13) : Color.primary.opacity(0.06))
            }
            .contentShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .help(applied ? L("当前生效") : LF("应用「%@」", title))
    }
}

/// 单技能档位行（v15 TierSegment 的行级宿主；meta-skill 固定不可改档）
private struct TierRow: View {
    @Environment(AppStore.self) private var store
    @Bindable var supply: SupplyStore
    var skill: Skill

    var body: some View {
        let isMeta = skill.directory == MetaSkill.directory
        HStack(spacing: Theme.Space.s12) {
            CategoryIcon(category: skill.category, size: 24, style: .quiet)
            VStack(alignment: .leading, spacing: 1) {
                Text(skill.name)
                    .font(Theme.Fonts.rowTitle)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(LF("%d 次会话", store.usage[skill.directory]?.total ?? 0))
                    .font(Theme.Fonts.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer(minLength: Theme.Space.s8)
            if isMeta {
                HStack(spacing: Theme.Space.s4) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9))
                    Text(L("固定"))
                        .font(Theme.Fonts.caption)
                }
                .foregroundStyle(Theme.textTertiary)
                .help(L("由本应用生成并挂到所有平台，不能单独停用。"))
            } else {
                TierSegment(
                    tier: supply.tier(for: skill),
                    accessibilityName: skill.name
                ) { supply.applyTier($0, to: skill, appStore: store) }
            }
        }
        .padding(.horizontal, Theme.Space.s12)
        .frame(height: 44)
        .rowHover()
    }
}

// MARK: - 非 Claude 平台（挂载二态）

private struct PlatformScopeView: View {
    @Environment(AppStore.self) private var store
    var platform: AgentPlatform

    var body: some View {
        let mounted = store.skills.filter { !$0.disabled && $0.platforms.contains(platform.label) }
        let unmounted = store.skills.filter {
            !$0.disabled && $0.origin == .atlas && !$0.platforms.contains(platform.label)
        }
        VStack(alignment: .leading, spacing: Theme.Space.s16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(LF("已挂载 %d 个", mounted.count))
                    .font(Theme.Fonts.panelTitle)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                Text(L("该平台按挂载供给，档位仅对 Claude 生效"))
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            mountGroup(L("已挂载"), skills: mounted, platform: platform)
            mountGroup(L("未挂载"), skills: unmounted, platform: platform)
        }
    }

    private func mountGroup(_ title: String, skills: [Skill], platform: AgentPlatform) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s8) {
            HStack(spacing: Theme.Space.s8) {
                Text(title)
                    .font(Theme.Fonts.secondaryEmphasis)
                    .foregroundStyle(Theme.textSecondary)
                Text("\(skills.count)")
                    .font(Theme.Fonts.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
            }
            if skills.isEmpty {
                Text(L("这一组暂时没有技能"))
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.vertical, Theme.Space.s4)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(skills.enumerated()), id: \.element.id) { index, skill in
                        if index > 0 {
                            Rectangle()
                                .fill(Color.primary.opacity(0.06))
                                .frame(height: 1)
                                .padding(.leading, Theme.Space.s12)
                        }
                        MountRow(skill: skill, platform: platform)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
                .quietControl(cornerRadius: Theme.Radius.tile)
            }
        }
    }
}

private struct MountRow: View {
    @Environment(AppStore.self) private var store
    var skill: Skill
    var platform: AgentPlatform

    var body: some View {
        let enabled = skill.platforms.contains(platform.label)
        let toggleable = skill.origin == .atlas && skill.directory != MetaSkill.directory
        HStack(spacing: Theme.Space.s12) {
            CategoryIcon(category: skill.category, size: 24, style: .quiet)
            Text(skill.name)
                .font(Theme.Fonts.rowTitle)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: Theme.Space.s8)
            if toggleable {
                Toggle("", isOn: Binding(
                    get: { enabled },
                    set: { store.setPlatform(skill, platform: platform, enabled: $0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .help(enabled
                    ? LF("停止同步到 %@", platform.displayName)
                    : LF("同步到 %@", platform.displayName))
                .accessibilityLabel(LF("把 %@ 挂到 %@", skill.name, platform.displayName))
            } else {
                HStack(spacing: Theme.Space.s4) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9))
                    Text(skill.directory == MetaSkill.directory ? L("固定") : skill.origin.label)
                        .font(Theme.Fonts.caption)
                }
                .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.horizontal, Theme.Space.s12)
        .frame(height: 44)
        .rowHover()
    }
}

// MARK: - 项目范围（登记 + 场景包绑定）

private struct ProjectScopeView: View {
    @Environment(AppStore.self) private var store
    @Bindable var supply: SupplyStore
    var path: String

    var body: some View {
        let binding = store.profiles.bindings.first { $0.directory == path }
        let boundProfile = binding.flatMap { b in
            store.profiles.profiles.first { $0.id == b.profileID }
        }
        VStack(alignment: .leading, spacing: Theme.Space.s16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(URL(fileURLWithPath: path).lastPathComponent)
                    .font(Theme.Fonts.panelTitle)
                    .foregroundStyle(Theme.textPrimary)
                Text(path.replacingOccurrences(of: AtlasPaths.home.path, with: "~"))
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            VStack(alignment: .leading, spacing: Theme.Space.s8) {
                if let binding, let boundProfile {
                    HStack(spacing: Theme.Space.s8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.healthy)
                        Text(LF("已绑定「%@」：%d 个技能不进该目录会话的自动清单", boundProfile.name, binding.appliedKeys.count))
                            .font(Theme.Fonts.secondary)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text(L("未绑定场景包。该目录的会话用全局默认清单。"))
                        .font(Theme.Fonts.secondary)
                        .foregroundStyle(Theme.textSecondary)
                }

                HStack(spacing: Theme.Space.s8) {
                    Menu {
                        ForEach(store.profiles.profiles) { profile in
                            Button(profile.name) {
                                store.requestProfileApply(profile, directory: URL(fileURLWithPath: path))
                            }
                        }
                        if store.profiles.profiles.isEmpty {
                            Button(L("先去「管理场景…」建一个")) {
                                store.profileSheetPresented = true
                            }
                        }
                    } label: {
                        Text(L("套用场景包…"))
                            .font(Theme.Fonts.calloutEmphasis)
                            .foregroundStyle(Theme.textPrimary)
                            .padding(.horizontal, Theme.Space.s12)
                            .frame(height: 28)
                            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .quietControl()
                    .help(L("把一组技能一次性钉到这个项目的会话上"))

                    if let binding {
                        Button(L("解除绑定")) {
                            store.unbindDirectory(binding)
                        }
                        .buttonStyle(PressableButtonStyle())
                        .font(Theme.Fonts.callout)
                        .foregroundStyle(Theme.textSecondary)
                    }

                    Button(L("在访达中显示")) {
                        store.openFolder(path)
                    }
                    .buttonStyle(PressableButtonStyle())
                    .font(Theme.Fonts.callout)
                    .foregroundStyle(Theme.textSecondary)

                    Spacer()

                    Button(L("移除登记")) {
                        supply.removeProject(path, appStore: store)
                    }
                    .buttonStyle(PressableButtonStyle())
                    .font(Theme.Fonts.callout)
                    .foregroundStyle(Theme.textTertiary)
                    .help(L("只从左侧列表移除；已绑定的配置要先解除绑定"))
                }
            }
            .padding(Theme.Space.s12)
            .quietControl(cornerRadius: Theme.Radius.tile)

            Text(L("项目供给写在 <目录>/.claude/settings.local.json，App 关掉照样生效。"))
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
