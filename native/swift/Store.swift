import AppKit
import SwiftUI

enum LaunchArgs {
    static func value(_ name: String) -> String? {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "-\(name)"), index + 1 < args.count else { return nil }
        let next = args[index + 1]
        if next.hasPrefix("-") { return nil }
        return next
    }

    static func flag(_ name: String) -> Bool {
        let args = CommandLine.arguments
        if args.contains("-\(name)") { return true }
        if let value = value(name) {
            return ["1", "YES", "yes", "true"].contains(value)
        }
        return false
    }
}

enum NavPage: String, CaseIterable, Identifiable, Hashable {
    case library, doctor, guide, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .library: return L("技能库")
        case .doctor: return L("体检")
        case .guide: return L("指南")
        case .settings: return L("设置")
        }
    }

    var symbol: String {
        switch self {
        case .library: return "books.vertical"
        case .doctor: return "heart.text.square"
        case .guide: return "text.book.closed"
        case .settings: return "gearshape"
        }
    }

    var help: String {
        switch self {
        case .library: return L("安装、挂载、更新、卸载技能（⌘1）")
        case .doctor: return L("挂载异常、预算、重叠、长期未用（⌘2）")
        case .guide: return L("三步把技能用起来（⌘3）")
        case .settings: return L("外观、本库、迁移、应用更新（⌘4）")
        }
    }
}

/// 触发词重叠对：两个技能会对同类说法同时响应
struct TriggerOverlap: Identifiable {
    var first: Skill
    var second: Skill
    var shared: [String]
    var id: String { "\(first.name)|\(second.name)" }
}

@MainActor
final class AppStore: ObservableObject {
    @Published var data: AtlasData? { didSet { dataRevision += 1 } }
    /// 体检报告缓存的失效键：技能数据或使用统计一变就 +1
    private var dataRevision = 0
    private var doctorReportCache: (revision: Int, window: Int, report: DoctorReport)?
    @Published var fatalError: String?
    @Published var scanning = false

    @Published var nav: NavPage = .library
    @Published var selectedName: String?
    @Published var search = ""
    @Published var category = "全部"
    @Published var platform = "全部"
    /// 状态筛选：全部 / 可更新 / 已停用（健康状态的入口统一收在体检页）
    @Published var stateFilter = "全部"
    @Published var sourceFilter = "全部"
    @Published var favoritesOnly = false
    @Published var favorites: Set<String>

    /// 触发词重叠（每次扫描后计算一次，不计入健康统计）
    @Published var triggerOverlaps: [TriggerOverlap] = []

    /// 使用频率统计（key = 技能目录名；后台增量索引会话日志）
    @Published var usage: [String: SkillUsage] = [:] { didSet { dataRevision += 1 } }
    @Published var usageIndexing = false
    @Published var usageProgress = 0.0
    /// 最近一次索引的统计口径（报告/帮助文案用）
    @Published var usageIndexInfo = ""

    /// 技能库排序：名称 / 使用频率
    @Published var sortOrder = "名称"
    /// 技能库分组视图（二期 F7）：不分组 / 套件 / 类别——逻辑分组，不动物理目录
    @Published var groupBy = "不分组"

    /// 阅读器 sheet 当前展示的技能（nil = 关闭）
    @Published var readerSkill: Skill?

    /// 安装技能 sheet（⌘N / 筛选行「+ 安装」/ 空状态主按钮）
    @Published var installSheetPresented = false

    /// 从 CC Switch 迁出向导
    @Published var migrationSheetPresented = false
    @Published var migrating = false
    @Published var migrationStatus = ""
    /// 清理 CC Switch 副本向导（迁移完成后回收磁盘）
    @Published var cleanupSheetPresented = false

    /// 管理操作（停用/恢复/卸载）的错误提示，弹 alert
    @Published var actionError: String?
    /// 卸载确认对话框的目标技能（nil = 关闭）
    @Published var uninstallTarget: Skill?
    /// 正在更新中的技能目录名（行内旋转指示）
    @Published var updatingDirectories: Set<String> = []
    /// 正在批量检查技能更新
    @Published var checkingSkillUpdates = false
    /// 本次检查是否用户手动发起（后台自动检查不在界面上展示进度）
    @Published var checkingInteractive = false
    /// 最近一次技能更新检查完成时间
    @Published var lastSkillUpdateCheck: Date?
    /// 体检页的上下文窗口档位（token），持久化
    @Published var contextWindowTokens: Int {
        didSet { UserDefaults.standard.set(contextWindowTokens, forKey: "atlasContextWindow") }
    }
    private var debugActionDone = false

    /// 自增即请求聚焦全局搜索框（⌘K）
    @Published var searchFocusRequest = 0

    /// 素材投递箱（二期 F5）：拖进来的文件与匹配结果
    struct DroppedMaterial: Identifiable {
        var url: URL
        var matches: [DropMatch]
        var id: String { url.path }
    }
    @Published var droppedMaterial: DroppedMaterial?
    @Published var dropTargeted = false

    func receiveDroppedFile(_ url: URL) {
        let matches = DropRules.match(fileURL: url, skills: skills)
        droppedMaterial = DroppedMaterial(url: url, matches: matches)
    }

    /// 已装技能的安全复扫结果（key = 技能目录名；后台增量，mtime 缓存）
    @Published var securityFindings: [String: [SecurityFinding]] = [:]
    private var securityCache: [String: (stamp: Date, findings: [SecurityFinding])] = [:]
    /// 已装技能的外链清单（info 级 URL，喂给存活探测）
    @Published var externalLinks: [String: [String]] = [:]
    /// 外链存活探测结果（并进安全展示）
    @Published var deadLinkFindings: [String: [SecurityFinding]] = [:]
    @Published var checkingLinks = false
    @Published var lastLinkCheck: Date?

    /// 体检/详情用的安全合并视图：静态复扫 + 外链死链
    var securityDisplay: [String: [SecurityFinding]] {
        var merged = securityFindings
        for (directory, findings) in deadLinkFindings {
            merged[directory, default: []].append(contentsOf: findings)
        }
        return merged
    }

    // MARK: - 更新审阅（G1：diff 强制审阅 + 本地补丁保护 + 回滚）
    //
    // 所有更新入口（详情按钮、更新条「全部更新」、⇧⌘U）一律先出审阅：
    // 看到 diff 才能确认；本地有改动的技能批量更新时默认跳过，只能单独审阅。
    // 确认后走 SkillActions.applyUpdate（备份 → 补丁 → pull → 重放）。

    struct UpdateReview: Identifiable, Equatable {
        var skill: Skill
        var stat: String
        var diff: String
        /// git status --porcelain 的本地改动行；非空 = 本地改过
        var dirty: [String]
        var loaded: Bool
        var id: String { skill.name }

        static func == (lhs: UpdateReview, rhs: UpdateReview) -> Bool {
            lhs.id == rhs.id && lhs.loaded == rhs.loaded
        }
    }

    /// 单技能审阅（sheet；nil = 关闭）
    @Published var updateReview: UpdateReview?
    /// 批量审阅（sheet；nil = 关闭，[] = 正在对照上游）
    @Published var batchReviews: [UpdateReview]?
    /// 回滚确认（confirmationDialog）：技能 + 将恢复到的备份名
    struct RollbackRequest: Identifiable {
        var skill: Skill
        var backupName: String
        var id: String { skill.name }
    }
    @Published var rollbackRequest: RollbackRequest?
    /// 更新/回滚完成后的结果通报（alert）
    @Published var updateNotice: String?

    private func computeReview(_ skill: Skill) async -> UpdateReview {
        let source = URL(fileURLWithPath: skill.sourcePath, isDirectory: true)
        let branch = skill.repoBranch
        let result = await Task.detached(priority: .userInitiated) {
            (SkillGit.upstreamDiff(source: source, branch: branch), SkillGit.localChanges(source: source))
        }.value
        return UpdateReview(skill: skill, stat: result.0.stat, diff: result.0.skillDiff, dirty: result.1, loaded: true)
    }

    func requestUpdate(_ skill: Skill) {
        guard skill.origin == .atlas else { return }
        updateReview = UpdateReview(skill: skill, stat: "", diff: "", dirty: [], loaded: false)
        pauseWatching()
        Task {
            let review = await computeReview(skill)
            resumeWatching()
            if updateReview?.skill.name == skill.name { updateReview = review }
        }
    }

    func confirmUpdate() {
        guard let review = updateReview, review.loaded else { return }
        updateReview = nil
        performGuardedUpdate([review.skill])
    }

    func requestUpdateAll() {
        let targets = updatableSkills.filter { $0.origin == .atlas }
        guard !targets.isEmpty else { return }
        batchReviews = []
        pauseWatching()
        Task {
            var reviews: [UpdateReview] = []
            for skill in targets {
                reviews.append(await computeReview(skill))
            }
            resumeWatching()
            if batchReviews != nil { batchReviews = reviews }
        }
    }

    func confirmBatchUpdate() {
        guard let reviews = batchReviews, !reviews.isEmpty else { return }
        batchReviews = nil
        performGuardedUpdate(reviews.filter { $0.dirty.isEmpty }.map(\.skill))
    }

