import SwiftUI
#if SWIFT_PACKAGE
import AtlasCore
#endif

// MARK: - 检查（v16 一级页，ROADMAP 2.2）
//
// 回答用户会用人话问出来的那句：「有什么要我处理吗？」
//
// 这里只放**待办**：有限、必须逐条决定、处理完就没了。安全提示（本机 118 条）、
// 触发词重叠、介绍埋太深那些属于技能自身的**性质**，数量大又不需要逐条决定，
// 排进队列的结果是既清不完又看不懂——它们回到技能行上当标记。
//
// 页顶那张卡是原「供给页」的全部实际价值：技能清单占多少 token，一键清理。
// 一个数字 + 一个动作，不需要一整页和「供给」这个没人懂的词。

struct CheckPage: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var inbox = InboxStore()

    var body: some View {
        let groups = InboxGroup.build(inbox.items(store: store))
        let leadID = InboxGroup.leadID(groups)
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.s20) {
                    if let receipt = inbox.receipt {
                        ReceiptLine(text: receipt.text, failed: receipt.failed) {
                            inbox.receipt = nil
                        }
                        .receiptTransition(reduceMotion: reduceMotion)
                    }

                    if groups.isEmpty {
                        quietState
                    } else {
                        section(L("要你处理的")) {
                            VStack(alignment: .leading, spacing: Theme.Space.s12) {
                                ForEach(groups) { group in
                                    // 全页只允许一个实心主按钮。六张卡各顶一个发光蓝按钮，
                                    // 等于六个「先点我」——没有优先级就是没有引导；但一个都不给
                                    // 又等于没有入口。给「一键能修掉最多条」的那张，
                                    // 那里点一下收益最大。
                                    GroupCard(inbox: inbox, group: group, lead: group.id == leadID)
                                        .id(group.id)
                                }
                            }
                        }
                    }

                    // 账单不是待办：它不会「处理完就没了」，是这个库长期的一条属性。
                    // 所以它在待办下面、自己一节，标题也说清楚是「顺便」。
                    section(L("顺便看一眼")) { TokenCard() }
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

    private func section<Content: View>(
        _ title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s8) {
            Text(title)
                .font(Theme.Fonts.secondaryEmphasis)
                .foregroundStyle(Theme.textSecondary)
                .padding(.leading, Theme.Space.s4)
            content()
        }
    }

    private var quietState: some View {
        EmptyStateBlock(
            symbol: "checkmark.circle",
            title: L("没有要处理的事"),
            caption: lastClearedText,
            actionTitle: L("再查一遍")
        ) {
            Task { await store.rescan() }
        }
    }

    private var lastClearedText: String {
        guard let at = InboxState.lastDecisionAt else {
            return L("技能装了就能用。真出问题时会出现在这里。")
        }
        let date = Date(timeIntervalSince1970: TimeInterval(at))
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return LF("上次处理：%@", formatter.string(from: date))
    }
}

// MARK: - 按原因归并
//
// 队列上一版是「一个技能一条」。真机上跑出来是这样：6 个技能同时报
// 「装了但用不了 / GrokBuild 挂载缺失」——那不是 6 件事，是 1 件事的 6 个症状
// （Grok 那批软链集体没了）。用户被迫滚过 14 行，读到的全是同一句话。
//
// 归并键取 (类别, detail)：detail 就是原因本身——挂载类是「哪个平台出了什么问题」，
// 安全类是「扫出来的是哪种写法」。同因的合成一张卡，给一个能一次修完的动作；
// 独一份的照旧单独成卡，不套壳。
struct InboxGroup: Identifiable {
    var kind: InboxKind
    /// 给人看的那句原因。归并键是 InboxItem.cause，这里存的是可读版本。
    var reason: String
    var items: [InboxItem]

    var id: String { items.count == 1 ? items[0].id : "\(kind.rawValue):\(Inbox.hash8(reason))" }
    var isSingle: Bool { items.count == 1 }
    var skillNames: [String] { items.compactMap { $0.skillName ?? $0.title } }

