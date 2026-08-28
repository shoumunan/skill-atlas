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

    /// 逐技能改档（Claude 用户级）。回执报账单前后数字；全局体检随后异步跟上。
    func applyTier(_ tier: SlimTier, to skill: Skill, appStore: AppStore) {
        guard self.tier(for: skill) != tier else { return }
        let before = billTokens(appStore: appStore)
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
            let after = billTokens(appStore: appStore)
            receipt = ReceiptState(
                text: after == before
                    ? LF("已改为「%@」，账单不变（%d tok）", tier.title, after)
                    : LF("已改为「%@」，账单 %d → %d tok", tier.title, before, after),
                failed: false
            )
            Task { await appStore.rescan() }
        } catch {
            receipt = ReceiptState(text: error.localizedDescription, failed: true)
            Oplog.append(op: "supply-tier", target: skill.directory, ok: false,
                         detail: error.localizedDescription)
        }
    }

    /// 按当前 overrides 现算 Claude 清单账单（口径 = ContextDoctor，report 内部自读 settings）
    func billTokens(appStore: AppStore) -> Int {
        let skills = appStore.skills.filter { !$0.disabled && $0.platforms.contains(AgentPlatform.claude.label) }
        let window = UserDefaults.standard.integer(forKey: "atlasContextWindow")
        let report = ContextDoctor.report(
            skills: skills,
            usage: appStore.usage,
            staleDirectories: [],
            contextWindowTokens: window > 0 ? window : 200_000
        )
        return report.totalTokens
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

    /// 移除登记只删书签；已绑定的 settings.local.json 覆盖须先在项目卡里解除绑定
    func removeProject(_ path: String, appStore: AppStore) {
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
