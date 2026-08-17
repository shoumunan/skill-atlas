import SwiftUI

// MARK: - 体检页（v7 重排）
//
// 所有健康信号的唯一入口（列表不再放小黄灯）。结构：
//   预算带（全宽）
//   左列（弹性）：需要修复 / 描述体检（丢弃风险 + 截断 + 缩短建议）
//   右列（400）：长期未用 / 触发词重叠
// 四个面板同一套头部（彩色图标章 + 标题 + 计数 + 副文案），行样式统一。

struct DoctorPage: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let report = store.doctorReport
        VStack(spacing: Theme.Space.s12) {
            BudgetBand(report: report)
            // 左右两列均分（固定 400 右列在宽窗口下会失衡）
            HStack(alignment: .top, spacing: Theme.Space.s12) {
                VStack(spacing: Theme.Space.s12) {
                    IssuesPanel()
                    DescriptionPanel(report: report)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                VStack(spacing: Theme.Space.s12) {
                    StalePanel(report: report)
                    OverlapPanel()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity)
        }
    }
}

// MARK: - 统一面板骨架

/// 体检面板统一头部：彩色图标章 + 标题 + 计数 + 一行副文案（+ 右上角注）
private struct DoctorPanel<Content: View>: View {
    var symbol: String
    var tint: Color
    var title: String
    var count: Int
    var subtitle: String
    var note: String?
    var noteHelp: String?
    @ViewBuilder var content: Content

    init(
        symbol: String, tint: Color, title: String, count: Int,
        subtitle: String, note: String? = nil, noteHelp: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.symbol = symbol
        self.tint = tint
        self.title = title
        self.count = count
        self.subtitle = subtitle
        self.note = note
        self.noteHelp = noteHelp
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s12) {
            HStack(alignment: .center, spacing: Theme.Space.s8 + 2) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(count > 0 ? tint : Theme.textTertiary)
                    .frame(width: 22, height: 22)
                    .background {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill((count > 0 ? tint : Color.primary).opacity(count > 0 ? 0.12 : 0.05))
                    }
                Text(L(title))
                    .font(Theme.Fonts.panelTitle)
                    .foregroundStyle(Theme.textPrimary)
                if count > 0 {
                    Text("\(count)")
                        .font(Theme.Fonts.caption)
                        .monospacedDigit()
                        .foregroundStyle(tint)
                        .padding(.horizontal, Theme.Space.s4 + 2)
                        .frame(minWidth: 18)
                        .frame(height: 17)
                        .background(Capsule().fill(tint.opacity(0.12)))
                }
                Spacer()
                if let note {
                    Text(L(note))
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.textTertiary)
                        .help(L(noteHelp ?? note))
                }
            }
            Text(L(subtitle))
                .font(Theme.Fonts.secondary)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(2)
            content
        }
        .padding(Theme.Space.s20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentSurface()
    }
}

// MARK: - 预算带

