import SwiftUI
#if SWIFT_PACKAGE
import AtlasCore
#endif

// MARK: - 收件箱（v15 一级页，WP-I）
//
// 回答「现在有什么事要我裁决」。v12 行动中心骨架复用：主任务卡（四要素：发生了
// 什么 / 影响什么 / 建议怎么做 / 按钮去哪）+「接下来」纵向队列 + 清零态。
// 条目由 InboxAssembler 渲染时聚合（ADR-10），动作全部接既有机制，裁决必留痕。

struct InboxPage: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var inbox = InboxStore()

    var body: some View {
        let items = inbox.items(store: store)
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.s16) {
                    if let receipt = inbox.receipt {
                        ReceiptLine(text: receipt.text, failed: receipt.failed) {
                            inbox.receipt = nil
                        }
                        .receiptTransition(reduceMotion: reduceMotion)
                    }
                    if items.isEmpty {
                        quietState
                    } else {
                        PrimaryTaskCard(inbox: inbox, item: items[0])
                            .id(items[0].id)
                        if items.count > 1 {
                            Text(L("接下来"))
                                .font(Theme.Fonts.secondaryEmphasis)
                                .foregroundStyle(Theme.textSecondary)
                                .padding(.leading, Theme.Space.s4)
                            LazyVStack(spacing: 0) {
                                ForEach(Array(items.dropFirst().enumerated()), id: \.element.id) { index, item in
                                    if index > 0 {
                                        Rectangle()
                                            .fill(Color.primary.opacity(0.06))
                                            .frame(height: 1)
                                            .padding(.leading, Theme.Space.s12)
                                    }
                                    InboxRow(inbox: inbox, item: item)
                                        .id(item.id)
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
                            .quietControl(cornerRadius: Theme.Radius.tile)
                        }
                    }
                }
                .padding(Theme.Space.s20)
                .animation(reduceMotion ? nil : Motion.standard, value: inbox.receipt)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .panelScroll()
            .contentSurface()
            .onAppear {
                if let target = Inbox.pendingFocusID {
                    Inbox.pendingFocusID = nil
                    withAnimation(nil) { proxy.scrollTo(target, anchor: .center) }
                }
            }
        }
    }

    private var quietState: some View {
        EmptyStateBlock(
            symbol: "checkmark.circle",
            title: L("一切安静"),
            caption: lastClearedText,
            actionTitle: L("再查一遍")
        ) {
            Task { await store.rescan() }
        }
    }

    private var lastClearedText: String {
        guard let at = InboxState.lastDecisionAt else {
            return L("还没有处理过事项。检出的运维事项会在这里排队。")
        }
        let date = Date(timeIntervalSince1970: TimeInterval(at))
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return LF("上次裁决：%@", formatter.string(from: date))
    }
}

// MARK: - 主任务卡（v12 四要素）

private struct PrimaryTaskCard: View {
    @Environment(AppStore.self) private var store
    @Bindable var inbox: InboxStore
    var item: InboxItem

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s12) {
            HStack(spacing: Theme.Space.s8) {
                InboxKindBadge(kind: item.kind)
                Text(L("先处理这一件"))
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            Text(item.title)
                .font(Theme.Fonts.panelTitle)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(item.detail)
                .font(Theme.Fonts.body)
                .lineSpacing(2)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            InboxActions(inbox: inbox, item: item, emphasized: true)
        }
        .padding(Theme.Space.s20)
        .frame(maxWidth: .infinity, alignment: .leading)
        // 底色不着语义色：严重度由 InboxKindBadge 单独承载。
        // 同一条目「琥珀底 + 红徽标」是两个语义色描述一件事（DESIGN 色彩收敛）。
        .quietControl(cornerRadius: Theme.Radius.tile)
    }
}

// MARK: - 队列行

private struct InboxRow: View {
    @Bindable var inbox: InboxStore
    var item: InboxItem

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.s12) {
            InboxKindBadge(kind: item.kind, compact: true)
            VStack(alignment: .leading, spacing: Theme.Space.s4) {
                Text(item.title)
                    .font(Theme.Fonts.calloutEmphasis)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(item.detail)
                    .font(Theme.Fonts.secondary)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                InboxActions(inbox: inbox, item: item, emphasized: false)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Space.s12)
        .padding(.vertical, Theme.Space.s8 + 2)
        .rowHover()
    }
}

/// 类别徽标：只用既有语义色（DESIGN v15 InboxCard）
private struct InboxKindBadge: View {
    var kind: InboxKind
    var compact = false

