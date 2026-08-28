import Observation
import SwiftUI
#if SWIFT_PACKAGE
import AtlasCore
#endif

// MARK: - 收件箱状态（WP-I）
//
// ADR-10：渲染时聚合。九类条目全部由 AppStore 已缓存的计算属性与既有引擎拼装，
// 这里不发起任何新采集。动作全部转发到既有机制（审阅 sheet / 处方 / 更新 diff /
// ignoreMiss），裁决记录写 inbox-state.json（core/Inbox.swift）。

// 徽标口径见 AppStore.inboxBadgeCount（未裁决且严重度 ≤1）：整理项只在页内排队，
// 不进徽标——徽标常年亮着大数字就是警报腔。聚合结果由 AppStore.inboxItems 缓存，
// 视图层不要直接调 InboxAssembler，否则每次渲染都会重跑全量聚合。

/// 聚合器：AppStore 缓存 → [InboxItem]（已裁决过滤 + 固定排序）
@MainActor
enum InboxAssembler {
    static func items(store: AppStore) -> [InboxItem] {
        var out: [InboxItem] = []

        for review in PendingReviews.list() {
            out.append(InboxItem(
                kind: .approval,
                target: review.token,
                title: L("有个技能等你点头才装"),
                detail: LF("会话里的 agent 想装 %@，但扫出了危险写法，得你看一眼再决定。", review.source.url),
                digest: review.token
            ))
        }

        // 安全命中与挂载问题是两类事项，各自成条。
        // 以前 else 分支意味着「同时有断链和关键命中」时只看得到安全那条，
        // 处理完要等下一轮扫描挂载问题才冒出来。
        for skill in store.blockingSkills {
            let critical = store.criticalFindings(for: skill)
            if let finding = critical.first {
                out.append(InboxItem(
                    kind: .securityCritical,
                    target: skill.directory,
                    title: LF("「%@」里有危险写法", skill.name),
                    detail: finding.beginnerNote,
                    digest: critical.map(\.beginnerNote).joined(),
                    skillName: skill.name,
                    cause: finding.beginnerNote
                ))
            }
            if !skill.problems.isEmpty {
                out.append(InboxItem(
                    kind: .mount,
                    target: skill.directory,
                    title: LF("「%@」装了但用不了", skill.name),
                    detail: skill.problems.first ?? L("它和 AI 软件之间的连接断了。"),
                    digest: skill.problems.joined(),
                    skillName: skill.name,
                    cause: skill.problems.first ?? "mount"
                ))
            } else if critical.isEmpty {
                out.append(InboxItem(
                    kind: .mount,
                    target: skill.directory,
                    title: LF("「%@」装了但用不了", skill.name),
                    detail: L("它和 AI 软件之间的连接断了。"),
                    digest: "unknown",
                    skillName: skill.name,
                    cause: "mount-unknown"
                ))
            }
        }

        // 安全提示（warning 级）同理：本机 118 条，排队没有意义。
        // 只有关键级（上面那段）才是必须逐条决定的待办。

        for hit in store.missHits {
            out.append(InboxItem(
                kind: .miss,
                target: hit.directory,
                title: LF("「%@」叫不动", hit.name),
                detail: hit.userInvocableOnly
                    ? LF("它被设成了「点名才用」。打 /%@ 就能用，或在技能库里改成「自动」。", hit.name)
                    : LF("最近七天有 %d 次，你说的话它本该接住却没接。改改它的自我介绍会好一些。", hit.occurrences),
                digest: "\(hit.occurrences)|\(hit.userInvocableOnly)",
                skillName: hit.name,
                cause: hit.userInvocableOnly ? "miss-user-invocable" : "miss-not-triggering"
            ))
        }

        for skill in store.updatableSkills.prefix(8) {
            out.append(InboxItem(
                kind: .update,
                target: skill.directory,
                title: LF("「%@」有新版本", skill.name),
                detail: L("更新前能先看改了什么。你自己改过的地方会保住。"),
                // digest 必须随版本变：写死常量会让「忽略一次」把这个技能
                // 今后所有新版本都静音掉（core/Inbox.swift 的内容寻址契约）
                digest: "update:\(skill.updatedAt)",
                skillName: skill.name,
                cause: "update"
            ))
        }

        // 触发重叠、介绍埋太深、改写回访三类不再进队列（ROADMAP 2.2 §1）：
        // 它们是技能自身的性质，不是「处理完就没了」的待办。数量大、无需逐条决定，
        // 混进队列的结果是既清不完又看不懂。它们作为技能行上的标记继续存在。

        return Inbox.sorted(out.filter { !InboxState.decided($0.id) })
    }
}

@MainActor
@Observable
final class InboxStore {
    struct ReceiptState: Equatable {
        var text: String
        var failed: Bool
    }

    var receipt: ReceiptState?
    var copiedOverlapID: String?

    func items(store: AppStore) -> [InboxItem] {
        store.inboxItems
    }

    /// 忽略：写裁决记录。安全关键 / 挡住使用 / 待审批拒绝忽略（core 兜底）。
    func ignore(_ item: InboxItem, store: AppStore) {
        if item.kind == .miss,
           let hit = store.missHits.first(where: { $0.directory == item.target }) {
            store.ignoreMiss(hit)
        }
        switch InboxState.decide(id: item.id, kind: item.kind, action: "ignored") {
        case .ok:
            store.invalidateInbox()
            receipt = ReceiptState(text: LF("已忽略「%@」。同一问题再变化时会重新出现。", item.title), failed: false)
        case .notIgnorable:
            receipt = ReceiptState(text: L("这一类不能忽略，得处理掉才会消失。"), failed: true)
        case .failed(let message):
            receipt = ReceiptState(text: LF("没能记下这次忽略：%@", message), failed: true)
        }
    }

    /// 审批 token 可能已被 CLI 清掉（会话取消 / 超时）。
    /// 以前这里点了没有任何反应，条目还赖在队首且不可忽略。
    func openApproval(_ item: InboxItem, store: AppStore) {
        guard PendingReviews.load(item.target) != nil else {
            InboxState.decide(id: item.id, kind: item.kind, action: "stale")
            store.invalidateInbox()
            receipt = ReceiptState(text: L("这条审批已经失效（发起它的会话可能已取消）。"), failed: false)
            return
        }
        store.openPendingReview(token: item.target)
    }

    func skill(for item: InboxItem, store: AppStore) -> Skill? {
        store.skills.first { $0.directory == item.target }
    }

    func copyOverlapPhrase(_ item: InboxItem, store: AppStore) {
        guard let pair = store.triggerOverlaps.first(where: { $0.id == item.target }) else { return }
        store.copyToPasteboard(LF("请使用 %@：<写清你的目标>", pair.first.name))
        copiedOverlapID = item.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            if self.copiedOverlapID == item.id { self.copiedOverlapID = nil }
        }
    }
}
