import SwiftUI
#if SWIFT_PACKAGE
import AtlasCore
#endif

// MARK: - 设置 → 维护
//
// 不是一级页。默认折叠。挡住使用的问题已经写在技能详情顶部；
// 这里给要整理整库的人：安全可疑、挂载失败、闲置、触发词重叠、介绍不好找。

struct MaintenanceGroup: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var open = false
    @State private var confirmStale = false
    @State private var copiedID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s12) {
            Button {
                if reduceMotion {
                    open.toggle()
                } else {
                    withAnimation(Motion.standard) { open.toggle() }
                }
            } label: {
                HStack(spacing: Theme.Space.s8) {
                    Text(L("维护"))
                        .font(Theme.Fonts.secondaryEmphasis)
                        .foregroundStyle(Theme.textSecondary)
                    Text(caption)
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                        .rotationEffect(.degrees(open ? 90 : 0))
                }
                .padding(.leading, Theme.Space.s4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(open ? L("收起维护") : L("展开维护"))

            if open {
                content
            }
        }
        .onAppear { if store.revealMaintenance { open = true } }
        .onChange(of: store.revealMaintenance) { _, reveal in
            if reveal {
                withAnimation(reduceMotion ? nil : Motion.control) { open = true }
            }
        }
    }

    private var caption: String {
        let blocking = store.blockingIssueCount
        if blocking > 0 { return LF("有 %d 件会挡住使用", blocking) }
        let advisory = advisoryCount
        if advisory > 0 { return LF("有 %d 项整理建议", advisory) }
        return L("连接、安全和闲置整理")
    }

    private var advisoryCount: Int {
        let security = store.skills.filter { !$0.disabled && !store.advisoryFindings(for: $0).isEmpty }.count
        let stale = store.staleSkills.count
        let overlap = store.triggerOverlaps.count
        let discover = discoverability.count
        return security + stale + overlap + discover
    }

    @ViewBuilder
    private var content: some View {
        let blocking = focusedFirst(store.blockingSkills)
        let warnings = warningSkills
        let stale = store.staleSkills
        let overlaps = store.triggerOverlaps
        let discover = discoverability
        let misses = store.missHits
        let followups = RxFollowup.due()

        if blocking.isEmpty && warnings.isEmpty && stale.isEmpty && overlaps.isEmpty && discover.isEmpty && misses.isEmpty && followups.isEmpty {
            focusedEmptyState
            emptyState
        } else {
            focusedEmptyState
            if !blocking.isEmpty {
                section(L("挡住使用的"), count: blocking.count) {
                    ForEach(blocking) { skill in
                        blockingRow(skill)
                    }
                }
            }
            if !warnings.isEmpty {
                section(L("安全可疑"), count: warnings.count) {
                    ForEach(warnings.prefix(8)) { item in
                        warningRow(item.skill, findings: item.findings)
                    }
                }
            }
            if !stale.isEmpty {
                section(L("很久没用"), count: stale.count) {
                    staleAction
                } content: {
                    ForEach(stale.prefix(6)) { skill in
                        actionRow(
                            title: skill.name,
                            detail: staleDetail(skill),
                            symbol: "pause.circle",
                            tint: Theme.idle
                        ) {
                            Button(L("打开技能详情")) { store.select(skill.name) }
                                .buttonStyle(.plain)
                                .font(Theme.Fonts.secondaryEmphasis)
                                .foregroundStyle(Theme.accent)
                        }
                    }
                }
            }
            if !overlaps.isEmpty {
                section(L("容易叫错"), count: overlaps.count) {
                    ForEach(overlaps.prefix(5)) { pair in
                        overlapRow(pair)
                    }
                }
            }
            if !discover.isEmpty {
                section(L("介绍不好找"), count: discover.count) {
                    ForEach(discover.prefix(6)) { item in
                        discoverRow(item)
                    }
                }
            }
            if !misses.isEmpty {
                section(L("本周 miss"), count: misses.count) {
                    ForEach(misses) { hit in
                        missRow(hit)
                    }
                }
            }
            if !followups.isEmpty {
                section(L("改写疗效"), count: followups.count) {
                    ForEach(followups) { card in
                        followupRow(card)
                    }
                }
            }
        }
    }

    private func missRow(_ hit: MissHit) -> some View {
        actionRow(
            title: hit.name,
            detail: hit.userInvocableOnly
                ? LF("可以用 /%@ 调用", hit.name)
                : LF("%d 次该触发却没触发", hit.occurrences),
            symbol: "bell.badge",
            tint: Theme.warning
        ) {
            HStack(spacing: Theme.Space.s8) {
                if !hit.userInvocableOnly {
                    Button(L("开处方")) {
                        if let skill = store.skills.first(where: { $0.directory == hit.directory }) {
                            store.requestPrescription(skill)
                        }
                    }
                    .buttonStyle(.plain)
                    .font(Theme.Fonts.secondaryEmphasis)
                    .foregroundStyle(Theme.accent)
                }
                Button(L("忽略")) { store.ignoreMiss(hit) }
                    .buttonStyle(.plain)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private func followupRow(_ card: RxFollowup.Card) -> some View {
        let skill = store.skills.first { $0.directory == card.directory }
        let sessions = store.usage[card.directory]?.total ?? 0
        return actionRow(
            title: skill?.name ?? card.directory,
            detail: LF("写回已 %d 天，现在 %d 次会话", card.ageDays, sessions),
            symbol: "chart.bar",
            tint: Theme.accent
        ) {
            Button(L("打开技能详情")) {
                if let skill { store.select(skill.name) }
            }
            .buttonStyle(.plain)
            .font(Theme.Fonts.secondaryEmphasis)
            .foregroundStyle(Theme.accent)
        }
    }

    @ViewBuilder
    private var focusedEmptyState: some View {
        if let name = store.maintenanceFocusSkillName,
           let skill = store.skills.first(where: { $0.name == name }),
           !store.hasBlockingIssue(skill) {
            VStack(alignment: .leading, spacing: Theme.Space.s8) {
                Text(LF("“%@”没有挡住使用的问题", skill.name))
                    .font(Theme.Fonts.rowTitle)
                    .foregroundStyle(Theme.textPrimary)
                Text(L("调用语里写出技能名更稳。确认技能详情里已经点亮你正在用的软件。"))
                    .font(Theme.Fonts.secondary)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(L("打开技能详情")) { store.select(skill.name) }
                    .buttonStyle(.plain)
                    .font(Theme.Fonts.secondaryEmphasis)
                    .foregroundStyle(Theme.accent)
            }
            .padding(Theme.Space.s16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .quietControl(cornerRadius: Theme.Radius.tile)
        }
    }

    private var emptyState: some View {
        Text(L("没有需要处理的维护项"))
            .font(Theme.Fonts.secondary)
            .foregroundStyle(Theme.textTertiary)
            .padding(.leading, Theme.Space.s4)
    }

    private var staleAction: some View {
        Button(L("先停用这些")) { confirmStale = true }
            .buttonStyle(.plain)
            .font(Theme.Fonts.secondaryEmphasis)
            .foregroundStyle(Theme.textSecondary)
            .confirmationDialog(
                LF("停用 %d 个很久没用的 Skill？", store.staleSkills.count),
                isPresented: $confirmStale,
                titleVisibility: .visible
            ) {
                Button(L("停用这些"), role: .destructive) { store.disableAllStale() }
                Button(L("取消"), role: .cancel) {}
            } message: {
                Text(L("只会先停用，文件仍然保留，需要时可以恢复。"))
            }
    }

    private func blockingRow(_ skill: Skill) -> some View {
        let critical = store.criticalFindings(for: skill)
        return actionRow(
            title: skill.name,
            detail: critical.first?.beginnerNote ?? (skill.problems.first ?? L("它与 AI 软件的连接需要确认。")),
            symbol: critical.isEmpty ? "link.badge.plus" : "lock.shield",
            tint: critical.isEmpty ? Theme.warning : Theme.error,
            emphasized: skill.name == store.maintenanceFocusSkillName
        ) {
            if let finding = critical.first {
                Button(L("打开原文")) { store.openFinding(finding, in: skill) }
                    .buttonStyle(.plain)
                    .font(Theme.Fonts.secondaryEmphasis)
                    .foregroundStyle(Theme.accent)
            }
            Button(L("打开技能详情")) { store.select(skill.name) }
                .buttonStyle(.plain)
                .font(Theme.Fonts.secondaryEmphasis)
                .foregroundStyle(Theme.accent)
        }
    }

    private func warningRow(_ skill: Skill, findings: [SecurityFinding]) -> some View {
        actionRow(
            title: skill.name,
            detail: findings.first?.beginnerNote ?? L("安装前扫到了需要先看一眼的写法。"),
            symbol: "exclamationmark.triangle",
            tint: Theme.warning,
            emphasized: skill.name == store.maintenanceFocusSkillName
        ) {
            if let finding = findings.first {
                Button(L("打开原文")) { store.openFinding(finding, in: skill) }
                    .buttonStyle(.plain)
                    .font(Theme.Fonts.secondaryEmphasis)
                    .foregroundStyle(Theme.accent)
            }
        }
    }

    private func overlapRow(_ pair: TriggerOverlap) -> some View {
        let phrase = LF("请使用 %@：<写清你的目标>", pair.first.name)
        return actionRow(
            title: LF("“%@”和“%@”会响应相似说法", pair.first.name, pair.second.name),
            detail: L("不必卸载任何 Skill；在调用语里写出名字即可。"),
            symbol: "arrow.triangle.branch",
            tint: Theme.warning
        ) {
            Button(copiedID == pair.id ? L("已复制点名调用语") : L("复制点名调用语")) {
                store.copyToPasteboard(phrase)
                copiedID = pair.id
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                    if copiedID == pair.id { copiedID = nil }
                }
            }
            .buttonStyle(.plain)
            .font(Theme.Fonts.secondaryEmphasis)
            .foregroundStyle(Theme.accent)
        }
    }

    private func discoverRow(_ item: DiscoverItem) -> some View {
        actionRow(
            title: item.skill.name,
            detail: item.detail,
            symbol: "text.magnifyingglass",
            tint: Theme.accent,
            emphasized: item.skill.name == store.maintenanceFocusSkillName
        ) {
            if item.skill.origin != .ccSwitch {
                Button(L("生成调整建议")) { store.requestPrescription(item.skill) }
                    .buttonStyle(.plain)
                    .font(Theme.Fonts.secondaryEmphasis)
                    .foregroundStyle(Theme.accent)
            }
            Button(L("打开技能详情")) { store.select(item.skill.name) }
                .buttonStyle(.plain)
                .font(Theme.Fonts.secondaryEmphasis)
                .foregroundStyle(Theme.accent)
        }
    }

    private func section<Content: View>(
        _ title: String,
        count: Int,
        @ViewBuilder content: () -> Content
    ) -> some View {
        section(title, count: count, trailing: { EmptyView() }) {
            content()
        }
    }

    private func section<Content: View, Trailing: View>(
        _ title: String,
        count: Int,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s8) {
            HStack(spacing: Theme.Space.s8) {
                Text(title)
                    .font(Theme.Fonts.secondaryEmphasis)
                    .foregroundStyle(Theme.textSecondary)
                Text("\(count)")
                    .font(Theme.Fonts.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
                Spacer(minLength: 0)
                trailing()
            }
            .padding(.leading, Theme.Space.s4)
            VStack(spacing: 0) {
                content()
            }
            .quietControl(cornerRadius: Theme.Radius.tile)
        }
    }

    private func actionRow<Trailing: View>(
        title: String,
        detail: String,
        symbol: String,
        tint: Color,
        emphasized: Bool = false,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.s12) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(tint.opacity(0.10))
                }
            VStack(alignment: .leading, spacing: Theme.Space.s4) {
                Text(title)
                    .font(Theme.Fonts.calloutEmphasis)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(Theme.Fonts.secondary)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Theme.Space.s12) { trailing() }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Space.s16)
        .padding(.vertical, Theme.Space.s12)
        .background(emphasized ? Theme.accent.opacity(0.06) : Color.clear)
    }

    private var warningSkills: [WarningItem] {
        let items = store.skills.compactMap { skill -> WarningItem? in
            guard !skill.disabled, !store.hasBlockingIssue(skill) else { return nil }
            let findings = store.advisoryFindings(for: skill)
            guard !findings.isEmpty else { return nil }
            return WarningItem(skill: skill, findings: findings)
        }
        return focusedFirst(items, name: \.skill.name)
    }

    private var discoverability: [DiscoverItem] {
        var seen = Set<String>()
        var items: [DiscoverItem] = []
        func add(_ skill: Skill, _ detail: String) {
            guard seen.insert(skill.directory).inserted, !skill.disabled else { return }
            items.append(DiscoverItem(skill: skill, detail: detail))
        }
        let report = store.doctorReport
        for entry in report.atRisk {
            add(entry.skill, L("当前技能清单较满，它的介绍可能排在可见范围之外。"))
        }
        for entry in report.buried {
            add(entry.skill, LF("关键说法写得太靠后：%@", entry.phrases.prefix(3).joined(separator: L("、"))))
        }
        for entry in report.overlong {
            add(entry.skill, LF("介绍有 %d 个字符，后半段可能不会进入技能清单。", entry.skill.description.count))
        }
        for entry in report.verbose.prefix(12) {
            add(entry.skill, LF("介绍有 %d 个字符，可以先说清使用时机。", entry.chars))
        }
        return focusedFirst(items, name: \.skill.name)
    }

    private func staleDetail(_ skill: Skill) -> String {
        if let last = store.usage[skill.directory]?.lastUsed {
            return LF("最近使用 %@", Format.day.string(from: last))
        }
        return L("还没有使用记录")
    }

    private func focusedFirst(_ skills: [Skill]) -> [Skill] {
        guard let focus = store.maintenanceFocusSkillName else { return skills }
        return skills.sorted { lhs, rhs in
            (lhs.name == focus ? 0 : 1) < (rhs.name == focus ? 0 : 1)
        }
    }

    private func focusedFirst<T>(_ items: [T], name: KeyPath<T, String>) -> [T] {
        guard let focus = store.maintenanceFocusSkillName else { return items }
        return items.sorted { lhs, rhs in
            (lhs[keyPath: name] == focus ? 0 : 1) < (rhs[keyPath: name] == focus ? 0 : 1)
        }
    }
}

private struct DiscoverItem: Identifiable {
    var skill: Skill
    var detail: String
    var id: String { skill.name }
}

private struct WarningItem: Identifiable {
    var skill: Skill
    var findings: [SecurityFinding]
    var id: String { skill.name }
}