    /// 带保护的更新执行：逐个 备份 → 补丁 → pull --ff-only → 重放，最后统一通报
    private func performGuardedUpdate(_ targets: [Skill]) {
        guard !targets.isEmpty else { return }
        pauseWatching()
        updatingDirectories.formUnion(targets.map(\.directory))
        Task {
            var updated = 0
            var unreplayed: [String] = []
            var failures: [String] = []
            for skill in targets {
                let result = await Task.detached(priority: .userInitiated) {
                    Result { try SkillActions.applyUpdate(skill: skill) }
                }.value
                switch result {
                case .success(let apply):
                    updated += 1
                    if apply.patchFile != nil && !apply.replayed { unreplayed.append(skill.name) }
                case .failure(let error):
                    failures.append("\(skill.name)：\(error.localizedDescription)")
                }
                updatingDirectories.remove(skill.directory)
            }
            resumeWatching()
            var lines: [String] = []
            if updated > 0 { lines.append(LF("%d 个技能已更新；更新前快照已存入 skill-backups，可随时回滚。", updated)) }
            if !unreplayed.isEmpty {
                lines.append(LF("本地改动未能自动重放（补丁已存 skill-patches，工作区为纯上游版）：%@", unreplayed.joined(separator: "、")))
            }
            if !failures.isEmpty { lines.append(L("未完成：") + "\n" + failures.joined(separator: "\n")) }
            if !lines.isEmpty { updateNotice = lines.joined(separator: "\n\n") }
            await rescan(keepSelection: true)
            await checkSkillUpdates(interactive: false)
        }
    }

    // MARK: - 单技能试跑（三期 G3）

    /// 试跑确认（sheet）：展示能隔离什么、不能隔离什么，确认后才建目录开终端
    @Published var sandboxTarget: Skill?
    @Published var sandboxCount = 0

    func requestSandbox(_ skill: Skill) {
        sandboxTarget = skill
    }

    func confirmSandbox() {
        guard let skill = sandboxTarget else { return }
        sandboxTarget = nil
        pauseWatching()
        do {
            let plan = try SkillSandbox.run(skill: skill)
            sandboxCount = SkillSandbox.existing().count
            profileNotice = LF("已开一个只装「%@」的会话。用完在设置页可一键清理试跑目录（当前 %d 个）。",
                               skill.name, sandboxCount)
        } catch {
            actionError = error.localizedDescription
        }
        resumeWatching()
    }

    func refreshSandboxCount() {
        sandboxCount = SkillSandbox.existing().count
    }

    func clearSandboxes() {
        let cleared = SkillSandbox.clearAll()
        refreshSandboxCount()
        profileNotice = LF("已把 %d 个试跑目录移入废纸篓。", cleared)
    }

    // MARK: - 场景 Profile（三期 G8）

    @Published var profiles = ProfilesFile()
    /// 待确认的写盘计划（sheet）：nil = 无
    struct ProfileApplyRequest: Identifiable {
        var profile: AtlasProfile
        var plan: ProfileWriter.Plan
        /// nil = 用户级默认；非 nil = 绑定到该目录
        var directory: URL?
        var id: String { (directory?.path ?? "user") + profile.id }
    }
    @Published var profileRequest: ProfileApplyRequest?
    @Published var profileSheetPresented = false
    @Published var profileNotice: String?

    var activeProfile: AtlasProfile? {
        profiles.profiles.first { $0.id == profiles.activeProfileID }
    }

    func loadProfiles() {
        profiles = ProfileStore.load()
    }

    private func persistProfiles() {
        do { try ProfileStore.save(profiles) } catch { actionError = error.localizedDescription }
    }

    func upsertProfile(_ profile: AtlasProfile) {
        var copy = profile
        copy.updatedAt = Int(Date().timeIntervalSince1970)
        if let index = profiles.profiles.firstIndex(where: { $0.id == copy.id }) {
            profiles.profiles[index] = copy
        } else {
            profiles.profiles.append(copy)
        }
        persistProfiles()
    }

    func deleteProfile(_ profile: AtlasProfile) {
        profiles.profiles.removeAll { $0.id == profile.id }
        if profiles.activeProfileID == profile.id {
            // 定义没了就不该继续对用户配置生效——先撤干净再删
            revertDefaultProfile(silent: true)
        }
        for binding in profiles.bindings where binding.profileID == profile.id {
            unbindDirectory(binding, silent: true)
        }
        persistProfiles()
    }

    /// 生成写盘计划并请求确认（不落盘）
    func requestProfileApply(_ profile: AtlasProfile, directory: URL?) {
        guard updatingDirectories.isEmpty else {
            profileNotice = L("有技能正在更新，等它完成再切换场景。")
            return
        }
        let target = directory.map { ProfileWriter.projectSettingsURL(for: $0) } ?? ProfileWriter.userSettingsURL
        let plan = ProfileWriter.plan(profile: profile, skills: skills, target: target)
        profileRequest = ProfileApplyRequest(profile: profile, plan: plan, directory: directory)
    }

    /// 用户确认后真正写盘
    func confirmProfileApply() {
        guard let request = profileRequest else { return }
        profileRequest = nil
        let target = request.directory.map { ProfileWriter.projectSettingsURL(for: $0) }
            ?? ProfileWriter.userSettingsURL
        let previous: [String]
        if let directory = request.directory {
            previous = profiles.bindings.first { $0.directory == directory.path }?.appliedKeys ?? []
        } else {
            previous = profiles.activeAppliedKeys
        }
        do {
            let applied = try ProfileWriter.apply(
                profile: request.profile, skills: skills, target: target, previousKeys: previous
            )
            if let directory = request.directory {
                profiles.bindings.removeAll { $0.directory == directory.path }
                profiles.bindings.append(ProfileBinding(
                    directory: directory.path, profileID: request.profile.id,
                    boundAt: Int(Date().timeIntervalSince1970), appliedKeys: applied
                ))
                profileNotice = LF("已把「%@」绑定到 %@：%d 个技能不再进该目录会话的自动清单。原配置已备份。",
                                   request.profile.name,
                                   directory.path.replacingOccurrences(of: AtlasPaths.home.path, with: "~"),
                                   applied.count)
            } else {
                profiles.activeProfileID = request.profile.id
                profiles.activeAppliedKeys = applied
                profileNotice = LF("已把「%@」设为默认场景：%d 个技能不再进自动清单。原配置已备份。",
                                   request.profile.name, applied.count)
            }
            persistProfiles()
        } catch {
            actionError = error.localizedDescription
        }
    }

    func revertDefaultProfile(silent: Bool = false) {
        do {
            try ProfileWriter.revert(target: ProfileWriter.userSettingsURL, appliedKeys: profiles.activeAppliedKeys)
            profiles.activeProfileID = nil
            profiles.activeAppliedKeys = []
            persistProfiles()
            if !silent { profileNotice = L("已恢复默认：所有技能重新进入自动清单。") }
        } catch {
            actionError = error.localizedDescription
        }
    }

    func unbindDirectory(_ binding: ProfileBinding, silent: Bool = false) {
        let target = ProfileWriter.projectSettingsURL(for: URL(fileURLWithPath: binding.directory))
        do {
            try ProfileWriter.revert(target: target, appliedKeys: binding.appliedKeys)
            profiles.bindings.removeAll { $0.directory == binding.directory }
            persistProfiles()
            if !silent { profileNotice = L("已解除绑定，该目录恢复默认技能清单。") }
        } catch {
            actionError = error.localizedDescription
        }
    }

    // MARK: - 描述医生开药（三期 G2）

    /// 处方 sheet（nil = 关闭）
    @Published var prescription: DescriptionPrescription?

    func requestPrescription(_ skill: Skill) {
        prescription = DescriptionRx.prescribe(skill: skill)
    }

    func adoptPrescription() {
        guard let rx = prescription, !rx.noop else { return }
        prescription = nil
        do {
            try DescriptionRx.writeBack(skill: rx.skill, newDescription: rx.rewritten)
            updateNotice = LF("「%@」的描述已改写并写回 SKILL.md。git 管理的技能这算一次本地改动，更新时会走补丁保护，不会被上游覆盖。", rx.skill.name)
        } catch {
            actionError = error.localizedDescription
        }
        Task { await rescan(keepSelection: true) }
    }

    /// 疗效验证：同一句话在「原描述」与「改后描述」两个库里分别模拟，返回本技能名次（1 起；nil = 没进前 8）
    func rxRankComparison(phrase: String) -> (before: Int?, after: Int?) {
        guard let rx = prescription else { return (nil, nil) }
        let atRiskNames = Set(doctorReport.atRisk.map(\.skill.name))
        func rank(in pool: [Skill]) -> Int? {
            let ranked = TriggerLab.simulate(phrase: phrase, skills: pool, usage: usage, atRiskNames: atRiskNames)
            return ranked.firstIndex { $0.skill.name == rx.skill.name }.map { $0 + 1 }
        }
        let altered = skills.map { skill -> Skill in
            guard skill.name == rx.skill.name else { return skill }
            var copy = skill
            copy.description = rx.rewritten
            return copy
        }
        return (before: rank(in: skills), after: rank(in: altered))
    }

    func requestRollback(_ skill: Skill) {
        guard skill.origin == .atlas else { return }
        // 正在更新中的技能不能同时回滚（同目录并发写会互踩）
        guard !updatingDirectories.contains(skill.directory) else { return }
        guard let backup = SkillBackup.latest(directory: skill.directory) else {
            actionError = LF("「%@」还没有备份。备份在更新或卸载时自动生成。", skill.name)
            return
        }
        rollbackRequest = RollbackRequest(skill: skill, backupName: backup.lastPathComponent)
    }