    /// 归并后的标题用「几个技能 + 原因」，不再重复技能名——名字进副文案
    var title: String {
        if let single = items.first, isSingle { return single.title }
        switch kind {
        case .mount: return LF("%d 个技能装了但用不了", items.count)
        case .securityCritical, .securityWarning: return LF("%d 个技能里有危险写法", items.count)
        case .update: return LF("%d 个技能有新版本", items.count)
        case .miss: return LF("%d 个技能叫不动", items.count)
        default: return LF("%d 件同类的事", items.count)
        }
    }

    var detail: String {
        guard !isSingle else { return items[0].detail }
        let names = skillNames.prefix(3).joined(separator: L("、"))
        let rest = items.count - min(3, skillNames.count)
        let list = rest > 0 ? LF("%@ 等 %d 个", names, items.count) : names
        return LF("%@。%@", reason, list)
    }

    /// 归并卡上给人看的原因。detail 里带技能名，合并后重复且啰嗦，这里给去名版本。
    static func reason(for item: InboxItem) -> String {
        switch item.cause {
        case "miss-user-invocable": return L("它们被设成了「点名才用」，所以不进开场清单")
        case "miss-not-triggering": return L("你说的话它们本该接住却没接")
        case "update": return L("关联仓库有新提交")
        case "mount-unknown": return L("和 AI 软件之间的连接断了")
        default: return item.cause
        }
    }

    /// 这一批里哪张卡该顶主按钮：优先给条数最多的**可批量修复**的那张
    /// （挂载断了、被设成点名才用——这两类一键就能修完）；一张都没有就给队首。
    static func leadID(_ groups: [InboxGroup]) -> String? {
        let repairable = groups.filter {
            $0.items.count > 1 && ($0.kind == .mount || $0.items.first?.cause == "miss-user-invocable")
        }
        if let best = repairable.max(by: { $0.items.count < $1.items.count }) { return best.id }
        return groups.first?.id
    }

    static func build(_ items: [InboxItem]) -> [InboxGroup] {
        var order: [String] = []
        var buckets: [String: InboxGroup] = [:]
        for item in items {
            // cause 为空 = 永不合并（审批这类必须逐条看原文的）
            let key = item.cause.isEmpty
                ? "solo:\(item.id)"
                : "\(item.kind.rawValue)|\(item.cause)"
            if buckets[key] == nil {
                order.append(key)
                buckets[key] = InboxGroup(kind: item.kind, reason: Self.reason(for: item), items: [])
            }
            buckets[key]?.items.append(item)
        }
        return order.compactMap { buckets[$0] }
    }
}

/// 队首用实心主按钮，其余用安静控件——同屏只允许一个「先点我」
private struct BulkButtonSkin: ViewModifier {
    var lead: Bool

    func body(content: Content) -> some View {
        if lead {
            content.accentGlass(Capsule(style: .continuous))
        } else {
            content.quietControl(cornerRadius: 14, tint: Theme.accent)
        }
    }
}

