import AppKit
import Observation
import SwiftUI
#if SWIFT_PACKAGE
import AtlasCore
#endif

// MARK: - 供给页状态（WP-S）
//
// ADR-14：新页面自建 store，AppStore 不再长成员。这里只管供给页自己的
// 状态（当前范围、overrides 快照、回执）；写盘一律经 SupplyWriter（ADR-11），
// 场景包应用/解绑仍走 AppStore 既有确认流程（ProfileApplySheet 一套不重造）。

enum SupplyScope: Hashable {
    case platform(AgentPlatform)
    case project(String)
}

@MainActor
@Observable
final class SupplyStore {
    var scope: SupplyScope = .platform(.claude)
    /// 当前用户级 skillOverrides 快照（技能名 → 原始值），进页与每次写后刷新
    var overrides: [String: String] = [:]
    /// 最近一次写操作回执（v15 ReceiptLine 数据源）
    var receipt: ReceiptState?
    var slimPresented = false

    struct ReceiptState: Equatable {
        var text: String
        var failed: Bool
    }

    /// Claude 可以在设置里被隐藏。左轨只列可见平台，scope 却默认钉在 Claude，
    /// 结果是左轨无选中、右侧照样渲染 Claude 档位板。进页时校正一次。
    func normalizeScope(appStore: AppStore) {
        if case .platform(let platform) = scope,
           !appStore.visiblePlatforms.contains(platform),
           let fallback = appStore.visiblePlatforms.first {
            scope = .platform(fallback)
        }
    }

    func reloadOverrides() {
        let settings = (try? ProfileWriter.readSettings(at: ProfileWriter.userSettingsURL)) ?? [:]
        let raw = settings["skillOverrides"] as? [String: Any] ?? [:]
        overrides = raw.compactMapValues { $0 as? String }
    }

    func tier(for skill: Skill) -> SlimTier {
        switch overrides[skill.name] {
        case ProfileExclusion.userInvocableOnly.rawValue: return .userInvocable
        case ProfileExclusion.off.rawValue: return .off
        default: return .core
        }
    }

    /// 逐技能改档（Claude 用户级）。回执报账单前后数字。
    ///
    /// 账单一律读 `appStore.doctorReport.totalTokens`——它和页头大数字、左轨、
    /// 库页链接是同一个口径。以前这里自己再算一遍，同屏两个数字必然打架。
    func applyTier(_ tier: SlimTier, to skill: Skill, appStore: AppStore) {
        guard self.tier(for: skill) != tier else { return }
        let before = appStore.doctorReport.totalTokens
        let assignment: SupplyAssignment
        switch tier {
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
                         detail: "\(skill.name) -> \(tier.rawValue)")
            reloadOverrides()
            // 体检缓存作废并重算：不调这一下，账单和 TierDots 会停在写入前
            appStore.invalidateSupply()
            pendingReceipt = (tier.title, before)
        } catch {
            receipt = ReceiptState(text: error.localizedDescription, failed: true)
            Oplog.append(op: "supply-tier", target: skill.directory, ok: false,
                         detail: error.localizedDescription)
        }
    }

    /// 体检是异步重算的：先记下「改成了什么档、改之前多少 token」，
    /// 等新账单落地再把回执补全，避免报一个还没生效的数字。
    @ObservationIgnored private var pendingReceipt: (tierTitle: String, before: Int)?

    /// 由 SupplyPage 在 doctorReport 变化时调用
    func settleReceiptIfNeeded(appStore: AppStore) {
        guard let pending = pendingReceipt else { return }
        let after = appStore.doctorReport.totalTokens
        pendingReceipt = nil
        receipt = ReceiptState(
            text: after == pending.before
                ? LF("已改为「%@」，账单不变（%d tok）", pending.tierTitle, after)
                : LF("已改为「%@」，账单 %d → %d tok", pending.tierTitle, pending.before, after),
            failed: false
        )
    }

    // MARK: 项目登记（ADR-13：只登记与绑定，不扫描项目内技能目录）

    func projects(appStore: AppStore) -> [SupplyProject] {
        (appStore.profiles.projects ?? []).sorted { $0.addedAt > $1.addedAt }
    }

    func addProject(appStore: AppStore) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = L("登记")
        panel.message = L("选择一个项目目录，把场景包钉在它的会话上")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var list = appStore.profiles.projects ?? []
        if !list.contains(where: { $0.path == url.path }) {
            list.append(SupplyProject(path: url.path, addedAt: Int(Date().timeIntervalSince1970)))
            appStore.profiles.projects = list
            do {
                try ProfileStore.save(appStore.profiles)
                Oplog.append(op: "supply-project-add", target: url.path, ok: true, detail: "")
            } catch {
                receipt = ReceiptState(text: error.localizedDescription, failed: true)
            }
        }
        scope = .project(url.path)
    }

    /// 移除登记。若该目录还绑着场景包，先解绑再删——
    /// 否则左轨看不见它了，<项目>/.claude/settings.local.json 里的覆盖还在生效，
    /// 变成一份谁也管不到的孤儿配置。
    func removeProject(_ path: String, appStore: AppStore) {
        if let binding = appStore.profiles.bindings.first(where: { $0.directory == path }) {
            appStore.unbindDirectory(binding, silent: true)
            receipt = ReceiptState(text: L("已解除该目录的场景包绑定，并从列表移除。"), failed: false)
        }
        var list = appStore.profiles.projects ?? []
        list.removeAll { $0.path == path }
        appStore.profiles.projects = list
        do {
            try ProfileStore.save(appStore.profiles)
            Oplog.append(op: "supply-project-remove", target: path, ok: true, detail: "")
        } catch {
            receipt = ReceiptState(text: error.localizedDescription, failed: true)
        }
        if scope == .project(path) { scope = .platform(.claude) }
    }
}