private struct BudgetBand: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var report: DoctorReport

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.s20) {
            VStack(alignment: .leading, spacing: Theme.Space.s8) {
                HStack(spacing: Theme.Space.s8) {
                    Text(L("技能清单的上下文预算"))
                        .font(Theme.Fonts.panelTitle)
                        .foregroundStyle(Theme.textPrimary)
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                        .help(L("Claude Code 启动时会把所有技能的名称和描述注入上下文，预算约为窗口的 1%。超额后，最少使用的技能描述会被静默丢弃。技能还在，但模型看不到它能做什么，触发就会失灵。数字为估算（CJK×0.7 + 其他÷4 + 条目开销）。"))
                    Spacer()
                    windowPicker
                }

                // 占用条：预算内用强调色，超出部分红色
                GeometryReader { proxy in
                    let fraction = min(1, report.usageFraction)
                    let overFraction = max(0, min(1, report.usageFraction - 1))
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.06))
                        Capsule()
                            .fill(report.overBudget ? Theme.warning : Theme.accent)
                            .frame(width: max(6, proxy.size.width * fraction / max(1, report.usageFraction)))
                        if report.overBudget {
                            Capsule()
                                .fill(Theme.error)
                                .frame(width: max(4, proxy.size.width * overFraction / report.usageFraction))
                                .offset(x: proxy.size.width * (1 - overFraction / report.usageFraction))
                        }
                    }
                }
                .frame(height: 8)
                .animation(reduceMotion ? nil : Motion.standard, value: report.totalTokens)

                Text(report.overBudget
                    ? LF("估算占用 ~%d token，超出预算 %d。按你的使用频率模拟，%d 个技能的描述会被丢弃。", report.totalTokens, report.totalTokens - report.budgetTokens, report.atRisk.count)
                    : LF("估算占用 ~%d / %d token，余量 %d。", report.totalTokens, report.budgetTokens, report.budgetTokens - report.totalTokens))
                    .font(Theme.Fonts.secondary)
                    .monospacedDigit()
                    .lineSpacing(2)
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            hairline
            // 官方口径：清单永远保留每个技能的名字，超预算时丢的是描述。
            // 旧文案「约 40 个 × 260 字开始截断」既无官方来源，也与本页的 token
            // 预算算法不自洽（200k 窗口 ≈ 2000 token，一条 260 字中文描述 ≈ 197
            // token，约 10 条就满，不是 40 条），已删。
            metric(number: report.entries.count, label: L("上架技能"), note: L("名字始终在清单里"))
            hairline
            metric(number: report.atRisk.count, label: L("描述丢弃风险"), note: report.overBudget ? L("最少用的先被丢") : L("预算内，无风险"), tint: report.atRisk.isEmpty ? nil : Theme.warning)
            hairline
            metric(number: report.reclaimableTokens, label: L("可回收 token"), note: L("停用长期未用即可省出"), tint: report.reclaimableTokens > 0 ? Theme.healthy : nil)
        }
        .padding(.horizontal, Theme.Space.s20)
        .padding(.vertical, Theme.Space.s16)
        .frame(maxWidth: .infinity)
        .contentSurface()
    }

    private var windowPicker: some View {
        HStack(spacing: 2) {
            windowTab("200k", tokens: 200_000)
            windowTab("1M", tokens: 1_000_000)
        }
        .padding(2)
        .quietControl()
        .help(L("按你常用模型的上下文窗口估算预算（窗口的 1%）"))
    }

    private func windowTab(_ title: String, tokens: Int) -> some View {
        let active = store.contextWindowTokens == tokens
        return Button {
            store.contextWindowTokens = tokens
        } label: {
            Text(title)
                .font(active ? Theme.Fonts.caption : .system(size: 10))
                .monospacedDigit()
                .foregroundStyle(active ? Theme.textPrimary : Theme.textSecondary)
                .padding(.horizontal, Theme.Space.s8)
                .frame(height: 18)
                .background {
                    if active {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(.background)
                            .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func metric(number: Int, label: String, note: String, tint: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s4) {
            Text("\(number)")
                .font(Theme.Fonts.metric)
                .foregroundStyle(tint ?? Theme.textPrimary)
                .contentTransition(.numericText())
            Text(L(label))
                .font(Theme.Fonts.secondaryEmphasis)
                .foregroundStyle(Theme.textSecondary)
            Text(L(note))
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(width: 132, alignment: .leading)
    }

    private var hairline: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.06))
            .frame(width: 1, height: 56)
    }
}

// MARK: - 需要修复（挂载与文件问题，从技能列表收拢过来的唯一入口）