    func confirmRollback() {
        guard let request = rollbackRequest else { return }
        rollbackRequest = nil
        pauseWatching()
        updatingDirectories.insert(request.skill.directory)
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result { try SkillActions.rollback(skill: request.skill) }
            }.value
            updatingDirectories.remove(request.skill.directory)
            resumeWatching()
            switch result {
            case .success(let name):
                updateNotice = LF("「%@」已回滚到备份 %@。回滚前的状态也拍了快照，可再次回滚。", request.skill.name, name)
            case .failure(let error):
                actionError = error.localizedDescription
            }
            await rescan(keepSelection: true)
            await checkSkillUpdates(interactive: false)
        }
    }

    /// 停用被依赖技能前的警告（F6 链路数据接管理动作）
    struct DisableWarning: Identifiable {
        var skill: Skill
        var dependents: [String]
        var id: String { skill.name }
    }
    @Published var disableWarning: DisableWarning?

    /// 停用入口统一走这里：有活跃下游依赖先警告
    func requestDisable(_ skill: Skill) {
        let dependents = ProductionChain.dependents(of: skill.directory).filter { directory in
            skills.contains { $0.directory == directory && !$0.disabled }
        }
        if dependents.isEmpty {
            setSkillDisabled(skill, disabled: true)
        } else {
            disableWarning = DisableWarning(skill: skill, dependents: dependents)
        }
    }

    /// 界面语言（设置页切换；视图树以它为 .id 整体重建，立即生效）
    @Published var uiLanguage = AppLanguage.stored
    func selectLanguage(_ language: AppLanguage) {
        AppLanguage.select(language)
        uiLanguage = language
    }

    private static let favoritesKey = "skill-atlas-favorites"
    private var keyMonitor: Any?

    init() {
        let stored = UserDefaults.standard.stringArray(forKey: Self.favoritesKey) ?? []
        favorites = Set(stored)
        let window = UserDefaults.standard.integer(forKey: "atlasContextWindow")
        contextWindowTokens = window > 0 ? window : 200_000
        let page = LaunchArgs.value("atlasPage") ?? UserDefaults.standard.string(forKey: "atlasPage")
        if let page {
            switch page {
            case "overview", "library", "updates": nav = .library
            case "health", "doctor": nav = .doctor
            case "guide", "howto": nav = .guide
            case "settings": nav = .settings
            default:
                if let target = NavPage(rawValue: page) { nav = target }
            }
        }
        // 调试钩子：-atlasInstallURL <url> 自动打开安装 sheet 并预填（验收用）
        if UserDefaults.standard.string(forKey: "atlasInstallURL") != nil {
            installSheetPresented = true
        }
        // 调试钩子：-atlasCleanup 1 启动即打开清理向导（截图/验收用）
        if LaunchArgs.flag("atlasCleanup") {
            cleanupSheetPresented = true
        }
    }

    /// 技能库页支持 ↑/↓ 移动选中项；输入框聚焦时不拦截。
    func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, self.nav == .library,
                      event.modifierFlags.intersection([.command, .option, .control]).isEmpty,
                      !(NSApp.keyWindow?.firstResponder is NSTextView) else { return event }
                switch event.keyCode {
                case 125: self.moveSelection(1); return nil
                case 126: self.moveSelection(-1); return nil
                default: return event
                }
            }
        }
    }

    func moveSelection(_ delta: Int) {
        let list = filteredSkills
        guard !list.isEmpty else { return }
        let current = list.firstIndex(where: { $0.name == selectedName }) ?? -1
        let next = min(list.count - 1, max(0, (current < 0 ? 0 : current) + delta))
        guard list[next].name != selectedName else { return }
        selectedName = list[next].name
    }

    // MARK: - 数据加载

    func rescan(keepSelection: Bool = true) async {
        guard !scanning else { return }
        scanning = true
        defer { scanning = false }
        do {
            var result = try await Task.detached(priority: .userInitiated) {
                try SkillScanner.scan()
            }.value
            // 扫描结果里 updateAvailable 默认 false；把上一轮检查的标记带过来，
            // 否则每次重扫都会丢「有新版本」状态（检查有 30 分钟节流，不会马上补回）
            let previousFlags = Dictionary(
                (data?.skills ?? []).map { ($0.directory, $0.updateAvailable) },
                uniquingKeysWith: { first, _ in first }
            )
            result.skills = result.skills.map { skill in
                var copy = skill
                copy.updateAvailable = previousFlags[skill.directory] ?? false
                return copy
            }
            data = result
            fatalError = nil
            triggerOverlaps = Self.computeTriggerOverlaps(result.skills)
            reindexUsage(for: result.skills)
            rescanSecurity(for: result.skills)
            startWatchingIfNeeded()
            runPhase2ProbesIfRequested(skills: result.skills)
            // 调试钩子：-atlasReader <技能名> 启动即打开阅读器；-atlasSelect <技能名> 启动即选中（截图用）
            if readerSkill == nil,
               let name = UserDefaults.standard.string(forKey: "atlasReader"),
               let skill = result.skills.first(where: { $0.name == name }) {
                select(skill.name)
                readerSkill = skill
            }
            if let name = LaunchArgs.value("atlasSelect") ?? UserDefaults.standard.string(forKey: "atlasSelect"),
               result.skills.contains(where: { $0.name == name }) {
                select(name)
            }
            // 调试钩子：-atlasAction disable/enable/adopt/uninstall* 对当前选中技能执行（验收用，只跑一次）
            if !debugActionDone,
               let action = UserDefaults.standard.string(forKey: "atlasAction"),
               let skill = selectedSkill {
                debugActionDone = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    switch action {
                    case "uninstallTrash":
                        self?.confirmUninstall(skill, trashLibrary: true)
                    case "uninstallKeep":
                        self?.confirmUninstall(skill, trashLibrary: false)
                    case "adopt":
                        self?.adoptLocalSkill(skill)
                    case "adoptAll":
                        self?.adoptAllLocalSkills()
                    default:
                        self?.setSkillDisabled(skill, disabled: action == "disable")
                    }
                    if let path = UserDefaults.standard.string(forKey: "atlasUninstallProbe") {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                            let link = AgentPlatform.claude.resolvedRoot(home: AtlasPaths.home)
                                .appendingPathComponent(skill.directory)
                            let library = AtlasPaths.libraryRoot.appendingPathComponent(skill.directory)
                            let payload: [String: Any] = [
                                "action": action,
                                "directory": skill.directory,
                                "linkExists": FileManager.default.fileExists(atPath: link.path)
                                    || !LinkTool.destination(of: link).isEmpty,
                                "linkTarget": LinkTool.destination(of: link),
                                "libraryExists": FileManager.default.fileExists(atPath: library.path),
                                "inCatalog": AtlasCatalog.load().skills[skill.directory] != nil,
                                "ccSwitchUntouched": true,
                            ]
                            if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]),
                               let text = String(data: data, encoding: .utf8) {
                                try? text.write(toFile: path, atomically: true, encoding: .utf8)
                            }
                            self?.quitIfRequested()
                        }
                    }
                }
            }
            // 默认不选中任何技能（详情栏保持收起，等用户点了再展开）
            let existing = keepSelection ? result.skills.first(where: { $0.name == selectedName }) : nil
            selectedName = existing?.name
            loadProfiles()
            // 老仓库是在这些文件出现之前 init 的，补齐忽略项防止 settings 备份、
            // 事件日志、沙箱被 F8 的快照提交推到远端
            try? GitSync.ensureIgnored()
            offerMigrationIfNeeded()
            writeOfferProbe()
            writeDoctorProbe()
            if UserDefaults.standard.bool(forKey: "atlasMigrate") {
                UserDefaults.standard.set(false, forKey: "atlasMigrate")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                    self?.performMigration()
                }
            } else if UserDefaults.standard.bool(forKey: "atlasRollback") {
                UserDefaults.standard.set(false, forKey: "atlasRollback")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                    self?.rollbackMigration()
                }
            }
            if !LaunchArgs.flag("atlasQuit") {
                Task { await self.checkSkillUpdates(interactive: false) }
            }
            if let raw = UserDefaults.standard.string(forKey: "atlasToggle"),
               let platform = AgentPlatform(rawValue: raw) {
                UserDefaults.standard.removeObject(forKey: "atlasToggle")
                let enabled = !UserDefaults.standard.bool(forKey: "atlasToggleOff")
                let targetName = UserDefaults.standard.string(forKey: "atlasSelect") ?? ""
                let skill = result.skills.first(where: { $0.name == targetName || $0.directory == targetName })
                if let skill {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                        self?.setPlatform(skill, platform: platform, enabled: enabled)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                            if let path = UserDefaults.standard.string(forKey: "atlasToggleProbe") {
                                let link = platform.resolvedRoot(home: AtlasPaths.home).appendingPathComponent(skill.directory)
                                let payload: [String: Any] = [
                                    "directory": skill.directory,
                                    "platform": platform.rawValue,
                                    "enabled": enabled,
                                    "link": LinkTool.destination(of: link),
                                ]
                                if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]),
                                   let text = String(data: data, encoding: .utf8) {
                                    try? text.write(toFile: path, atomically: true, encoding: .utf8)
                                }
                            }
                            self?.quitIfRequested()
                        }
                    }
                }
            }
            if UserDefaults.standard.bool(forKey: "atlasCheckSkillUpdates") {
                UserDefaults.standard.set(false, forKey: "atlasCheckSkillUpdates")
                Task {
                    await self.checkSkillUpdates(interactive: false)
                    if let path = UserDefaults.standard.string(forKey: "atlasGitProbe") {
                        let updatable = (self.data?.skills ?? []).filter(\.updateAvailable).map(\.directory)
                        let payload: [String: Any] = [
                            "checked": (self.data?.skills ?? []).filter { $0.origin == .atlas }.count,
                            "updatable": updatable,
                        ]
                        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]),
                           let text = String(data: data, encoding: .utf8) {
                            try? text.write(toFile: path, atomically: true, encoding: .utf8)
                        }
                    }
                    self.quitIfRequested()
                }
            }
            // G1 更新审阅三 probe（-atlasProbeOut 落盘；配 -atlasQuit 用于无头验收）
            if let target = UserDefaults.standard.string(forKey: "atlasUpdateReviewProbe") {
                UserDefaults.standard.removeObject(forKey: "atlasUpdateReviewProbe")
                let skill = result.skills.first(where: { $0.name == target || $0.directory == target })
                pauseWatching()
                Task {
                    var payload: [String: Any] = ["target": target]
                    if let skill {
                        let review = await self.computeReview(skill)
                        payload["directory"] = skill.directory
                        payload["stat"] = review.stat
                        payload["diff"] = review.diff
                        payload["dirty"] = review.dirty
                    } else {
                        payload["error"] = "not found"
                    }
                    self.resumeWatching()
                    self.writeProbeJSON(payload)
                    self.quitIfRequested()
                }
            }
            if let target = UserDefaults.standard.string(forKey: "atlasApplyUpdateProbe") {
                UserDefaults.standard.removeObject(forKey: "atlasApplyUpdateProbe")
                let skill = result.skills.first(where: { $0.name == target || $0.directory == target })
                pauseWatching()
                Task {
                    var payload: [String: Any] = ["target": target]
                    if let skill {
                        let outcome = await Task.detached(priority: .userInitiated) {
                            Result { try SkillActions.applyUpdate(skill: skill) }
                        }.value
                        switch outcome {
                        case .success(let apply):
                            payload["directory"] = skill.directory
                            payload["backup"] = apply.backupName
                            payload["patch"] = apply.patchFile ?? ""
                            payload["replayed"] = apply.replayed
                            payload["dirty"] = apply.dirtyFiles
                        case .failure(let error):
                            payload["error"] = error.localizedDescription
                        }
                    } else {
                        payload["error"] = "not found"
                    }
                    self.resumeWatching()
                    self.writeProbeJSON(payload)
                    self.quitIfRequested()
                }
            }
            // G3 单技能试跑 probe：建沙箱并落盘计划，不开终端
            if let target = UserDefaults.standard.string(forKey: "atlasSandboxProbe") {
                UserDefaults.standard.removeObject(forKey: "atlasSandboxProbe")
                let path = UserDefaults.standard.string(forKey: "atlasProbeOut")
                if let skill = result.skills.first(where: { $0.name == target || $0.directory == target }) {
                    do {
                        _ = try SkillSandbox.run(skill: skill, dryRunProbe: path)
                    } catch {
                        writeProbeJSON(["target": target, "error": error.localizedDescription])
                    }
                } else {
                    writeProbeJSON(["target": target, "error": "not found"])
                }
                quitIfRequested()
            }
            // G8 Profile probe：create|apply|bind|unbind|status
            // -atlasProfileName <名> -atlasProfileMembers <逗号分隔目录> -atlasProfileDir <目录>
            if let action = UserDefaults.standard.string(forKey: "atlasProfileProbe") {
                UserDefaults.standard.removeObject(forKey: "atlasProfileProbe")
                loadProfiles()
                var payload: [String: Any] = ["action": action]
                let name = UserDefaults.standard.string(forKey: "atlasProfileName") ?? "验收场景"
                let dirPath = UserDefaults.standard.string(forKey: "atlasProfileDir")
                do {
                    switch action {
                    case "create":
                        var profile = AtlasProfile.new(name: name)
                        let raw = UserDefaults.standard.string(forKey: "atlasProfileMembers") ?? ""
                        profile.members = raw.split(separator: ",").map {
                            $0.trimmingCharacters(in: .whitespaces)
                        }.filter { !$0.isEmpty }
                        upsertProfile(profile)
                        payload["profileID"] = profile.id
                        payload["members"] = profile.members
                    case "apply", "bind":
                        guard let profile = profiles.profiles.first(where: { $0.name == name }) else {
                            throw AtlasError("找不到 Profile：\(name)")
                        }
                        let directory = (action == "bind" && dirPath != nil)
                            ? URL(fileURLWithPath: dirPath!) : nil
                        let target = directory.map { ProfileWriter.projectSettingsURL(for: $0) }
                            ?? ProfileWriter.userSettingsURL
                        let plan = ProfileWriter.plan(profile: profile, skills: skills, target: target)
                        payload["target"] = target.path
                        payload["excluded"] = plan.excluded
                        payload["kept"] = plan.kept
                        payload["conflicts"] = plan.conflicts
                        payload["foreignKeys"] = plan.foreignKeys
                        profileRequest = ProfileApplyRequest(profile: profile, plan: plan, directory: directory)
                        confirmProfileApply()
                        payload["written"] = (try? ProfileWriter.readSettings(at: target))?["skillOverrides"] as? [String: Any] ?? [:]
                    case "unbind":
                        if let dirPath, let binding = profiles.bindings.first(where: { $0.directory == dirPath }) {
                            unbindDirectory(binding, silent: true)
                            payload["unbound"] = dirPath
                        } else {
                            revertDefaultProfile(silent: true)
                            payload["unbound"] = "user"
                        }
                    default:
                        break
                    }
                    payload["profiles"] = profiles.profiles.map(\.name)
                    payload["activeProfile"] = activeProfile?.name ?? ""
                    payload["bindings"] = profiles.bindings.map(\.directory)
                    if let error = actionError { payload["error"] = error }
                } catch {
                    payload["error"] = error.localizedDescription
                }
                writeProbeJSON(payload)
                quitIfRequested()
            }
            // G5 Hook 遥测 probe：install / uninstall / status
            if let action = UserDefaults.standard.string(forKey: "atlasHookProbe") {
                UserDefaults.standard.removeObject(forKey: "atlasHookProbe")
                var payload: [String: Any] = ["action": action]
                do {
                    switch action {
                    case "install": try HookTelemetry.install()
                    case "uninstall": try HookTelemetry.uninstall()
                    default: break
                    }
                    payload["installed"] = HookTelemetry.installed()
                    payload["script"] = HookTelemetry.scriptURL.path
                    payload["settings"] = HookTelemetry.settingsURL.path
                    payload["events"] = HookTelemetry.totalEvents
                } catch {
                    payload["error"] = error.localizedDescription
                }
                writeProbeJSON(payload)
                quitIfRequested()
            }
            // G2 描述开药两 probe：Rx = 只出处方；RxApply = 出处方并写回
            for (key, apply) in [("atlasRxProbe", false), ("atlasRxApplyProbe", true)] {
                guard let target = UserDefaults.standard.string(forKey: key) else { continue }
                UserDefaults.standard.removeObject(forKey: key)
                let skill = result.skills.first(where: { $0.name == target || $0.directory == target })
                var payload: [String: Any] = ["target": target]
                if let skill {
                    let rx = DescriptionRx.prescribe(skill: skill)
                    payload["directory"] = skill.directory
                    payload["noop"] = rx.noop
                    payload["rewritten"] = rx.rewritten
                    payload["moves"] = rx.moves
                    payload["beforeBuried"] = rx.beforeBuried
                    payload["afterBuried"] = rx.afterBuried
                    if apply, !rx.noop {
                        do {
                            try DescriptionRx.writeBack(skill: skill, newDescription: rx.rewritten)
                            payload["applied"] = true
                        } catch {
                            payload["applied"] = false
                            payload["error"] = error.localizedDescription
                        }
                    }
                } else {
                    payload["error"] = "not found"
                }
                writeProbeJSON(payload)
                quitIfRequested()
            }
            if let target = UserDefaults.standard.string(forKey: "atlasRollbackProbe") {
                UserDefaults.standard.removeObject(forKey: "atlasRollbackProbe")
                let skill = result.skills.first(where: { $0.name == target || $0.directory == target })
                pauseWatching()
                Task {
                    var payload: [String: Any] = ["target": target]
                    if let skill {
                        let outcome = await Task.detached(priority: .userInitiated) {
                            Result { try SkillActions.rollback(skill: skill) }
                        }.value
                        switch outcome {
                        case .success(let name):
                            payload["directory"] = skill.directory
                            payload["restored"] = name
                        case .failure(let error):
                            payload["error"] = error.localizedDescription
                        }
                    } else {
                        payload["error"] = "not found"
                    }
                    self.resumeWatching()
                    self.writeProbeJSON(payload)
                    self.quitIfRequested()
                }
            }
        } catch {
            fatalError = error.localizedDescription
        }
    }

    // MARK: - 派生数据

    var skills: [Skill] { data?.skills ?? [] }

    var categories: [String] {
        var seen: [String] = []
        for skill in skills where !seen.contains(skill.category) {
            seen.append(skill.category)
        }
        return seen
    }

    var filteredSkills: [Skill] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        // 搜索并入任务推荐：除关键词直配外，扩展中文任务别名（搜「做个PPT」能命中 pptx）
        var queryTokens: [String] = []
        if !query.isEmpty {
            queryTokens = [query]
            for (key, values) in Rules.recommendAliases where query.contains(key) {
                queryTokens.append(contentsOf: values.map { $0.lowercased() })
            }
        }
        let matched = skills.filter { skill in
            if !queryTokens.isEmpty && !queryTokens.contains(where: { skill.searchText.contains($0) }) { return false }
            if category != "全部" && skill.category != category { return false }
            switch stateFilter {
            case "可更新": if !skill.updateAvailable || skill.disabled { return false }
            case "已停用": if !skill.disabled { return false }
            default: break
            }
            if platform != "全部" && !skill.platforms.contains(platform) { return false }
            if sourceFilter != "全部" && skill.origin.label != sourceFilter { return false }
            if favoritesOnly && !favorites.contains(skill.name) { return false }
            return true
        }
        switch sortOrder {
        case "使用频率":
            return matched.sorted {
                let a = usage[$0.directory]?.total ?? 0
                let b = usage[$1.directory]?.total ?? 0
                return a != b ? a > b : $0.name.lowercased() < $1.name.lowercased()
            }
        case "最近使用":
            return matched.sorted {
                let a = usage[$0.directory]?.lastUsed ?? .distantPast
                let b = usage[$1.directory]?.lastUsed ?? .distantPast
                return a != b ? a > b : $0.name.lowercased() < $1.name.lowercased()
            }
        default:
            return matched
        }
    }

    /// F7 分组：返回 (组名, 组内技能)；分组内沿用当前排序
    func groupedSkills(_ list: [Skill]) -> [(String, [Skill])] {
        switch groupBy {
        case "套件":
            var prefixCount: [String: Int] = [:]
            for skill in list {
                if let prefix = skill.directory.split(separator: "-").first.map(String.init) {
                    prefixCount[prefix, default: 0] += 1
                }
            }
            var groups: [String: [Skill]] = [:]
            for skill in list {
                let prefix = skill.directory.split(separator: "-").first.map(String.init) ?? skill.directory
                let key = (prefixCount[prefix] ?? 0) >= 3 ? LF("%@ 套件", prefix) : L("独立技能")
                groups[key, default: []].append(skill)
            }
            let standalone = L("独立技能")
            return groups.sorted {
                if $0.key == standalone { return false }
                if $1.key == standalone { return true }
                return $0.value.count != $1.value.count ? $0.value.count > $1.value.count : $0.key < $1.key
            }
        case "类别":
            var groups: [String: [Skill]] = [:]
            for skill in list {
                groups[skill.category, default: []].append(skill)
            }
            return groups.sorted { $0.value.count != $1.value.count ? $0.value.count > $1.value.count : $0.key < $1.key }
        default:
            return [("", list)]
        }
    }

    var selectedSkill: Skill? {
        guard let selectedName else { return nil }
        return skills.first(where: { $0.name == selectedName })
    }

    var hasActiveFilters: Bool {
        category != "全部" || platform != "全部" || stateFilter != "全部" || sourceFilter != "全部" || !search.isEmpty
    }

    // MARK: - 动作

    func toggleFavorite(_ name: String) {
        if favorites.contains(name) {
            favorites.remove(name)
        } else {
            favorites.insert(name)
        }
        UserDefaults.standard.set(Array(favorites).sorted(), forKey: Self.favoritesKey)
    }

    func select(_ name: String) {
        selectedName = name
    }

    func jumpToCategory(_ value: String) {
        clearFilters()
        category = value
        nav = .library
    }

    /// 技能库顶部更新条 →「只看可更新」
    func jumpToUpdatable() {
        clearFilters()
        stateFilter = "可更新"
        nav = .library
    }

    /// 侧栏角标 & 更新页：可更新的技能
    var updatableSkills: [Skill] {
        skills.filter { $0.updateAvailable && !$0.disabled }
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    /// 侧栏角标：异常数；超 listing 预算时再加 1，避免把上百个「有丢弃风险」全堆在角标
    var doctorBadgeCount: Int {
        let errors = skills.filter { $0.health == .error && !$0.disabled }.count
        return errors + (doctorReport.overBudget ? 1 : 0)
    }

    /// UI 展示的平台：Claude / Codex / Gemini / Grok / WorkBuddy。
    /// OpenClaw、OpenCode、Hermes 只保留数据兼容——扫描、挂载、安全扫描照常，
    /// 已建的软链不动，但不占界面位置（用不上的平台摆在那里只是噪音）。
    /// 日后要放出来，把它加回这个数组即可，其余代码不用动。
    var visiblePlatforms: [AgentPlatform] {
        [.claude, .codex, .gemini, .grokbuild, .workbuddy]
    }

    /// 体检报告（预算模拟 + 超长描述 + 可回收）。
    /// 按 (dataRevision, 预算窗口) 记忆化——侧栏角标/页副标每次渲染都读它，
    /// 不缓存等于每帧对 143 条描述跑一遍 token 估算 + 触发词正则。
    var doctorReport: DoctorReport {
        if let cache = doctorReportCache,
           cache.revision == dataRevision, cache.window == contextWindowTokens {
            return cache.report
        }
        let report = ContextDoctor.report(
            skills: skills,
            usage: usage,
            staleDirectories: Set(staleSkills.map(\.directory)),
            contextWindowTokens: contextWindowTokens
        )
        doctorReportCache = (dataRevision, contextWindowTokens, report)
        return report
    }

    func clearFilters() {
        category = "全部"
        platform = "全部"
        stateFilter = "全部"
        sourceFilter = "全部"
        search = ""
    }

    func openFolder(_ path: String) {
        let url = URL(fileURLWithPath: path)
        // 白名单：所有扫描根（CC Switch 源目录 + Claude/Codex 平台根目录）内的路径才允许打开
        let roots = [
            SkillScanner.sourceRoot,
            SkillScanner.claudeRoot,
            SkillScanner.codexRoot,
            AtlasPaths.root,
            AtlasPaths.libraryRoot,
            AtlasPaths.backupsRoot,
            AgentPlatform.grokbuild.root(home: SkillScanner.home),
            AgentPlatform.gemini.root(home: SkillScanner.home),
            AgentPlatform.opencode.root(home: SkillScanner.home),
            AgentPlatform.hermes.root(home: SkillScanner.home),
            AgentPlatform.workbuddy.root(home: SkillScanner.home),
            AgentPlatform.openclaw.root(home: SkillScanner.home),
        ]
            .map { $0.resolvingSymlinksInPath().standardizedFileURL.path }
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL.path
        guard roots.contains(where: { resolved == $0 || resolved.hasPrefix($0 + "/") }) else { return }
        NSWorkspace.shared.open(url)
    }

    func copyToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    // MARK: - 调用语与指南素材

    /// 一键复制的调用语：「请使用 <name>：<第一条示例的任务部分>」，取不出任务时用通用模板
    static func callPhrase(for skill: Skill) -> String {
        if let first = skill.examplePrompts.first {
            if first.hasPrefix("请使用") {
                if let colon = first.range(of: "：") {
                    return LF("请使用 %@：%@", skill.name, String(first[colon.upperBound...]))
                }
            } else {
                return LF("请使用 %@：%@", skill.name, first)
            }
        }
        return LF("请使用 %@ 帮我完成：<描述你的目标>", skill.name)
    }

    /// 工具栏页标题下的活副文案（随数据变化）
    var pageSubtitle: String {
        guard let data else { return L("正在扫描…") }
        let summary = data.summary
        switch nav {
        case .library:
            if hasActiveFilters || favoritesOnly {
                return LF("筛选出 %d / %d 项", filteredSkills.count, summary.total)
            }
            let updates = updatableSkills.count
            return updates > 0
                ? LF("%d 个技能 · %d 个有新版本", summary.total, updates)
                : LF("%d 个技能 · 随处按 ⌥⌘K 快速搜索", summary.total)
        case .doctor:
            let report = doctorReport
            if report.overBudget {
                return LF("清单超预算，%d 个技能的描述有被丢弃风险", report.atRisk.count)
            }
            let issues = doctorBadgeCount
            return issues > 0 ? LF("%d 项异常需要修复", issues) : L("预算余量充足")
        case .guide:
            return LF("%d 个技能，用过 %d 个", summary.total, usedSkillCount)
        case .settings:
            if data.summary.migrated {
                return LF("已迁入 %d 个技能", data.summary.atlasCount)
            }
            if data.summary.hasCCSwitch {
                return L("发现可迁入的技能")
            }
            return L("外观、本库、迁移、应用更新")
        }
    }

    /// 有使用记录的技能数（怎么用页教材）
    var usedSkillCount: Int {
        skills.filter { (usage[$0.directory]?.total ?? 0) > 0 }.count
    }

    /// 当前选中，否则使用最多，否则库里第一个（怎么用页卡片）
    var featuredSkill: Skill? {
        if let selected = selectedSkill { return selected }
        return skills.max {
            let a = usage[$0.directory]?.total ?? 0
            let b = usage[$1.directory]?.total ?? 0
            return a != b ? a < b : $0.name.lowercased() > $1.name.lowercased()
        }
    }

    /// 直接描述任务的示例（不点名技能）
    static func autoMatchPhrase(for skill: Skill) -> String {
        if let first = skill.examplePrompts.first {
            if first.hasPrefix("请使用"), let colon = first.range(of: "：") {
                return String(first[colon.upperBound...])
            }
            return first
        }
        return skill.whenToUse
    }

    // MARK: - 目录自动刷新（FSEvents + 2 秒防抖）

    private let watcher = DirectoryWatcher()
    private var watcherStarted = false
    private var refreshDebounce: Task<Void, Never>?

    private func startWatchingIfNeeded() {
        guard !watcherStarted else { return }
        watcherStarted = true
        // 注意：不能监听 ~/.skill-atlas 根目录——usage-index.json（后台使用统计缓存）
        // 就写在根下，监听它会形成 扫描→写缓存→FSEvents→再扫描 的自触发循环
        //（表现为右上角刷新箭头转个不停）。只监听技能目录与 CC Switch DB。
        let paths = Set([
            SkillScanner.claudeRoot.resolvingSymlinksInPath().path,
            SkillScanner.codexRoot.resolvingSymlinksInPath().path,
            SkillScanner.sourceRoot.resolvingSymlinksInPath().path,
            SkillScanner.databaseURL.path,
            AtlasPaths.libraryRoot.path,
            AgentPlatform.grokbuild.root(home: SkillScanner.home).path,
            AgentPlatform.gemini.root(home: SkillScanner.home).path,
            AgentPlatform.opencode.root(home: SkillScanner.home).path,
            AgentPlatform.hermes.root(home: SkillScanner.home).path,
            AgentPlatform.workbuddy.root(home: SkillScanner.home).path,
            AgentPlatform.openclaw.root(home: SkillScanner.home).path,
        ])
        watcher.start(paths: Array(paths)) { [weak self] in
            MainActor.assumeIsolated { self?.scheduleAutoRescan() }
        }
    }

    private func scheduleAutoRescan() {
        refreshDebounce?.cancel()
        refreshDebounce = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            await self?.rescan(keepSelection: true)
        }
    }

    /// 自家写操作（停用/恢复）期间暂停监听，避免自触发
    func pauseWatching() { watcher.pause() }
    func resumeWatching() {
        // 写操作产生的 FSEvents 可能延迟送达，稍等再恢复
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.watcher.resume()
        }
    }

    // MARK: - 本地 / Atlas 技能停用/恢复

    /// Atlas 库：移入 ~/.skill-atlas/skills/.disabled/
    /// 未迁入的本地直装：仍移入所在根的 .disabled/
    /// CC Switch 来源：不写
    func setSkillDisabled(_ skill: Skill, disabled: Bool) {
        guard skill.disabled != disabled else { return }
        if skill.origin == .ccSwitch { return }
        pauseWatching()
        do {
            if skill.origin == .atlas {
                try SkillActions.setDisabled(directory: skill.directory, disabled: disabled)
            } else {
                try disableLocalDirectory(skill, disabled: disabled)
            }
        } catch {
            actionError = error.localizedDescription
        }
        resumeWatching()
        Task { await rescan(keepSelection: true) }
    }

    private func disableLocalDirectory(_ skill: Skill, disabled: Bool) throws {
        let fileManager = FileManager.default
        let source = URL(fileURLWithPath: skill.sourcePath, isDirectory: true)
        let target: URL = disabled
            ? source.deletingLastPathComponent()
                .appendingPathComponent(".disabled")
                .appendingPathComponent(source.lastPathComponent)
            : source.deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent(source.lastPathComponent)
        guard !fileManager.fileExists(atPath: target.path) else {
            throw AtlasError(disabled
                ? LF("停用失败：.disabled/ 里已存在同名目录「%@」。", source.lastPathComponent)
                : LF("恢复失败：原位置已存在同名目录「%@」，不会覆盖。", source.lastPathComponent))
        }
        try fileManager.createDirectory(
            at: target.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.moveItem(at: source, to: target)
    }

    func setPlatform(_ skill: Skill, platform: AgentPlatform, enabled: Bool) {
        guard skill.origin == .atlas else { return }
        pauseWatching()
        do {
            try SkillActions.setPlatform(directory: skill.directory, platform: platform, enabled: enabled)
        } catch {
            actionError = error.localizedDescription
        }
        resumeWatching()
        Task { await rescan(keepSelection: true) }
    }

    /// 收编本地直装：拷入本库、原散装目录替换成指向库的软链。
    /// 重扫后 origin 变 atlas，详情页原地解锁平台 logo 开关。
    func adoptLocalSkill(_ skill: Skill) {
        guard skill.origin == .local, !skill.disabled else { return }
        pauseWatching()
        do {
            try SkillActions.adoptLocal(skill: skill)
        } catch {
            actionError = error.localizedDescription
        }
        resumeWatching()
        Task { await rescan(keepSelection: true) }
    }

    /// 可收编的本地直装（收编条的数据源）
    var adoptableSkills: [Skill] {
        skills.filter { $0.origin == .local && !$0.disabled }
    }

    /// 收编条 →「只看本地安装」
    func jumpToLocalSkills() {
        clearFilters()
        sourceFilter = SkillOrigin.local.label
        nav = .library
    }

    /// 一键收编全部本地直装（收编条入口）。逐个执行，全部完成只重扫一次；
    /// 失败的（同名冲突等）聚合报错，不中断其余。
    func adoptAllLocalSkills() {
        let targets = adoptableSkills
        guard !targets.isEmpty else { return }
        pauseWatching()
        var failures: [String] = []
        for skill in targets {
            do {
                try SkillActions.adoptLocal(skill: skill)
            } catch {
                failures.append(skill.name)
            }
        }
        if !failures.isEmpty {
            actionError = LF("有 %d 个未能收编：%@", failures.count, failures.prefix(3).joined(separator: "、") + (failures.count > 3 ? "…" : ""))
        }
        resumeWatching()
        Task { await rescan(keepSelection: true) }
    }

    var canMigrate: Bool {
        (data?.summary.hasCCSwitch ?? FileManager.default.fileExists(atPath: SkillScanner.databaseURL.path))
            && !(data?.summary.migrated ?? AtlasCatalog.load().migratedFromCCSwitch)
    }

    var canRollback: Bool { SkillMigrator.canRollback() }

    private var suppressMigrationOffer = false

    func offerMigrationIfNeeded() {
        if LaunchArgs.flag("atlasForceMigrate") {
            migrationSheetPresented = true
            return
        }
        if suppressMigrationOffer { return }
        if UserDefaults.standard.bool(forKey: "atlasRollback") { return }
        if UserDefaults.standard.bool(forKey: "atlasQuit") && UserDefaults.standard.bool(forKey: "atlasMigrate") {
            // 探针模式由 performMigration 接手，不弹向导
        }
        let hasCC = data?.summary.hasCCSwitch == true
        if UserDefaults.standard.bool(forKey: "atlasShowMigrate") {
            migrationSheetPresented = true
            return
        }
        if SkillMigrator.shouldOffer(hasCCSwitch: hasCC) {
            migrationSheetPresented = true
        }
    }

    func skipMigration() {
        try? SkillMigrator.skip()
        migrationSheetPresented = false
    }

    func performMigration() {
        guard !migrating else { return }
        migrating = true
        migrationStatus = "准备迁移…"
        migrationSheetPresented = true
        pauseWatching()
        Self.progressBridge = { [weak self] message in
            self?.migrationStatus = message
        }
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try SkillMigrator.migrate { message in
                        Task { @MainActor in
                            AppStore.progressBridge?(message)
                        }
                    }
                }.value
                migrating = false
                migrationStatus = "完成"
                migrationSheetPresented = false
                resumeWatching()
                await rescan(keepSelection: true)
                writeMigrationProbe(ok: true, error: nil)
                quitIfRequested()
            } catch {
                migrating = false
                migrationStatus = ""
                actionError = error.localizedDescription
                writeMigrationProbe(ok: false, error: error.localizedDescription)
                resumeWatching()
                quitIfRequested()
            }
        }
    }

    func rollbackMigration() {
        suppressMigrationOffer = true
        migrationSheetPresented = false
        pauseWatching()
        do {
            try SkillMigrator.rollback()
        } catch {
            actionError = error.localizedDescription
        }
        resumeWatching()
        Task {
            await rescan(keepSelection: true)
            quitIfRequested()
        }
    }

    private static var progressBridge: ((String) -> Void)?

    private func writeDoctorProbe() {
        guard let path = UserDefaults.standard.string(forKey: "atlasDoctorProbe"), !path.isEmpty else { return }
        let report = doctorReport
        let object: [String: Any] = [
            "entries": report.entries.count,
            "budgetTokens": report.budgetTokens,
            "totalTokens": report.totalTokens,
            "overBudget": report.overBudget,
            "atRisk": report.atRisk.count,
            "verbose": report.verbose.count,
            "overlong": report.overlong.count,
            "reclaimableTokens": report.reclaimableTokens,
            "perEntryCap": ContextDoctor.perEntryCap,
            "window": contextWindowTokens,
        ]
        if let payload = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
           let text = String(data: payload, encoding: .utf8) {
            try? text.write(toFile: path, atomically: true, encoding: .utf8)
        }
        quitIfRequested()
    }

    private func writeOfferProbe() {
        guard let path = UserDefaults.standard.string(forKey: "atlasOfferProbe"), !path.isEmpty else { return }
        let hasCC = data?.summary.hasCCSwitch == true
        let catalog = AtlasCatalog.load()
        let object: [String: Any] = [
            "offered": SkillMigrator.shouldOffer(hasCCSwitch: hasCC),
            "hasCCSwitch": hasCC,
            "migrated": data?.summary.migrated ?? catalog.migratedFromCCSwitch,
            "skipped": catalog.migrationSkipped,
            "atlasCount": data?.summary.atlasCount ?? 0,
            "ccSwitchCount": data?.summary.ccSwitchCount ?? 0,
            "presented": migrationSheetPresented,
        ]
        if let payload = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
           let text = String(data: payload, encoding: .utf8) {
            try? text.write(toFile: path, atomically: true, encoding: .utf8)
        }
        if LaunchArgs.flag("atlasQuit") {
            quitIfRequested()
        }
    }

    private func writeMigrationProbe(ok: Bool, error: String?) {
        guard let path = UserDefaults.standard.string(forKey: "atlasMigrateProbe"), !path.isEmpty else { return }
        var object: [String: Any] = [
            "ok": ok,
            "atlasCount": data?.summary.atlasCount ?? AtlasCatalog.load().skills.count,
            "migrated": AtlasCatalog.load().migratedFromCCSwitch,
            "log": AtlasPaths.migrationLog.path,
            "library": AtlasPaths.libraryRoot.path,
        ]
        if let error { object["error"] = error }
        let hotspot = AgentPlatform.claude.resolvedRoot(home: AtlasPaths.home)
            .appendingPathComponent("hotspot")
        object["hotspotLink"] = LinkTool.destination(of: hotspot)
        if let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            try? text.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    private func quitIfRequested() {
        if LaunchArgs.flag("atlasQuit") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                exit(0)
            }
        }
    }

    /// probe 统一落盘：写到 -atlasProbeOut 指定的路径（无则不写）
    private func writeProbeJSON(_ payload: [String: Any]) {
        guard let path = UserDefaults.standard.string(forKey: "atlasProbeOut"), !path.isEmpty else { return }
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            try? text.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    func checkSkillUpdates(interactive: Bool) async {
        guard !checkingSkillUpdates else { return }
        // 后台自动检查节流：30 分钟内不重复跑（手动「重新检查」不受限）。
        // 没有节流时会形成自触发循环：git fetch 写 .git → FSEvents → rescan → 又 fetch。
        if !interactive, let last = lastSkillUpdateCheck,
           Date().timeIntervalSince(last) < 1800 { return }
        let targets = skills.filter { $0.origin == .atlas && !$0.disabled }
        guard !targets.isEmpty else {
            if interactive { actionError = L("没有可检查更新的 Skill Atlas 技能。") }
            return
        }
        checkingSkillUpdates = true
        checkingInteractive = interactive
        // fetch 会写各技能的 .git，检查全程暂停 FSEvents，避免自触发重扫
        pauseWatching()
        defer {
            checkingSkillUpdates = false
            checkingInteractive = false
            lastSkillUpdateCheck = Date()
            resumeWatching()
        }
        let results: [String: Bool] = await Task.detached(priority: .utility) {
            var map: [String: Bool] = [:]
            for skill in targets {
                let source = URL(fileURLWithPath: skill.sourcePath, isDirectory: true)
                let status = SkillGit.check(source: source, branch: skill.repoBranch)
                map[skill.directory] = status.available
            }
            return map
        }.value
        if var data {
            data.skills = data.skills.map { skill in
                var copy = skill
                if let flag = results[skill.directory] {
                    copy.updateAvailable = flag
                }
                return copy
            }
            self.data = data
        }
    }

    // MARK: - 安全复扫（二期 F3：防「几个月后变恶意」）

    /// 后台静态复扫已装技能（atlas/local；CC Switch 只读来源跳过——修复动作是迁移）。
    /// 以目录 mtime 为缓存键，只重扫有变化的。
    private func rescanSecurity(for skills: [Skill]) {
        let targets = skills
            .filter { $0.origin != .ccSwitch && !$0.disabled }
            .map { (directory: $0.directory, path: $0.sourcePath) }
        let cache = securityCache
        Task { [weak self] in
            let result: ([String: [SecurityFinding]], [String: (Date, [SecurityFinding])]) =
                await Task.detached(priority: .utility) {
                    var findings: [String: [SecurityFinding]] = [:]
                    var newCache: [String: (Date, [SecurityFinding])] = [:]
                    let fileManager = FileManager.default
                    for target in targets {
                        let url = URL(fileURLWithPath: target.path, isDirectory: true)
                        let stamp = (try? fileManager.attributesOfItem(atPath: target.path))?[.modificationDate] as? Date ?? .distantPast
                        if let cached = cache[target.path], cached.stamp == stamp {
                            newCache[target.path] = cached
                            if !cached.findings.isEmpty { findings[target.directory] = cached.findings }
                            continue
                        }
                        let scanned = SecurityScanner.scan(directory: url)
                        newCache[target.path] = (stamp, scanned)
                        if !scanned.isEmpty { findings[target.directory] = scanned }
                    }
                    return (findings, newCache)
                }.value
            guard let self else { return }
            // 可疑项（非 info）进体检展示；info 外链单独收集喂存活探测
            var visible: [String: [SecurityFinding]] = [:]
            var links: [String: [String]] = [:]
            for (directory, findings) in result.0 {
                let suspicious = findings.filter { $0.severity != .info }
                if !suspicious.isEmpty { visible[directory] = suspicious }
                let urls = findings.filter { $0.severity == .info }.map(\.excerpt)
                if !urls.isEmpty { links[directory] = urls }
            }
            self.securityFindings = visible
            self.externalLinks = links
            self.securityCache = result.1
            Task { await self.checkExternalLinks(force: LaunchArgs.flag("atlasCheckLinks")) }
        }
    }

    // MARK: - 外链存活复查（每周自动 + 手动；只报确定死掉的）

    private static let linkCheckKey = "atlasLastLinkCheck"

    func checkExternalLinks(force: Bool) async {
        guard !checkingLinks else { return }
        let last = UserDefaults.standard.double(forKey: Self.linkCheckKey)
        if last > 0 { lastLinkCheck = Date(timeIntervalSince1970: last) }
        if !force, last > 0, Date().timeIntervalSince1970 - last < 7 * 86400 { return }
        let linkMap = externalLinks
        guard !linkMap.isEmpty else {
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.linkCheckKey)
            return
        }
        checkingLinks = true
        defer { checkingLinks = false }

        var uniqueURLs: [String] = []
        var seen = Set<String>()
        for urls in linkMap.values {
            for url in urls where seen.insert(url).inserted {
                uniqueURLs.append(url)
            }
        }
        uniqueURLs = Array(uniqueURLs.prefix(80))

        let dead = await LinkProber.probe(urls: uniqueURLs)

        var findings: [String: [SecurityFinding]] = [:]
        for (directory, urls) in linkMap {
            for url in urls {
                guard let reason = dead[url] else { continue }
                findings[directory, default: []].append(SecurityFinding(
                    severity: .warning,
                    rule: "外链已失效（引用的端点可能已下线或被替换）",
                    file: "SKILL.md", line: 0,
                    excerpt: "\(url) — \(reason)"
                ))
            }
        }
        deadLinkFindings = findings
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.linkCheckKey)
        lastLinkCheck = Date()

        // -atlasCheckLinks -atlasProbeOut：验收探针
        if LaunchArgs.flag("atlasCheckLinks"), let out = LaunchArgs.value("atlasProbeOut") {
            let payload: [String: Any] = [
                "checked": uniqueURLs.count,
                "dead": dead.map { ["url": $0.key, "reason": $0.value] },
            ]
            if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
               let text = String(data: data, encoding: .utf8) {
                try? text.write(toFile: out, atomically: true, encoding: .utf8)
            }
            quitIfRequested()
        }
    }

    // MARK: - 二期探针（F1 触发模拟 / F2 发起器 dry-run，验收用）

    private var phase2ProbesDone = false

    private func runPhase2ProbesIfRequested(skills: [Skill]) {
        guard !phase2ProbesDone else { return }
        phase2ProbesDone = true
        // -atlasTriggerProbe "做个PPT" -atlasProbeOut /path.json
        if let phrase = LaunchArgs.value("atlasTriggerProbe"),
           let out = LaunchArgs.value("atlasProbeOut") {
            let atRiskNames = Set(doctorReport.atRisk.map(\.skill.name))
            let ranked = TriggerLab.simulate(
                phrase: phrase, skills: skills, usage: usage, atRiskNames: atRiskNames
            )
            let payload: [[String: Any]] = ranked.map {
                ["skill": $0.skill.name, "score": $0.score,
                 "matched": $0.matched, "buried": $0.buried,
                 "atRisk": $0.atRisk, "disabled": $0.disabled, "usage": $0.usageCount]
            }
            if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
               let text = String(data: data, encoding: .utf8) {
                try? text.write(toFile: out, atomically: true, encoding: .utf8)
            }
        }
        // -atlasLaunchProbe <技能名> -atlasLaunchTopic <主题> -atlasProbeOut /path.json
        if let name = LaunchArgs.value("atlasLaunchProbe"),
           let out = LaunchArgs.value("atlasProbeOut"),
           let skill = skills.first(where: { $0.name == name || $0.directory == name }) {
            let topic = LaunchArgs.value("atlasLaunchTopic") ?? ""
            _ = try? SkillLauncher.launch(skill: skill, topic: topic, dryRunProbe: out)
        }
        // -atlasOutputsProbe <技能名> -atlasProbeOut /path.json（F4 产出回链）
        if let name = LaunchArgs.value("atlasOutputsProbe"),
           let out = LaunchArgs.value("atlasProbeOut"),
           let skill = skills.first(where: { $0.name == name || $0.directory == name }) {
            let records = OutputLinker.recentOutputs(for: skill)
            let payload: [[String: Any]] = records.map {
                ["dir": $0.directory.path, "date": $0.dateText, "topic": $0.topic,
                 "files": $0.fileCount, "deliverable": $0.latestDeliverable ?? ""]
            }
            if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
               let text = String(data: data, encoding: .utf8) {
                try? text.write(toFile: out, atomically: true, encoding: .utf8)
            }
        }
        // -atlasDropProbe <文件路径> -atlasProbeOut /path.json（F5 规则匹配）
        if let file = LaunchArgs.value("atlasDropProbe"),
           let out = LaunchArgs.value("atlasProbeOut") {
            let matches = DropRules.match(fileURL: URL(fileURLWithPath: file), skills: skills)
            let payload: [[String: String]] = matches.map {
                ["skill": $0.skillDirectory, "reason": $0.reason]
            }
            if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
               let text = String(data: data, encoding: .utf8) {
                try? text.write(toFile: out, atomically: true, encoding: .utf8)
            }
        }
        let probeKeys = ["atlasTriggerProbe", "atlasLaunchProbe", "atlasOutputsProbe", "atlasDropProbe"]
        if probeKeys.contains(where: { LaunchArgs.value($0) != nil }) {
            quitIfRequested()
        }
    }

    // MARK: - 使用频率统计（后台增量索引）

    private var usageTask: Task<Void, Never>?

    func reindexUsage(for skills: [Skill]) {
        usageTask?.cancel()
        let knownDirs = Set(skills.map(\.directory))
        usageIndexing = true
        usageProgress = 0
        // AppStore 与应用同生命周期，任务内强捕获（新一轮索引会先 cancel 旧任务）
        usageTask = Task { [self] in
            let result = await Task.detached(priority: .utility) { [self] in
                UsageIndexer.index(knownDirs: knownDirs) { fraction in
                    Task { @MainActor [self] in self.usageProgress = fraction }
                }
            }.value
            guard !Task.isCancelled else { return }
            usage = result.usage
            mergeHookStats()
            usageIndexing = false
            usageIndexInfo = String(
                format: L("%d 个会话文件（增量解析 %d 个），耗时 %.1f 秒"),
                result.scannedFiles, result.reparsedFiles, result.duration
            )
        }
    }

    // MARK: - Hook 实时遥测（三期 G5）

    /// hook 事件口径（目录 → 精确计量），与 grep 口径并存展示
    @Published var hookStats: [String: HookTelemetry.HookStats] = [:]

    /// 把 hook 事件并进 usage：grep 漏计的补会话数，最近使用取两口径较新者。
    /// 长期未用/丢弃模拟因此不再冤枉「grep 认不出但确实在用」的技能。
    func mergeHookStats() {
        var nameToDirectory: [String: String] = [:]
        for skill in skills { nameToDirectory[skill.name] = skill.directory }
        hookStats = HookTelemetry.stats(nameToDirectory: nameToDirectory)
        for (directory, stats) in hookStats {
            var record = usage[directory] ?? SkillUsage()
            if record.total == 0 { record.claudeSessions = stats.sessions }
            if let last = stats.last, last > (record.lastUsed ?? .distantPast) { record.lastUsed = last }
            usage[directory] = record
        }
    }

    /// 长期未用批量停用（首次治理主入口：一键把吃灰技能移出 listing）。
    /// CC Switch 来源只读跳过；全部处理完只重扫一次。
    func disableAllStale() {
        // 被活跃下游依赖的跳过（guizang-social-card-skill 被 to-xhs 依赖这类）
        let targets = staleSkills.filter { skill in
            guard skill.origin != .ccSwitch, !skill.disabled else { return false }
            let dependents = ProductionChain.dependents(of: skill.directory)
            return !dependents.contains { directory in
                skills.contains { $0.directory == directory && !$0.disabled }
            }
        }
        guard !targets.isEmpty else { return }
        pauseWatching()
        var failures: [String] = []
        for skill in targets {
            do {
                if skill.origin == .atlas {
                    try SkillActions.setDisabled(directory: skill.directory, disabled: true)
                } else {
                    try disableLocalDirectory(skill, disabled: true)
                }
            } catch {
                failures.append(skill.name)
            }
        }
        if !failures.isEmpty {
            actionError = LF("有 %d 个未能停用：%@", failures.count, failures.prefix(3).joined(separator: "、") + (failures.count > 3 ? "…" : ""))
        }
        resumeWatching()
        Task { await rescan(keepSelection: true) }
    }

    /// 长期未用：从未使用 + 90 天未用（索引完成后才有意义）
    var staleSkills: [Skill] {
        guard !usageIndexing else { return [] }
        let now = Date()
        let cutoff = now.addingTimeInterval(-90 * 86400)
        // 新装技能给 14 天观察期：「没有使用记录」≠ 吃灰，也可能是刚装上还没轮到它。
        // 没有这一条，用户上午装的技能下午就会被「全部停用」一键停掉。
        let grace = 14.0 * 86400
        return skills.filter { skill in
            guard !skill.disabled else { return false }  // 已停用的不再算「吃灰」
            if skill.installedAt > 0,
               now.timeIntervalSince(Date(timeIntervalSince1970: TimeInterval(skill.installedAt))) < grace {
                return false
            }
            guard let record = usage[skill.directory] else { return true }
            guard let last = record.lastUsed else { return true }
            return last < cutoff
        }
        .sorted {
            let a = usage[$0.directory]?.lastUsed ?? .distantPast
            let b = usage[$1.directory]?.lastUsed ?? .distantPast
            return a != b ? a < b : $0.name.lowercased() < $1.name.lowercased()
        }
    }

    // MARK: - 触发词撞车检测

    /// 抽取触发短语：描述中「」引号内的短语 + 技能名分词
    static func triggerPhrases(of skill: Skill) -> Set<String> {
        var phrases = Set<String>()
        if let regex = try? NSRegularExpression(pattern: "「([^」]{1,24})」") {
            let text = skill.description
            let range = NSRange(text.startIndex..., in: text)
            for match in regex.matches(in: text, range: range) {
                if let swiftRange = Range(match.range(at: 1), in: text) {
                    phrases.insert(String(text[swiftRange]))
                }
            }
        }
        // 技能名分词：常见结构词不算触发信号
        let stopWords: Set<String> = ["skill", "skills", "the", "and", "for", "with", "expert", "writer", "use", "new"]
        for token in skill.name.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
        where token.count >= 3 && !stopWords.contains(token) {
            phrases.insert(token)
        }
        return phrases
    }

    /// 两技能共享 ≥2 条短语（或 1 条 ≥4 字的完整短语）判为重叠；按共享数排序取前 10
    static func computeTriggerOverlaps(_ allSkills: [Skill]) -> [TriggerOverlap] {
        let skills = allSkills.filter { !$0.disabled }  // 已停用的不会再响应触发词
        let phraseSets = skills.map { triggerPhrases(of: $0) }
        var overlaps: [TriggerOverlap] = []
        for i in skills.indices {
            for j in skills.indices where j > i {
                let shared = phraseSets[i].intersection(phraseSets[j])
                let qualifies = shared.count >= 2 || shared.contains { $0.count >= 4 }
                guard qualifies, !shared.isEmpty else { continue }
                overlaps.append(TriggerOverlap(
                    first: skills[i],
                    second: skills[j],
                    shared: shared.sorted { $0.count > $1.count }
                ))
            }
        }
        return Array(overlaps.sorted { $0.shared.count > $1.shared.count }.prefix(10))
    }

    // MARK: - 导出技能清单（⌘E → Markdown）

    func exportSkillList() {
        guard let data else { return }
        let panel = NSSavePanel()
        panel.title = L("导出技能清单")
        panel.nameFieldStringValue = LF("技能清单 %@.md", Format.day.string(from: Date()).replacingOccurrences(of: "/", with: "-"))
        panel.allowedContentTypes = [.init(filenameExtension: "md") ?? .plainText]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Self.markdownList(for: data).write(to: url, atomically: true, encoding: .utf8)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            NSSound.beep()
        }
    }

    static func markdownList(for data: AtlasData) -> String {
        let summary = data.summary
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy/MM/dd HH:mm"

        var lines: [String] = []
        lines.append("# Skill Atlas 技能清单")
        lines.append("")
        lines.append("- 导出时间：\(formatter.string(from: Date()))")
        let sourceNote: String
        if summary.migrated {
            sourceNote = "\(summary.total)（Skill Atlas \(summary.atlasCount) · 本地 \(summary.localCount)）"
        } else if summary.hasCCSwitch {
            sourceNote = "\(summary.total)（CC Switch \(summary.ccSwitchCount) · 本地安装 \(summary.localCount)）"
        } else {
            sourceNote = "\(summary.total)（本地安装）"
        }
        lines.append("- 技能总数：\(sourceNote)")
        lines.append("- 平台可用：Codex \(summary.codexCount) · Claude \(summary.claudeCount)")
        let health = summary.health
        lines.append("- 健康状态：健康 \(health[.healthy] ?? 0) · 警告 \(health[.warning] ?? 0) · 异常 \(health[.error] ?? 0)")
        lines.append("")

        // 按分类分节，节内按名称排序
        var byCategory: [String: [Skill]] = [:]
        for skill in data.skills {
            byCategory[skill.category, default: []].append(skill)
        }
        for (category, skills) in byCategory.sorted(by: { $0.value.count > $1.value.count }) {
            lines.append("## \(category)（\(skills.count)）")
            lines.append("")
            for skill in skills.sorted(by: { $0.name.lowercased() < $1.name.lowercased() }) {
                let platforms = skill.platforms.isEmpty ? L("未启用") : skill.platforms.joined(separator: " / ")
                lines.append("- **\(skill.name)** · \(platforms) · \(skill.origin.label) · \(skill.health.label)")
                let description = skill.description
                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                lines.append("  \(description)")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - 卸载（确认后执行；目录进废纸篓，可恢复）

    func requestUninstall(_ skill: Skill) {
        if skill.origin == .ccSwitch {
            actionError = LF("「%@」由 CC Switch 管理。先执行迁移，再在这里卸载。", skill.name)
            return
        }
        uninstallTarget = skill
    }

    func confirmUninstall(_ skill: Skill, trashLibrary: Bool) {
        uninstallTarget = nil
        pauseWatching()
        do {
            try SkillActions.uninstall(skill: skill, trashLibrary: trashLibrary)
            if selectedName == skill.name { selectedName = nil }
        } catch {
            actionError = error.localizedDescription
        }
        resumeWatching()
        Task { await rescan(keepSelection: true) }
    }

    // MARK: - 批量更新（入口在「更新审阅」区：requestUpdateAll → confirmBatchUpdate）
}