    private var meta: (symbol: String, label: String, tint: Color) {
        switch kind {
        case .approval: return ("person.badge.shield.checkmark", L("待审批"), Theme.warning)
        case .securityCritical: return ("lock.shield", L("安全关键"), Theme.error)
        case .securityWarning: return ("exclamationmark.triangle", L("安全提醒"), Theme.warning)
        case .mount: return ("link.badge.plus", L("挂载"), Theme.warning)
        case .miss: return ("bell.badge", L("miss"), Theme.warning)
        case .update: return ("arrow.down.circle", L("可更新"), Theme.accent)
        case .overlap: return ("arrow.triangle.branch", L("触发重叠"), Theme.idle)
        case .overlong: return ("text.magnifyingglass", L("介绍"), Theme.idle)
        case .rx: return ("chart.bar", L("回访"), Theme.accent)
        }
    }

    var body: some View {
        let meta = meta
        HStack(spacing: Theme.Space.s4) {
            Image(systemName: meta.symbol)
                .font(.system(size: compact ? 10 : 11, weight: .semibold))
            if !compact {
                Text(meta.label)
                    .font(Theme.Fonts.caption)
            }
        }
        .foregroundStyle(meta.tint)
        .padding(.horizontal, compact ? 0 : Theme.Space.s4 + 2)
        .frame(height: 20)
        .frame(minWidth: compact ? 20 : 0)
        .quietControl(tint: meta.tint)
        .help(meta.label)
    }
}

// MARK: - 条目动作（全部接既有机制）

private struct InboxActions: View {
    @Environment(AppStore.self) private var store
    @Bindable var inbox: InboxStore
    var item: InboxItem
    var emphasized: Bool

    var body: some View {
        HStack(spacing: Theme.Space.s12) {
            switch item.kind {
            case .approval:
                primary(L("审阅并批准…")) { inbox.openApproval(item, store: store) }
            case .securityCritical:
                if let skill = inbox.skill(for: item, store: store),
                   let finding = store.criticalFindings(for: skill).first {
                    primary(L("打开原文")) { store.openFinding(finding, in: skill) }
                }
                detailLink
            case .securityWarning:
                if let skill = inbox.skill(for: item, store: store),
                   let finding = store.advisoryFindings(for: skill).first {
                    primary(L("打开原文")) { store.openFinding(finding, in: skill) }
                }
                detailLink
                ignoreButton
            case .mount:
                detailLinkPrimary
                if let skill = inbox.skill(for: item, store: store) {
                    secondary(L("在访达中显示")) { store.openFolder(skill.sourcePath) }
                }
            case .miss:
                let hit = store.missHits.first { $0.directory == item.target }
                if let skill = inbox.skill(for: item, store: store), hit?.userInvocableOnly != true {
                    primary(L("开处方")) { store.requestPrescription(skill) }
                }
                if hit?.userInvocableOnly == true {
                    secondary(L("去供给页升档")) { store.nav = .supply }
                }
                ignoreButton
            case .update:
                if let skill = inbox.skill(for: item, store: store) {
                    primary(L("看更新…")) { store.requestUpdate(skill) }
                }
                ignoreButton
            case .overlap:
                primary(inbox.copiedOverlapID == item.id ? L("已复制点名调用语") : L("复制点名调用语")) {
                    inbox.copyOverlapPhrase(item, store: store)
                }
                ignoreButton
            case .overlong:
                if let skill = inbox.skill(for: item, store: store), skill.origin != .ccSwitch {
                    primary(L("生成调整建议")) { store.requestPrescription(skill) }
                }
                detailLink
                ignoreButton
            case .rx:
                detailLinkPrimary
                ignoreButton
            }
        }
    }

    @ViewBuilder
    private var detailLinkPrimary: some View {
        if let name = item.skillName {
            primary(L("打开技能详情")) { store.select(name) }
        }
    }

    @ViewBuilder
    private var detailLink: some View {
        if let name = item.skillName {
            secondary(L("打开技能详情")) { store.select(name) }
        }
    }

    private var ignoreButton: some View {
        Button(L("忽略")) { inbox.ignore(item, store: store) }
            .buttonStyle(.plain)
            .font(Theme.Fonts.caption)
            .foregroundStyle(Theme.textTertiary)
            .help(L("同一问题再变化时会重新出现"))
    }

    @ViewBuilder
    private func primary(_ title: String, action: @escaping () -> Void) -> some View {
        if emphasized {
            // 主任务卡：一屏一个强调色主按钮（DESIGN 铁律），材质与全 App 一致
            AtlasPrimaryButton(title: title, action: action)
        } else {
            secondary(title, action: action)
        }
    }

    private func secondary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Fonts.secondaryEmphasis)
                .foregroundStyle(Theme.accent)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
    }
}