private struct IssuesPanel: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let issues = store.skills.filter { $0.health != .healthy && !$0.disabled }
            .sorted {
                let rank: [Health: Int] = [.error: 0, .warning: 1]
                if $0.health != $1.health { return (rank[$0.health] ?? 2) < (rank[$1.health] ?? 2) }
                return $0.name.lowercased() < $1.name.lowercased()
            }
        let security = store.securityDisplay
            .compactMap { directory, findings -> (Skill, [SecurityFinding])? in
                guard let skill = store.skills.first(where: { $0.directory == directory }) else { return nil }
                return (skill, findings)
            }
            .sorted { lhs, rhs in
                let lc = lhs.1.filter { $0.severity == .critical }.count
                let rc = rhs.1.filter { $0.severity == .critical }.count
                return lc != rc ? lc > rc : lhs.0.name.lowercased() < rhs.0.name.lowercased()
            }
        DoctorPanel(
            symbol: "wrench.and.screwdriver.fill",
            tint: Theme.error,
            title: "需要修复",
            count: issues.count + security.count,
            subtitle: issues.isEmpty
                ? L("挂载与文件检查全部通过。")
                : L("挂载或文件有问题，技能可能加载不出来。点击行去详情处理。"),
            note: store.data?.summary.migrated == true ? L("Skill Atlas 管理") : L("只读检查"),
            noteHelp: store.data?.summary.migrated == true
                ? L("技能由 Skill Atlas 库管理；CC Switch 原数据未做任何修改，可随时在菜单里撤销迁移")
                : L("本应用不修改 CC Switch 数据；管理动作只对 Skill Atlas 库与本地直装技能生效")
        ) {
            HStack(spacing: Theme.Space.s8) {
                Text(store.lastLinkCheck.map { LF("外链上次复查 %@", Format.day.string(from: $0)) } ?? L("外链尚未复查"))
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                if store.checkingLinks {
                    ProgressView().controlSize(.mini)
                } else {
                    Button {
                        Task { await store.checkExternalLinks(force: true) }
                    } label: {
                        Text("复查外链存活")
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, Theme.Space.s8)
                            .frame(height: 20)
                            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                    }
                    .buttonStyle(PressableButtonStyle())
                    .quietControl()
                    .help(L("对已装技能引用的外链做存活检查（每周自动跑一次；只报确定失效的）"))
                }
            }
            if issues.isEmpty && security.isEmpty {
                emptyHint(symbol: "checkmark.seal.fill", tint: Theme.healthy, text: L("所有检查项都正常"))
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        if !security.isEmpty {
                            groupHead(L("安全可疑（静态复扫，点行去详情看命中原文）"), count: security.count)
                            ForEach(security, id: \.0.name) { pair in
                                let critical = pair.1.filter { $0.severity == .critical }.count
                                DoctorRow(
                                    skill: pair.0,
                                    note: pair.1.first.map { L($0.rule) } ?? "",
                                    trailing: {
                                        AnyView(miniBadge(
                                            critical > 0 ? LF("%lld 关键", critical) : LF("%lld 警告", pair.1.count),
                                            tint: critical > 0 ? Theme.error : Theme.warning
                                        ))
                                    }
                                )
                            }
                        }
                        if !issues.isEmpty {
                            if !security.isEmpty {
                                groupHead(L("挂载与文件"), count: issues.count)
                            }
                            ForEach(issues) { skill in
                                DoctorRow(
                                    skill: skill,
                                    note: skill.problems.joined(separator: "；"),
                                    trailing: { AnyView(HealthFlag(health: skill.health)) }
                                )
                            }
                        }
                    }
                }
                .panelScroll()
            }
        }
    }
}

// MARK: - 描述体检（丢弃风险 / 截断 / 缩短建议，都是「描述」一件事）

private struct DescriptionPanel: View {
    @Environment(AppStore.self) private var store
    var report: DoctorReport