private struct GroupCard: View {
    @Environment(AppStore.self) private var store
    @Bindable var inbox: InboxStore
    @State private var expanded = false
    var group: InboxGroup
    var lead: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s12) {
            HStack(alignment: .top, spacing: Theme.Space.s12) {
                InboxKindBadge(kind: group.kind)
                VStack(alignment: .leading, spacing: Theme.Space.s4) {
                    Text(group.title)
                        .font(Theme.Fonts.rowTitle)
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(group.detail)
                        .font(Theme.Fonts.secondary)
                        .lineSpacing(2)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            if group.isSingle {
                InboxActions(inbox: inbox, item: group.items[0], emphasized: lead)
            } else {
                HStack(spacing: Theme.Space.s12) {
                    if let bulk = bulkAction {
                        bulkButton(bulk.title, action: bulk.run)
                    }
                    Button(expanded ? L("收起") : LF("逐个看这 %d 个", group.items.count)) {
                        expanded.toggle()
                    }
                    .buttonStyle(.plain)
                    .font(Theme.Fonts.secondaryEmphasis)
                    .foregroundStyle(Theme.accent)
                }
            }

            if expanded, !group.isSingle {
                VStack(spacing: 0) {
                    ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
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
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
                .quietControl(cornerRadius: Theme.Radius.row)
            }
        }
        .padding(Theme.Space.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
        // 底色不着语义色：严重度由 InboxKindBadge 单独承载
        .quietControl(cornerRadius: Theme.Radius.tile)
    }

    /// 归并卡的批量动作：一次修掉那**一个**原因。没有能一次修完的动作就不给按钮，
    /// 只留「逐个看」——给一个点了不知道会发生什么的批量键比不给更糟。
    private var bulkAction: (title: String, run: () -> Void)? {
        switch group.kind {
        case .mount:
            return (L("全部重新挂上"), repairAll)
        case .miss where group.items.first?.cause == "miss-user-invocable":
            return (L("全部改成自动"), makeAllAutomatic)
        default:
            return nil
        }
    }

    @ViewBuilder
    private func bulkButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(PressableButtonStyle())
            .font(Theme.Fonts.calloutEmphasis)
            .foregroundStyle(lead ? .white : Theme.accent)
            .padding(.horizontal, Theme.Space.s12)
            .frame(height: 28)
            .contentShape(Capsule())
            .modifier(BulkButtonSkin(lead: lead))
    }

    private func repairAll() {
        let count = store.repairMounts(directories: group.items.map(\.target))
        inbox.receipt = .init(
            text: count > 0
                ? LF("补挂了 %d 处。", count)
                : L("没有能自动补的：占位的是普通目录，得你先看一眼。"),
            failed: count == 0
        )
    }

    private func makeAllAutomatic() {
        var done = 0
        for item in group.items {
            guard let skill = inbox.skill(for: item, store: store) else { continue }
            store.makeSkillAutomatic(skill)
            done += 1
        }
        inbox.receipt = .init(text: LF("%d 个技能改回「自动」了。", done), failed: done == 0)
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
        case .approval: return ("person.badge.shield.checkmark", L("等你确认"), Theme.warning)
        case .securityCritical: return ("lock.shield", L("可能不安全"), Theme.error)
        case .securityWarning: return ("exclamationmark.triangle", L("可能不安全"), Theme.warning)
        case .mount: return ("link.badge.plus", L("装了用不了"), Theme.warning)
        case .miss: return ("bell.badge", L("叫不动"), Theme.warning)
        case .update: return ("arrow.down.circle", L("有新版本"), Theme.accent)
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
                if hit?.userInvocableOnly == true, let skill = inbox.skill(for: item, store: store) {
                    primary(L("改成自动")) { store.makeSkillAutomatic(skill) }
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


// MARK: - 技能清单占用（原「供给页」的全部实际价值）

/// 一个数字 + 一个动作。原来这需要一整页、一条 ScopeRail、三档控件、场景包
/// chips 和「上下文账单」这个词——而用户真正想知道的只有「占了多少、能不能少点」。
private struct TokenCard: View {
    @Environment(AppStore.self) private var store
    @State private var slimPresented = false

    var body: some View {
        let tokens = store.doctorReport.totalTokens
        let stale = store.staleSkills.count
        HStack(alignment: .center, spacing: Theme.Space.s16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s8) {
                    Text(LF("%d tok", tokens))
                        .font(Theme.Fonts.panelTitle)
                        .monospacedDigit()
                        .foregroundStyle(tokens > 10_000 ? Theme.warning : Theme.textPrimary)
                        .contentTransition(.numericText())
                    Text(L("估算"))
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
                Text(L("每次跟 Claude 说话，它都要先读一遍你所有技能的简介。这是那份简介的长度。"))
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                if stale > 0 {
                    Text(LF("其中 %d 个技能三个月没用过了。", stale))
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer(minLength: Theme.Space.s8)
            Button(L("挑出不用的")) { slimPresented = true }
                .buttonStyle(PressableButtonStyle())
                .font(Theme.Fonts.calloutEmphasis)
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, Theme.Space.s12)
                .frame(height: 28)
                .contentShape(Capsule())
                .glassChrome(Capsule(style: .continuous), interactive: true)
                .help(L("按使用次数排一遍，你逐个确认要不要关掉"))
        }
        .padding(Theme.Space.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .quietControl(cornerRadius: Theme.Radius.tile)
        .sheet(isPresented: $slimPresented) { SlimDraftSheet() }
    }
}
