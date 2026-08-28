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
                title: L("来自会话的安装等待批准"),
                detail: LF("agent 请求安装 %@，含关键级安全命中，需要你审阅。", review.source.url),
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
                    title: LF("“%@”有关键级安全命中", skill.name),
                    detail: finding.beginnerNote,
                    digest: critical.map(\.beginnerNote).joined(),
                    skillName: skill.name
                ))
            }
            if !skill.problems.isEmpty {
                out.append(InboxItem(
                    kind: .mount,
                    target: skill.directory,
                    title: LF("“%@”的挂载出了问题", skill.name),
                    detail: skill.problems.first ?? L("它与 AI 软件的连接需要确认。"),
                    digest: skill.problems.joined(),
                    skillName: skill.name
                ))
            } else if critical.isEmpty {
                out.append(InboxItem(
                    kind: .mount,
                    target: skill.directory,
                    title: LF("“%@”的挂载出了问题", skill.name),
                    detail: L("它与 AI 软件的连接需要确认。"),
                    digest: "unknown",
                    skillName: skill.name
                ))
            }
        }

        for skill in store.skills where !skill.disabled && !store.hasBlockingIssue(skill) {
            let findings = store.advisoryFindings(for: skill)
            guard let first = findings.first else { continue }
            out.append(InboxItem(
                kind: .securityWarning,
                target: skill.directory,
                title: LF("“%@”有需要看一眼的写法", skill.name),
                detail: first.beginnerNote,
                digest: findings.map(\.beginnerNote).joined(),
                skillName: skill.name
            ))
        }

        for hit in store.missHits {
            out.append(InboxItem(
                kind: .miss,
                target: hit.directory,
                title: LF("“%@”该触发却没触发", hit.name),
                detail: hit.userInvocableOnly
                    ? LF("它在「仅用户可调」档。可以用 /%@ 调用，或在供给页升档。", hit.name)
                    : LF("近 7 天有 %d 次任务它该接却没接到。开处方改写描述能提升命中。", hit.occurrences),
                digest: "\(hit.occurrences)|\(hit.userInvocableOnly)",
                skillName: hit.name
            ))
        }

        for skill in store.updatableSkills {
            out.append(InboxItem(
                kind: .update,
                target: skill.directory,
                title: LF("“%@”有新版本", skill.name),
                detail: L("先看 diff 再更新；本地改动会走补丁保护。"),
                // digest 必须随版本变：写死常量会让「忽略一次」把这个技能
                // 今后所有新版本都静音掉（core/Inbox.swift 的内容寻址契约）
                digest: "update:\(skill.updatedAt)",
                skillName: skill.name
            ))
        }

        for pair in store.triggerOverlaps.prefix(8) {
            out.append(InboxItem(
                kind: .overlap,
                target: pair.id,
                title: LF("“%@”和“%@”会响应相似说法", pair.first.name, pair.second.name),
                detail: L("不必卸载任何 Skill；在调用语里写出名字即可。"),
                digest: pair.shared.joined()
            ))
        }

        var seenDiscover = Set<String>()
        let report = store.doctorReport
        func addDiscover(_ skill: Skill, _ detail: String, digest: String) {
            guard seenDiscover.insert(skill.directory).inserted, !skill.disabled else { return }
            out.append(InboxItem(
                kind: .overlong,
                target: skill.directory,
                title: LF("“%@”的介绍不好找", skill.name),
                detail: detail,
                digest: digest,
                skillName: skill.name
            ))
        }
        for entry in report.atRisk {
            addDiscover(entry.skill, L("当前技能清单较满，它的介绍可能排在可见范围之外。"), digest: "atrisk")
        }
        for entry in report.buried {
            addDiscover(entry.skill,
                        LF("关键说法写得太靠后：%@", entry.phrases.prefix(3).joined(separator: L("、"))),
                        digest: "buried:" + entry.phrases.joined())
        }
        for entry in report.overlong {
            addDiscover(entry.skill,
                        LF("介绍有 %d 个字符，后半段可能不会进入技能清单。", entry.skill.description.count),
                        digest: "overlong:\(entry.skill.description.count)")
        }

        for card in RxFollowup.due() {
            let skill = store.skills.first { $0.directory == card.directory }
            let sessions = store.usage[card.directory]?.total ?? 0
            out.append(InboxItem(
                kind: .rx,
                target: card.directory,
                title: LF("“%@”的描述改写该回访了", skill?.name ?? card.directory),
                detail: LF("写回已 %d 天，现在 %d 次会话。看看命中有没有回升。", card.ageDays, sessions),
                // 用写回时间戳而不是天数：天数每天都变，id 跟着变，忽略永远不生效
                digest: "rx:\(card.writtenAt)",
                skillName: skill?.name
            ))
        }

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
        if InboxState.decide(id: item.id, kind: item.kind, action: "ignored") {
            store.invalidateInbox()
            receipt = ReceiptState(text: LF("已忽略「%@」。同一问题再变化时会重新出现。", item.title), failed: false)
        } else {
            receipt = ReceiptState(text: L("这一类不能忽略，得处理掉才会消失。"), failed: true)
        }
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