    var body: some View {
        let total = report.atRisk.count + report.overlong.count + report.verbose.count + report.buried.count
        DoctorPanel(
            symbol: "text.alignleft",
            tint: Theme.warning,
            title: "描述体检",
            count: total,
            subtitle: total == 0
                ? L("所有描述都在预算和长度线内。")
                : L("描述是技能被模型「看见」的唯一入口：超预算会被丢、超长会被截、太啰嗦挤占别人。"),
            note: L("估算")
        ) {
            if total == 0 {
                emptyHint(symbol: "checkmark.seal.fill", tint: Theme.healthy, text: L("描述都短而清楚，模型看得完"))
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        if !report.atRisk.isEmpty {
                            groupHead(L("丢弃风险（按使用频率从低到高被丢）"), count: report.atRisk.count)
                            ForEach(report.atRisk) { entry in
                                DoctorRow(
                                    skill: entry.skill,
                                    note: LF("%d 次会话 · 上架 ~%d token", entry.sessions, entry.tokens),
                                    trailing: { AnyView(EmptyView()) }
                                )
                            }
                        }
                        if !report.buried.isEmpty {
                            groupHead(L("触发词埋太深（前 250 字符之外，listing 里等于没写）"), count: report.buried.count)
                            ForEach(report.buried) { entry in
                                DoctorRow(
                                    skill: entry.skill,
                                    note: entry.phrases.prefix(4).joined(separator: "、"),
                                    trailing: { AnyView(HStack(spacing: Theme.Space.s4) {
                                        miniBadge(L("埋深"), tint: Theme.warning)
                                        RxButton(skill: entry.skill)
                                    }) }
                                )
                            }
                        }
                        if !report.overlong.isEmpty {
                            groupHead(L("会被截断（单条上限 1,536 字符）"), count: report.overlong.count)
                            ForEach(report.overlong) { entry in
                                DoctorRow(
                                    skill: entry.skill,
                                    note: LF("描述 %d 字符，超出部分对模型不可见", entry.skill.description.count),
                                    trailing: { AnyView(HStack(spacing: Theme.Space.s4) {
                                        miniBadge(L("会被截断"), tint: Theme.error)
                                        RxButton(skill: entry.skill)
                                    }) }
                                )
                            }
                        }
                        if !report.verbose.isEmpty {
                            groupHead(L("建议缩短（>1 句或 >200 字）"), count: report.verbose.count)
                            ForEach(report.verbose.prefix(12)) { entry in
                                VStack(alignment: .leading, spacing: Theme.Space.s4) {
                                    DoctorRow(
                                        skill: entry.skill,
                                        note: LF("%d 字 · %d 句", entry.chars, entry.sentences),
                                        trailing: { AnyView(HStack(spacing: Theme.Space.s4) {
                                            miniBadge(L("建议缩短"), tint: Theme.warning)
                                            RxButton(skill: entry.skill)
                                        }) }
                                    )
                                    HStack(alignment: .top, spacing: Theme.Space.s8) {
                                        Text(entry.suggestion)
                                            .font(Theme.Fonts.secondary)
                                            .foregroundStyle(Theme.textSecondary)
                                            .textSelection(.enabled)
                                        CopyIconButton(text: entry.suggestion, help: L("复制缩短建议"))
                                    }
                                    .padding(.leading, 32)
                                }
                            }
                        }
                    }
                }
                .panelScroll()
            }
        }
    }

}

/// 面板内小组头：标题 + 计数
private func groupHead(_ text: String, count: Int) -> some View {
    HStack(spacing: Theme.Space.s4) {
        Text(L(text))
            .font(Theme.Fonts.secondaryEmphasis)
            .foregroundStyle(Theme.textSecondary)
        Text("\(count)")
            .font(Theme.Fonts.caption)
            .monospacedDigit()
            .foregroundStyle(Theme.textTertiary)
    }
    .padding(.top, Theme.Space.s8)
    .padding(.bottom, Theme.Space.s4)
}

// MARK: - 长期未用（可回收）

private struct StalePanel: View {
    @Environment(AppStore.self) private var store
    @Environment(UsageIndexState.self) private var usageIndex
    @State private var confirmBatch = false
    var report: DoctorReport

