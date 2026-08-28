import AppKit
import Observation
import SwiftUI
#if SWIFT_PACKAGE
import AtlasCore
#endif

// MARK: - 创作页状态（WP-D）
//
// ADR-14：页面自建 store。四步线的进度落 UserDefaults（中途退出可恢复，
// PLAN WP-D 验收），scaffold 走 core 的 SkillScaffold（与 atlas new 同一份逻辑）。

@MainActor
@Observable
final class StudioStore {
    private static let draftKey = "atlasStudioDraftDir"
    private static let rankedKey = "atlasStudioRankedFirst"

    var draftName = ""
    var includeClipboard = false
    var error: String?
    var simulateText = ""
    var candidates: [TriggerCandidate] = []
    /// 第 3 步曾把草稿技能模拟到第一名（持久化，回访期还能看到绿勾）
    var rankedFirst: Bool

    /// 当前草稿技能目录名（持久化；技能被删则自动清）
    var draftDir: String? {
        didSet {
            if let draftDir {
                UserDefaults.standard.set(draftDir, forKey: Self.draftKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.draftKey)
            }
        }
    }

    init() {
        draftDir = UserDefaults.standard.string(forKey: Self.draftKey)
        rankedFirst = UserDefaults.standard.bool(forKey: Self.rankedKey)
    }

    func draftSkill(appStore: AppStore) -> Skill? {
        guard let draftDir else { return nil }
        if let skill = appStore.skills.first(where: { $0.directory == draftDir }) {
            return skill
        }
        return nil
    }

    /// 恢复校验：库里已经没有这个目录（被卸载）→ 清空步进
    func validateDraft(appStore: AppStore) {
        guard let draftDir else { return }
        let path = AtlasPaths.libraryRoot.appendingPathComponent(draftDir).path
        if !FileManager.default.fileExists(atPath: path) {
            reset()
        }
        _ = appStore
    }

    func create(appStore: AppStore) {
        let extra = includeClipboard
            ? (NSPasteboard.general.string(forType: .string)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
            : ""
        do {
            let created = try SkillScaffold.create(rawName: draftName, extra: extra, actor: "app")
            error = nil
            draftDir = created.directory
            setRankedFirst(false)
            draftName = ""
            Task { await appStore.rescan() }
        } catch let scaffoldError as SkillScaffold.ScaffoldError {
            error = scaffoldError.message
        } catch {
            self.error = error.localizedDescription
        }
    }

    func runSimulate(appStore: AppStore) {
        let atRisk = Set(appStore.doctorReport.atRisk.map { $0.skill.name })
        candidates = TriggerLab.simulate(
            phrase: simulateText,
            skills: appStore.skills,
            usage: appStore.usage,
            atRiskNames: atRisk
        )
        // 无条件按本次结果重置：只在成功时置 true 会让绿勾黏住——
        // 之后把描述改坏、草稿掉到第 3 名，界面还在说「这句话能唤到它」。
        setRankedFirst(candidates.first?.skill.directory == draftDir)
    }

    func setRankedFirst(_ value: Bool) {
        rankedFirst = value
        UserDefaults.standard.set(value, forKey: Self.rankedKey)
    }

    /// 换一个想法：只清步进状态，不动已建的技能（卸载走技能库）
    func reset() {
        draftDir = nil
        setRankedFirst(false)
        candidates = []
        simulateText = ""
        error = nil
    }
}