    var body: some View {
        let stale = store.staleSkills
        let batchable = stale.filter { $0.origin != .ccSwitch }
        DoctorPanel(
            symbol: "zzz",
            tint: Theme.idle,
            title: "长期未用",
            count: stale.count,
            subtitle: stale.isEmpty
                ? L("90 天内都有使用记录。")
                : LF("从未使用或超 90 天未用。悬停行内单个停用，可回收 ~%d token。", report.reclaimableTokens),
            note: L("不计入健康")
        ) {
            if usageIndex.indexing {
                HStack(spacing: Theme.Space.s8) {
                    ProgressView().controlSize(.small)
                    Text(L("正在索引使用记录…"))
                        .font(Theme.Fonts.secondary)
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if stale.isEmpty {
                emptyHint(symbol: "sparkles", tint: Theme.healthy, text: L("没有吃灰的技能"))
            } else {
                VStack(spacing: Theme.Space.s8) {
                    if batchable.count > 1 {
                        Button {
                            confirmBatch = true
                        } label: {
                            HStack(spacing: Theme.Space.s4) {
                                Image(systemName: "pause.circle")
                                    .font(.system(size: 11, weight: .semibold))
                                Text(LF("全部停用（%lld）", batchable.count))
                                    .font(Theme.Fonts.calloutEmphasis)
                            }
                            .foregroundStyle(Theme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 28)
                            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                        }
                        .buttonStyle(PressableButtonStyle())
                        .quietControl()
                        .help(L("把下面所有吃灰技能移入 .disabled/，不删任何文件，随时可恢复"))
                        .confirmationDialog(
                            LF("停用 %lld 个长期未用的技能？", batchable.count),
                            isPresented: $confirmBatch,
                            titleVisibility: .visible
                        ) {
                            Button(L("全部停用"), role: .destructive) { store.disableAllStale() }
                            Button(L("取消"), role: .cancel) {}
                        } message: {
                            Text(LF("目录移入 .disabled/，平台不再加载，可回收约 %lld token 上架预算。不删除任何文件，详情页随时恢复；CC Switch 来源的会跳过。", report.reclaimableTokens))
                        }
                    }
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(stale) { skill in
                                StaleRow(skill: skill)
                            }
                        }
                    }
                    .panelScroll()
                }
            }
        }
    }
}

/// 长期未用行：行内一键停用（≤2 次点击自查达标）
private struct StaleRow: View {
    @Environment(AppStore.self) private var store
    @State private var hovering = false
    var skill: Skill

    var body: some View {
        let record = store.usage[skill.directory]
        HStack(spacing: Theme.Space.s8) {
            CategoryIcon(category: skill.category, size: 24, style: .quiet)
            VStack(alignment: .leading, spacing: 1) {
                Text(skill.name)
                    .font(Theme.Fonts.callout)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(record?.lastUsed.map { LF("上次 %@", Format.day.string(from: $0)) } ?? L("从未使用"))
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer(minLength: Theme.Space.s4)
            if hovering, skill.origin != .ccSwitch {
                Button {
                    store.requestDisable(skill)
                } label: {
                    Text(L("停用"))
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, Theme.Space.s8)
                        .frame(height: 20)
                        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                }
                .buttonStyle(PressableButtonStyle())
                .quietControl()
                .help(L("移入 .disabled/，不删文件，随时恢复"))
            }
        }
        .padding(.horizontal, Theme.Space.s8)
        .padding(.vertical, Theme.Space.s4 + 1)
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(hovering ? Color.primary.opacity(0.04) : Color.clear)
        }
        .onHover { hovering = $0 }
        .onTapGesture { store.select(skill.name) }
    }
}

// MARK: - 触发词重叠

private struct OverlapPanel: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        DoctorPanel(
            symbol: "arrow.triangle.swap",
            tint: Theme.accent,
            title: "触发词重叠",
            count: store.triggerOverlaps.count,
            subtitle: store.triggerOverlaps.isEmpty
                ? L("未发现明显重叠。")
                : L("这些技能对同类任务都会响应，调用时建议点名。"),
            note: L("不计入健康")
        ) {
            if store.triggerOverlaps.isEmpty {
                emptyHint(symbol: "checkmark.seal.fill", tint: Theme.healthy, text: L("触发词分工清晰"))
            } else {
                ScrollView {
                    LazyVStack(spacing: Theme.Space.s8) {
                        ForEach(store.triggerOverlaps) { overlap in
                            OverlapRow(overlap: overlap)
                        }
                    }
                }
                .panelScroll()
            }
        }
    }
}

private struct OverlapRow: View {
    @Environment(AppStore.self) private var store
    var overlap: TriggerOverlap

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s4 + 2) {
            HStack(spacing: Theme.Space.s8) {
                pair(overlap.first)
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                pair(overlap.second)
                Spacer(minLength: 0)
            }
            HStack(spacing: Theme.Space.s4) {
                ForEach(overlap.shared.prefix(4), id: \.self) { phrase in
                    Text(phrase)
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, Theme.Space.s8)
                        .frame(height: 18)
                        .quietControl()
                }
            }
        }
        .padding(Theme.Space.s8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .quietControl(cornerRadius: Theme.Radius.tile)
    }

    private func pair(_ skill: Skill) -> some View {
        Button {
            store.select(skill.name)
        } label: {
            HStack(spacing: Theme.Space.s4) {
                CategoryIcon(category: skill.category, size: 18, style: .quiet)
                Text(skill.name)
                    .font(Theme.Fonts.calloutEmphasis)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(LF("查看 %@", skill.name))
    }
}

// MARK: - 共享小件

private struct DoctorRow: View {
    @Environment(AppStore.self) private var store
    @State private var hovering = false
    var skill: Skill
    var note: String
    var trailing: () -> AnyView

    var body: some View {
        Button {
            store.select(skill.name)
        } label: {
            HStack(spacing: Theme.Space.s8) {
                CategoryIcon(category: skill.category, size: 24, style: .quiet)
                VStack(alignment: .leading, spacing: 1) {
                    Text(skill.name)
                        .font(Theme.Fonts.callout)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(note)
                        .font(Theme.Fonts.caption)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: Theme.Space.s4)
                trailing()
            }
            .padding(.horizontal, Theme.Space.s8)
            .padding(.vertical, Theme.Space.s4 + 1)
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                    .fill(hovering ? Color.primary.opacity(0.04) : Color.clear)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private func miniBadge(_ text: String, tint: Color) -> some View {
    Text(L(text))
        .font(Theme.Fonts.caption)
        .foregroundStyle(tint)
        .padding(.horizontal, Theme.Space.s8)
        .frame(height: 20)
        .quietControl(tint: tint)
}

private func emptyHint(symbol: String, tint: Color, text: String) -> some View {
    VStack(spacing: Theme.Space.s8) {
        Image(systemName: symbol)
            .font(.system(size: 22))
            .foregroundStyle(tint)
        Text(L(text))
            .font(Theme.Fonts.secondary)
            .foregroundStyle(Theme.textSecondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
}

// MARK: - 描述开药（三期 G2）

/// 体检行尾的「开药」入口
struct RxButton: View {
    @Environment(AppStore.self) private var store
    var skill: Skill

    var body: some View {
        Button {
            store.requestPrescription(skill)
        } label: {
            Label(L("开药"), systemImage: "pills")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, Theme.Space.s8)
                .frame(height: 22)
                .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .quietControl()
        .help(L("生成改写建议：触发词句子前置进 250 字符可见窗，试触发对比疗效后可写回"))
    }
}

/// 处方 sheet：改法说明 + 前后对照（250 字符可见线）+ 试触发疗效 + 写回
struct PrescriptionSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var probePhrase = ""
    @State private var promptCopied = false

    private var rx: DescriptionPrescription? { store.prescription }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1)
            content.padding(Theme.Space.s20)
        }
        .frame(width: 680, height: 620)
        .background(.regularMaterial)
        .onAppear {
            probePhrase = rx?.beforeBuried.first ?? ""
        }
    }

    private var header: some View {
        HStack(spacing: Theme.Space.s12) {
            Image(systemName: "pills")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 28, height: 28)
                .background {
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .fill(Theme.accent.opacity(0.12))
                }
            VStack(alignment: .leading, spacing: 1) {
                Text(rx?.skill.name ?? "")
                    .font(Theme.Fonts.panelTitle)
                    .foregroundStyle(Theme.textPrimary)
                Text(L("描述开药 · 只重排句子不增删一字，写回前先看疗效"))
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
        if let rx {
            VStack(alignment: .leading, spacing: Theme.Space.s12) {
                movesBlock(rx)
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.s12) {
                        descriptionBlock(title: L("改前"), text: rx.original, buried: rx.beforeBuried)
                        if !rx.noop {
                            descriptionBlock(title: L("改后"), text: rx.rewritten, buried: rx.afterBuried)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .panelScroll()
                if !rx.noop { efficacyRow(rx) }
                footer(rx)
            }
        }
    }

    private func movesBlock(_ rx: DescriptionPrescription) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s4) {
            ForEach(Array(rx.moves.enumerated()), id: \.offset) { _, move in
                Label(move, systemImage: "arrow.turn.down.right")
                    .font(Theme.Fonts.secondary)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(Theme.Space.s8 + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .quietControl(cornerRadius: Theme.Radius.control)
    }

    /// 描述展示：前 250 字符正常色，之后调暗——可见线肉眼可辨
    private func descriptionBlock(title: String, text: String, buried: [String]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s4) {
            HStack(spacing: Theme.Space.s8) {
                Text(title)
                    .font(Theme.Fonts.secondaryEmphasis)
                    .foregroundStyle(Theme.textPrimary)
                Text(LF("%d 字符", text.count))
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textTertiary)
                if buried.isEmpty {
                    Text(L("无埋深触发词"))
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.healthy)
                } else {
                    Text(LF("埋深：%@", buried.prefix(4).joined(separator: "、")))
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.warning)
                }
            }
            (Text(String(text.prefix(TriggerLab.visibleWindow)))
                .foregroundColor(Theme.textPrimary)
             + Text(text.count > TriggerLab.visibleWindow ? "⟨250⟩" : "")
                .foregroundColor(Theme.accent)
             + Text(String(text.dropFirst(TriggerLab.visibleWindow)))
                .foregroundColor(Theme.textTertiary))
                .font(Theme.Fonts.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.Space.s8 + 2)
                .quietControl(cornerRadius: Theme.Radius.control)
        }
    }

    /// 疗效行：同一句话，改前/改后各排第几
    private func efficacyRow(_ rx: DescriptionPrescription) -> some View {
        let ranks = store.rxRankComparison(phrase: probePhrase)
        return HStack(spacing: Theme.Space.s8) {
            Text(L("疗效试触发"))
                .font(Theme.Fonts.secondaryEmphasis)
                .foregroundStyle(Theme.textPrimary)
            TextField(L("输入你会说的话（预填第一个埋深触发词）"), text: $probePhrase)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 260)
            rankBadge(label: L("改前"), rank: ranks.before)
            Image(systemName: "arrow.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
            rankBadge(label: L("改后"), rank: ranks.after)
            Spacer()
        }
    }

    private func rankBadge(label: String, rank: Int?) -> some View {
        HStack(spacing: Theme.Space.s4) {
            Text(label)
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.textTertiary)
            Text(rank.map { LF("第 %d 名", $0) } ?? L("未进前 8"))
                .font(Theme.Fonts.calloutEmphasis)
                .foregroundStyle(rank == 1 ? Theme.healthy : (rank == nil ? Theme.error : Theme.textPrimary))
        }
        .padding(.horizontal, Theme.Space.s8)
        .frame(height: 24)
        .quietControl()
    }

    private func footer(_ rx: DescriptionPrescription) -> some View {
        HStack(spacing: Theme.Space.s8) {
            Button {
                store.copyToPasteboard(DescriptionRx.rewritePrompt(skill: rx.skill))
                promptCopied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { promptCopied = false }
            } label: {
                Label(promptCopied ? L("已复制") : L("复制 Claude 改写指令"), systemImage: promptCopied ? "checkmark" : "doc.on.doc")
                    .font(Theme.Fonts.calloutEmphasis)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, Theme.Space.s12)
                    .frame(height: 28)
                    .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            }
            .buttonStyle(PressableButtonStyle())
            .quietControl()
            .help(L("机器只重排；要真正精简/重写，把指令贴给 Claude 按 Trigger Triad 改，改完手动替换"))
            Spacer()
            Button {
                store.adoptPrescription()
            } label: {
                HStack(spacing: Theme.Space.s4) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 11, weight: .semibold))
                    Text(L("采纳并写回"))
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
            .disabled(rx.noop || rx.skill.origin == .ccSwitch)
            .help(rx.skill.origin == .ccSwitch
                  ? L("CC Switch 技能只读。先迁移进本库，再开药写回。")
                  : L("写回 SKILL.md 的 description；git 技能算一次本地改动，更新时受补丁保护"))
        }
    }
}
