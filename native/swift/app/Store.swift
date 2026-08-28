import AppKit
import Observation
import SwiftUI
#if SWIFT_PACKAGE
import AtlasCore
#endif

/// v16 四项侧栏（ROADMAP 2.2）：页面名就是用户的处境，不是我的架构名。
///
/// 六项两组是从引擎往外设计的结果——有 ContextDoctor 就长出「供给」，有 MissDetect
/// 就长出「收件箱」。用户读不懂这些词。四项各自回答一个用人话问得出来的问题。
enum NavPage: String, CaseIterable, Identifiable, Hashable {
    case library, add, check, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .library: return L("技能库")
        case .add: return L("添加技能")
        case .check: return L("检查")
        case .settings: return L("设置")
        }
    }

    var symbol: String {
        switch self {
        case .library: return "books.vertical"
        case .add: return "plus.circle"
        case .check: return "checkmark.circle"
        case .settings: return "gearshape"
        }
    }

    var help: String {
        switch self {
        case .library: return L("我有哪些技能（⌘1）")
        case .add: return L("装现成的，或自己做一个（⌘2）")
        case .check: return L("有什么要我处理吗（⌘3）")
        case .settings: return L("外观、软件目录和进阶（⌘4）")
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

/// 索引进度单独成对象：按文件回调时不要带动技能表重绘。
@MainActor
@Observable
final class UsageIndexState {
    var indexing = false
    var progress = 0.0
    @ObservationIgnored private var lastPublished = 0.0

    func begin() {
        indexing = true
        progress = 0
        lastPublished = 0
    }

    func report(_ fraction: Double) {
        guard fraction >= 1 || fraction - lastPublished >= 0.2 else { return }
        lastPublished = fraction
        progress = fraction
    }

    func finish() {
        progress = 1
        indexing = false
    }
}

@MainActor
@Observable
final class AppStore: InstallHost {
    var data: AtlasData? { didSet { dataRevision += 1; libraryGeneration += 1; scheduleDoctorReport() } }
    /// 体检报告缓存的失效键：技能数据或使用统计一变就 +1
    private var dataRevision = 0
    /// 只在库表真的要变时抬。体检/指南读用量时不拆隐藏着的技能表。
    private var libraryGeneration = 0
    @ObservationIgnored private var doctorReportCache: (revision: Int, window: Int, report: DoctorReport)?
    /// 只让读了 `doctorReport` 的视图刷新，不再带动整棵树。
    private var cachedDoctorReport = DoctorReport() { didSet { inboxInputRevision &+= 1 } }

    // MARK: 收件箱条目缓存
    //
    // 侧栏徽标、工具栏副文案、收件箱页读的是同一份聚合结果。没有缓存时它们会在
    // **每次渲染**重跑全量聚合——遍历全部技能查安全命中、枚举 pending-reviews 目录、
    // 逐行解析 oplog（RxFollowup），是 2.1 首版滚动与点击卡顿的主因。
    // 失效键：dataRevision（技能数据）+ inboxInputRevision（安全/miss/重叠/体检/裁决）。
    @ObservationIgnored private var inboxCache: (stamp: Int, items: [InboxItem])?
    /// 聚合输入的版本号。非 Observation 忽略：视图读 inboxItems 时要靠它建立依赖。
    private var inboxInputRevision = 0

    /// 裁决落盘等外部改动后手动抬版本，让缓存失效
    func invalidateInbox() { inboxInputRevision &+= 1 }

    /// 供给写入（档位 / 场景包 / 瘦身草案）后必须调这一下。
    ///
    /// 病根：写 skillOverrides 只改 ~/.claude/settings.json，技能数据本身没变，
    /// 于是 dataRevision 不抬、doctorReportCache 永远命中——账单数字和库页
    /// TierDots 半亮态会一直停在写入前的样子。rescan() 也救不了（它比对的是
    /// 扫描结果，settings 不在其中），只有显式作废体检缓存才行。
    func invalidateSupply() {
        doctorReportCache = nil
        scheduleDoctorReport()
        libraryGeneration &+= 1   // 让 TierDots 半亮态跟着重画
        inboxInputRevision &+= 1
    }

    var inboxItems: [InboxItem] {
        let stamp = dataRevision &* 1_000_003 &+ inboxInputRevision
        if let cache = inboxCache, cache.stamp == stamp { return cache.items }
        let items = InboxAssembler.items(store: self)
        inboxCache = (stamp, items)
        return items
    }

    /// 徽标与副文案口径：未裁决且严重度 ≤1（整理项只在页内排队，不进徽标）
    /// 角标 = **要你做几个决定**，不是有几条症状。
    ///
    /// 同一个原因（比如某个平台的软链集体没了）会刷出一堆条目，检查页把它们
    /// 归并成一张卡、给一个一次修完的动作。角标若还报条目数，就会出现
    /// 「角标 14、页面只有 3 张卡」这种两个数字打架的局面。
    var inboxBadgeCount: Int {
        InboxGroup.build(inboxItems.filter { $0.kind.severity <= 1 }).count
    }
    @ObservationIgnored private var doctorComputeTask: Task<Void, Never>?
    @ObservationIgnored private var deferredWork: Task<Void, Never>?
    @ObservationIgnored private var firstLaunchDeferred = true
    var fatalError: String?
    var scanning = false

    var nav: NavPage = .library
    var selectedName: String?
    /// 从技能详情跳到设置「维护」时展开该组，并尽量把这一条顶到前面。
    var search = "" { didSet { scheduleSearchDebounce() } }
    /// 过滤用的防抖搜索词：输入即时回显，过滤延迟 200ms——每击键全量过滤 + 整表 reloadData 会发肉
    private(set) var debouncedSearch = ""
    @ObservationIgnored private var searchDebounce: Task<Void, Never>?
    var category = "全部"
    var platform = "全部"
    /// 状态筛选：全部 / 可更新 / 已停用（挂载/安全问题写在详情顶部；整理建议在设置 → 维护）
    var stateFilter = "全部"
    var sourceFilter = "全部"
    var favoritesOnly = false
    var favorites: Set<String>

    /// 触发词重叠（每次扫描后计算一次，不计入健康统计）
    var triggerOverlaps: [TriggerOverlap] = [] { didSet { inboxInputRevision &+= 1 } }

    /// 使用频率统计（key = 技能目录名；后台增量索引会话日志）
    var usage: [String: SkillUsage] = [:] {
        didSet {
            // 默认按名称排：使用统计落地不必让过滤缓存失效。
            // 按频率/近用排序时才抬世代。
            if sortOrder == "使用频率" || sortOrder == "最近使用" {
                dataRevision += 1
                libraryGeneration += 1
            }
            scheduleDoctorReport()
        }
    }
    let usageIndex = UsageIndexState()
    /// 最近一次索引的统计口径（报告/帮助文案用）
    var usageIndexInfo = ""

    /// 技能库排序：名称 / 使用频率
    var sortOrder = "名称"
    /// 技能库分组视图（二期 F7）：不分组 / 套件 / 类别——逻辑分组，不动物理目录
    var groupBy = "不分组"

    /// 阅读器 sheet 当前展示的技能（nil = 关闭）
    var readerSkill: Skill?

    /// 安装技能 sheet（⌘N / 筛选行「+ 安装」/ 空状态主按钮）
    var installSheetPresented = false
    /// CLI 深链 skillatlas://review/<token> 打开的待审请求
    var pendingReview: PendingReviewRequest?

    struct PendingReviewRequest: Identifiable {
        var token: String
        var id: String { token }
    }

    func openPendingReview(token: String) {
        guard PendingReviews.load(token) != nil else { return }
        pendingReview = PendingReviewRequest(token: token)
    }
    /// 打开安装窗时预填并开装（空库示例技能）
    var pendingInstallURL: String?
    /// 新装默认点亮的平台。空库勾一次，之后都跟着走。
    var preferredPlatforms: Set<String> = PreferredPlatforms.current {
        didSet { PreferredPlatforms.save(preferredPlatforms) }
    }

    /// 从 CC Switch 迁出向导
    var migrationSheetPresented = false
    var migrating = false
    var migrationStatus = ""
    /// 清理 CC Switch 副本向导（迁移完成后回收磁盘）
    var cleanupSheetPresented = false

    /// 管理操作（停用/恢复/卸载）的错误提示，弹 alert
    var actionError: String?
    /// 卸载确认对话框的目标技能（nil = 关闭）
    var uninstallTarget: Skill?
    /// 正在更新中的技能目录名（行内旋转指示）
    var updatingDirectories: Set<String> = []
    /// 正在批量检查技能更新
    var checkingSkillUpdates = false
    /// 本次检查是否用户手动发起（后台自动检查不在界面上展示进度）
    var checkingInteractive = false
    /// 最近一次技能更新检查完成时间
    var lastSkillUpdateCheck: Date?
    /// 上下文窗口档位（token），给检查引擎做预算模拟，持久化
    var contextWindowTokens: Int {
        didSet {
            UserDefaults.standard.set(contextWindowTokens, forKey: "atlasContextWindow")
            scheduleDoctorReport()
        }
    }
    private static let lastSkillUpdateCheckKey = "atlasLastSkillUpdateCheck"
    @ObservationIgnored private var debugActionDone = false

    /// 自增即请求聚焦全局搜索框（⌘K）
    var searchFocusRequest = 0
    /// 技能表跨切页复用，避免 SwiftUI 卸掉时丢掉滚动位置。
    @ObservationIgnored var skillTable: SkillTableController?

    /// 已装技能的安全复扫结果（key = 技能目录名；后台增量，逐文件缓存落盘）
    var securityFindings: [String: [SecurityFinding]] = [:] { didSet { inboxInputRevision &+= 1 } }

    /// 体检/详情用的安全展示（装前静态规则复扫）
    var securityDisplay: [String: [SecurityFinding]] { securityFindings }

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
    var updateReview: UpdateReview?
    /// 批量审阅（sheet；nil = 关闭，[] = 正在对照上游）
    var batchReviews: [UpdateReview]?
    /// 回滚确认（confirmationDialog）：技能 + 将恢复到的备份名
    struct RollbackRequest: Identifiable {
        var skill: Skill
        var backupName: String
        var id: String { skill.name }
    }
    var rollbackRequest: RollbackRequest?
    /// 更新/回滚完成后的结果通报（alert）
    var updateNotice: String?

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
    var sandboxTarget: Skill?
    var sandboxCount = 0

    func requestSandbox(_ skill: Skill) {
        sandboxTarget = skill
    }

    func confirmSandbox() {
        guard let skill = sandboxTarget else { return }
        sandboxTarget = nil
        pauseWatching()
        do {
            _ = try SkillSandbox.run(skill: skill)
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

    var profiles = ProfilesFile()
    /// 待确认的写盘计划（sheet）：nil = 无
    struct ProfileApplyRequest: Identifiable {
        var profile: AtlasProfile
        var plan: ProfileWriter.Plan
        /// nil = 用户级默认；非 nil = 绑定到该目录
        var directory: URL?
        var id: String { (directory?.path ?? "user") + profile.id }
    }
    var profileRequest: ProfileApplyRequest?
    var profileSheetPresented = false
    var profileNotice: String?

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
            // 非 Claude 平台没有「装着但不进清单」这一档，只能摘软链。
            // 账记在 scenario-mounts.json，catalog 的意图位一个字节不动。
            // 只在默认场景（全局）时做：项目级绑定靠 Claude Code 自己的设置级联，
            // 而软链是全机唯一的，跟着某个目录翻会影响所有会话。
            var unmounted = 0
            if request.directory == nil {
                unmounted = try ScenarioMounts.apply(profile: request.profile, skills: skills)
            }
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
                profileNotice = unmounted > 0
                    ? LF("已把「%@」设为默认场景：Claude Code 里 %d 个技能不再进自动清单，另外 %d 处在别的软件里先摘下来了。撤场景时会原样挂回。",
                         request.profile.name, applied.count, unmounted)
                    : LF("已把「%@」设为默认场景：%d 个技能不再进自动清单。原配置已备份。",
                         request.profile.name, applied.count)
            }
            persistProfiles()
            invalidateSupply()
            Oplog.append(op: "profile-apply", target: request.profile.name, ok: true,
                         detail: "excluded \(applied.count)")
        } catch {
            actionError = error.localizedDescription
        }
    }

    /// 批量补挂：catalog 说该挂、盘上却没有软链的，全部重建。
    ///
    /// 「装了但用不了」在队列里能刷出 6 条一模一样的行——同一个原因（某个平台的
    /// 软链集体没了）被拆成每技能一条。用户看到的是 6 个问题，其实是 1 个。
    /// 这个动作把那 1 个原因一次修掉。
    ///
    /// 返回补好的条数，供回执用。
    @discardableResult
    func repairMounts(directories: [String]? = nil) -> Int {
        let targets = Set(directories ?? skills.map(\.directory))
        var repaired = 0
        pauseWatching()
        for skill in skills where targets.contains(skill.directory) {
            guard skill.origin == .atlas, !skill.managed, !skill.disabled else { continue }
            for platform in AgentPlatform.allCases {
                let mount = skill.mount(platform)
                // 只补「说好要挂、却断了或没有」的；.directory（占位是真目录）
                // 不碰——那要人来判断是不是旧拷贝，静默覆盖会吃掉用户的文件
                guard mount.enabled, mount.status == .missing || mount.status == .broken else { continue }
                do {
                    try SkillActions.setPlatform(
                        directory: skill.directory, platform: platform, enabled: true
                    )
                    Oplog.append(op: "remount", target: skill.directory, ok: true,
                                 detail: platform.rawValue)
                    repaired += 1
                } catch {
                    actionError = error.localizedDescription
                }
            }
        }
        resumeWatching()
        for directory in targets { patchMounts(directory: directory) }
        invalidateInbox()
        return repaired
    }

    /// 把一个技能改回「自动」（Claude 会自己想到用它）。
    ///
    /// 「叫不动」这条待办里，如果原因就是它被设成了「点名才用」，那修复动作只有一个。
    /// 以前这里给的按钮写「去供给页升档」，点了 `store.nav = .check`——你本来就站在
    /// 检查页上，点完什么都没发生。待办条目的动作必须当场把事办了。
    func makeSkillAutomatic(_ skill: Skill) {
        do {
            try SupplyWriter.write(
                assignments: [skill.name: .core],
                target: ProfileWriter.userSettingsURL
            )
            Oplog.append(op: "supply-tier", target: skill.directory, ok: true,
                         detail: "\(skill.name) -> core")
            invalidateSupply()
            refreshMisses()
        } catch {
            actionError = error.localizedDescription
        }
    }

    func applySlimDraft(_ rows: [SlimRow]) {
        do {
            try SlimPlanner.apply(rows, target: ProfileWriter.userSettingsURL)
            invalidateSupply()
            let core = rows.filter { $0.tier == .core }.count
            let trimmed = rows.filter { $0.tier != .core }.count
            profileNotice = LF("已应用瘦身草案：%d 个完整挂载，%d 个不再进自动清单。只对 Claude Code 生效。", core, trimmed)
            Oplog.append(op: "profile-apply", target: "slim-draft", ok: true, detail: "\(trimmed) excluded")
        } catch {
            actionError = error.localizedDescription
        }
    }

    /// 「全部技能」= 让所有技能重新进自动清单。
    ///
    /// 只 revert 场景包写过的键是不够的：逐技能档位与瘦身草案写的是同一张
    /// skillOverrides 表，不一并清掉就会出现「chip 说全都回来了，下面还躺着
    /// 12 个不挂载」。这里按值回收全部属于我们三档的键。
    func revertDefaultProfile(silent: Bool = false) {
        let ourKeys = SupplyWriter.ownedKeys(target: ProfileWriter.userSettingsURL)
        do {
            try ProfileWriter.revert(
                target: ProfileWriter.userSettingsURL,
                appliedKeys: Array(Set(profiles.activeAppliedKeys).union(ourKeys))
            )
            let restored = try ScenarioMounts.revert(skills: skills)
            profiles.activeProfileID = nil
            profiles.activeAppliedKeys = []
            persistProfiles()
            invalidateSupply()
            if restored > 0 { Task { await rescan(keepSelection: true) } }
            if !silent {
                profileNotice = restored > 0
                    ? LF("已恢复默认：%d 个技能重新进入自动清单，%d 处软链挂回来了。", ourKeys.count, restored)
                    : (ourKeys.isEmpty
                        ? L("本来就没有技能被排除，自动清单没有变化。")
                        : LF("已恢复默认：%d 个技能重新进入自动清单。", ourKeys.count))
            }
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
            invalidateSupply()
            if !silent { profileNotice = L("已解除绑定，该目录恢复默认技能清单。") }
        } catch {
            actionError = error.localizedDescription
        }
    }

    // MARK: - 描述医生开药（三期 G2）

    /// 处方 sheet（nil = 关闭）
    var prescription: DescriptionPrescription?

    func requestPrescription(_ skill: Skill) {
        prescription = DescriptionRx.prescribe(skill: skill)
    }

    func adoptPrescription() {
        guard let rx = prescription, !rx.noop else { return }
        prescription = nil
        do {
            try DescriptionRx.writeBack(skill: rx.skill, newDescription: rx.rewritten)
            Oplog.append(op: "rx-writeback", target: rx.skill.directory, ok: true, detail: rx.skill.name)
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

    func requestDisable(_ skill: Skill) {
        setSkillDisabled(skill, disabled: true)
    }

    /// 界面语言（设置页切换；视图树以它为 .id 整体重建，立即生效）
    var uiLanguage = AppLanguage.stored
    func selectLanguage(_ language: AppLanguage) {
        AppLanguage.select(language)
        uiLanguage = language
    }

    func togglePreferred(_ platform: AgentPlatform) {
        if preferredPlatforms.contains(platform.rawValue) {
            guard preferredPlatforms.count > 1 else { return }
            preferredPlatforms.remove(platform.rawValue)
        } else {
            preferredPlatforms.insert(platform.rawValue)
        }
    }

    func beginInstall(url: String) {
        pendingInstallURL = url
        installSheetPresented = true
    }

    private static let favoritesKey = "skill-atlas-favorites"
    @ObservationIgnored private var keyMonitor: Any?

    init() {
        let stored = UserDefaults.standard.stringArray(forKey: Self.favoritesKey) ?? []
        favorites = Set(stored)
        let window = UserDefaults.standard.integer(forKey: "atlasContextWindow")
        contextWindowTokens = window > 0 ? window : 200_000
        let lastCheck = UserDefaults.standard.double(forKey: Self.lastSkillUpdateCheckKey)
        if lastCheck > 0 { lastSkillUpdateCheck = Date(timeIntervalSince1970: lastCheck) }
        let page = LaunchArgs.value("atlasPage") ?? UserDefaults.standard.string(forKey: "atlasPage")
        if let page {
            switch page {
            case "overview", "library", "updates", "health", "doctor", "guide", "howto":
                nav = .library
            case "settings":
                nav = .settings
            default:
                if let target = NavPage(rawValue: page) { nav = target }
            }
        }
        // 调试钩子：-atlasInstallURL <url> 自动打开安装 sheet 并预填（验收用）
        if LaunchArgs.value("atlasInstallURL") != nil {
            installSheetPresented = true
        }
        // 调试钩子：-atlasCleanup 1 启动即打开清理向导（截图/验收用）
        if LaunchArgs.flag("atlasCleanup") {
            cleanupSheetPresented = true
        }
        // 调试钩子：-atlasProfileSheet 1 启动即打开场景编辑器（截图/验收用）
        if LaunchArgs.flag("atlasProfileSheet") {
            loadProfiles()
            profileSheetPresented = true
        }
    }

    /// 库页 Equatable 隔离用：后台安全扫描/外链探测不抬这个世代，列表不跟着重刷。
    var libraryEpoch: Int { libraryGeneration }

    /// 技能库：↑/↓ 或 J/K 选行，/ 聚焦搜索。输入框聚焦时不拦截。
    func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, self.nav == .library,
                      event.modifierFlags.intersection([.command, .option, .control]).isEmpty,
                      !(NSApp.keyWindow?.firstResponder is NSTextView) else { return event }
                switch event.keyCode {
                case 125, 38: self.moveSelection(1); return nil
                case 126, 40: self.moveSelection(-1); return nil
                case 44:
                    self.searchFocusRequest += 1
                    return nil
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
            let scanned = try await Task.detached(priority: .userInitiated) {
                let data = try SkillScanner.scan()
                let overlaps = AppStore.computeTriggerOverlaps(data.skills)
                return (data, overlaps)
            }.value
            var result = scanned.0
            let overlaps = scanned.1
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
            // 扫描结果与上一轮无差异就不发布：watcher 抖动（touch/元数据事件）不该带动全树重算。
            // hasCCSwitch/migrated 可以不伴随技能集变化（如删库留目录），单独比这两个标志。
            let summaryFlagsChanged = data.map {
                $0.summary.hasCCSwitch != result.summary.hasCCSwitch
                    || $0.summary.migrated != result.summary.migrated
            } ?? true
            // 先标「正在索引」，再发布 data：否则空 usage + 未开始索引会被当成「全部吃灰」
            scheduleBackgroundWork(skills: result.skills)
            if summaryFlagsChanged || data?.skills != result.skills {
                data = result
                triggerOverlaps = overlaps
            }
            if fatalError != nil { fatalError = nil }
            refreshMisses()
            if !UserDefaults.standard.bool(forKey: "atlasHookConsentAsked"), !HookTelemetry.installed() {
                hookConsentPresented = true
            }
            startWatchingIfNeeded()
            await runPhase2ProbesIfRequested(skills: result.skills)
            // 调试钩子：-atlasReader <技能名> 启动即打开阅读器；-atlasSelect <技能名> 启动即选中（截图用）
            if readerSkill == nil,
               let name = UserDefaults.standard.string(forKey: "atlasReader"),
               let skill = result.skills.first(where: { $0.name == name }) {
                select(skill.name)
                readerSkill = skill
            }
            // 已知限制：无头启动（后台 shell 直跑二进制）下本探针的高亮与详情栏不重绘，
            // 2.0.0 同症；选中状态本身已置位（-atlasAction 探针可证）。交互态正常。详见 PLAN §9。
            if let name = LaunchArgs.value("atlasSelect") ?? UserDefaults.standard.string(forKey: "atlasSelect"),
               result.skills.contains(where: { $0.name == name }) {
                select(name)
            }
            // 调试钩子：-atlasSelectMany a,b,c 启动即多选（批量条截图用）。
            // 表控制器在库页首帧才创建，延后半秒再写多选集合。
            if let many = LaunchArgs.value("atlasSelectMany") ?? UserDefaults.standard.string(forKey: "atlasSelectMany") {
                let names = Set(many.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
                    .filter { name in result.skills.contains { $0.name == name } }
                if !names.isEmpty {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                        guard let self else { return }
                        self.skillTable?.multi.names = names
                        self.skillTable?.refreshVisible()
                    }
                }
            }
            // 旧「检查 / 怎么用」页已撤；同名调试参数改为选中该技能并停在技能库。
            if let name = LaunchArgs.value("atlasGuideSkill")
                ?? LaunchArgs.value("atlasDoctorSkill")
                ?? UserDefaults.standard.string(forKey: "atlasGuideSkill")
                ?? UserDefaults.standard.string(forKey: "atlasDoctorSkill"),
               result.skills.contains(where: { $0.name == name }) {
                select(name)
            }
            // 调试钩子：-atlasAction disable/enable/adopt/uninstall* 对当前选中技能执行（验收用，只跑一次）
            if !debugActionDone,
               let action = LaunchArgs.value("atlasAction"),
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
                    if let path = LaunchArgs.value("atlasUninstallProbe") {
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
            if selectedName != existing?.name { selectedName = existing?.name }
            loadProfiles()
            // 老仓库是在这些文件出现之前 init 的，补齐忽略项防止 settings 备份、
            // 事件日志、沙箱被 F8 的快照提交推到远端
            try? GitSync.ensureIgnored()
            offerMigrationIfNeeded()
            writeOfferProbe()
            writeDoctorProbe()
            if LaunchArgs.flag("atlasMigrate") {
                UserDefaults.standard.set(false, forKey: "atlasMigrate")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                    self?.performMigration()
                }
            } else if LaunchArgs.flag("atlasRollback") {
                UserDefaults.standard.set(false, forKey: "atlasRollback")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                    self?.rollbackMigration()
                }
            }
            // 自动 git fetch 改走 scheduleBackgroundWork，错开启动前 10 秒
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
            if let target = LaunchArgs.value("atlasApplyUpdateProbe") {
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
            if let target = LaunchArgs.value("atlasSandboxProbe") {
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
            if let action = LaunchArgs.value("atlasProfileProbe") {
                loadProfiles()
                var payload: [String: Any] = ["action": action]
                let name = LaunchArgs.value("atlasProfileName") ?? "验收场景"
                let dirPath = LaunchArgs.value("atlasProfileDir")
                do {
                    switch action {
                    case "create":
                        var profile = AtlasProfile.new(name: name)
                        let raw = LaunchArgs.value("atlasProfileMembers") ?? ""
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
            if let action = LaunchArgs.value("atlasHookProbe") {
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
            if let target = LaunchArgs.value("atlasRollbackProbe") {
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

    private struct FilterStamp: Equatable {
        var revision: Int
        var search: String
        var category: String
        var platform: String
        var stateFilter: String
        var sourceFilter: String
        var favoritesOnly: Bool
        var favorites: Set<String>
        var sortOrder: String
    }

    @ObservationIgnored private var filteredSkillsCache: (stamp: FilterStamp, result: [Skill])?

    /// 搜索防抖：清空立即生效（✕ 按钮 / ⌘K 退出不清不滞后）；非空延迟 200ms 再进过滤
    private func scheduleSearchDebounce() {
        searchDebounce?.cancel()
        if search.isEmpty {
            if debouncedSearch != search { debouncedSearch = search }
            return
        }
        searchDebounce = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled, let self, self.debouncedSearch != self.search else { return }
            self.debouncedSearch = self.search
        }
    }

    var filteredSkills: [Skill] {
        let stamp = FilterStamp(
            revision: dataRevision,
            search: debouncedSearch,
            category: category,
            platform: platform,
            stateFilter: stateFilter,
            sourceFilter: sourceFilter,
            favoritesOnly: favoritesOnly,
            favorites: favorites,
            sortOrder: sortOrder
        )
        if let cache = filteredSkillsCache, cache.stamp == stamp {
            return cache.result
        }
        let result = computeFilteredSkills()
        filteredSkillsCache = (stamp, result)
        return result
    }

    private func computeFilteredSkills() -> [Skill] {
        let query = debouncedSearch.trimmingCharacters(in: .whitespaces).lowercased()
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

    /// 搜索框自己会展示当前词；这里仅表示菜单里的四类筛选是否生效。
    var hasFacetFilters: Bool {
        category != "全部" || platform != "全部" || stateFilter != "全部" || sourceFilter != "全部"
    }

    var activeFacetCount: Int {
        [category, platform, stateFilter, sourceFilter].filter { $0 != "全部" }.count
    }

    var facetSummary: String {
        var parts: [String] = []
        if platform != "全部" {
            parts.append(visiblePlatforms.first(where: { $0.label == platform })?.displayName ?? platform)
        }
        if category != "全部" { parts.append(L(category)) }
        if stateFilter != "全部" { parts.append(L(stateFilter)) }
        if sourceFilter != "全部" { parts.append(L(sourceFilter)) }
        return parts.joined(separator: L("、"))
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

    /// 跳到技能库详情。筛掉当前会把目标藏起来的条件，否则表里看不见、详情也展不开。
    func select(_ name: String) {
        if favoritesOnly && !favorites.contains(name) {
            favoritesOnly = false
        }
        selectedName = name
        if !filteredSkills.contains(where: { $0.name == name }) {
            clearFilters()
        }
        nav = .library
    }

    /// 从别处带到创作页触发验证的预填句（消费后置 nil）
    var simulatePhrase: String?

    /// ⌘N：切到发现页并聚焦搜索框（计数器，每次 +1 触发一次聚焦）
    var discoverSearchFocus = 0

    /// 跳到收件箱，并尽量定位到这个技能的那一条。
    /// 按钮文字承诺「看这一条」，只切页不定位就是说谎。
    func openInbox(for skill: Skill? = nil) {
        if let skill,
           let hit = inboxItems.first(where: { $0.target == skill.directory }) {
            Inbox.pendingFocusID = hit.id
        }
        nav = .check
    }

    func hasCriticalSecurity(_ skill: Skill) -> Bool {
        (securityDisplay[skill.directory] ?? []).contains { $0.severity == .critical }
    }

    func hasBlockingIssue(_ skill: Skill) -> Bool {
        guard !skill.disabled else { return false }
        return skill.health == .error || hasCriticalSecurity(skill)
    }

    func criticalFindings(for skill: Skill) -> [SecurityFinding] {
        (securityDisplay[skill.directory] ?? []).filter { $0.severity == .critical }
    }

    func advisoryFindings(for skill: Skill) -> [SecurityFinding] {
        (securityDisplay[skill.directory] ?? []).filter { $0.severity != .critical }
    }

    var blockingSkills: [Skill] {
        skills.filter { hasBlockingIssue($0) }.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    /// 侧栏不再为维护项打点。设置「维护」折叠标题用同一口径。
    var blockingIssueCount: Int { blockingSkills.count }

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

    /// 侧栏角标 & 更新页：可更新的技能。
    /// 按 dataRevision 记忆化——侧栏每次渲染都读它，不缓存等于每次发布重排 N 遍
    @ObservationIgnored private var updatableSkillsCache: (revision: Int, result: [Skill])?

    var updatableSkills: [Skill] {
        if let cache = updatableSkillsCache, cache.revision == dataRevision { return cache.result }
        let result = skills.filter { $0.updateAvailable && !$0.disabled }
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
        updatableSkillsCache = (dataRevision, result)
        return result
    }

    /// UI 展示的平台。默认 Claude / Codex / Grok / Cursor / Gemini / WorkBuddy。
    /// OpenClaw、OpenCode、Hermes 只保留数据兼容，设置里可打开。
    var visiblePlatformsRaw = UserDefaults.standard.string(forKey: "atlasVisiblePlatforms") ?? ""

    var visiblePlatforms: [AgentPlatform] {
        let parsed = visiblePlatformsRaw.split(separator: ",").compactMap { AgentPlatform(rawValue: String($0)) }
        if parsed.isEmpty {
            return [.claude, .codex, .grokbuild, .cursor, .gemini, .workbuddy]
        }
        return parsed
    }

    /// 开关一个平台 = 「我在用它」：既决定界面里出不出现，也决定新装技能默认勾不勾。
    ///
    /// 这两件事以前是设置页里相隔很远的两组开关（可见平台 / 我在用的软件），
    /// 用户读起来就是同一个矩阵配了两遍。合并的前提是：安装 sheet 本来就会把你的
    /// 实际勾选写回 preferredPlatforms，所以那一组本就不必单独陈列。
    func setVisible(_ platform: AgentPlatform, on: Bool) {
        var current = Set(visiblePlatforms.map(\.rawValue))
        if on { current.insert(platform.rawValue) } else { current.remove(platform.rawValue) }
        if current.isEmpty { current.insert(AgentPlatform.claude.rawValue) }
        let ordered = AgentPlatform.allCases.map(\.rawValue).filter { current.contains($0) }
        visiblePlatformsRaw = ordered.joined(separator: ",")
        UserDefaults.standard.set(visiblePlatformsRaw, forKey: "atlasVisiblePlatforms")

        // 不在用的软件不该继续吃新装的技能——否则 CLI 还会往一个界面上看不见的
        // 目录里建软链，是典型的「关了却没真关」。
        var preferred = preferredPlatforms
        if on { preferred.insert(platform.rawValue) } else { preferred.remove(platform.rawValue) }
        preferred.formIntersection(current)
        if preferred.isEmpty { preferred = [ordered.first ?? AgentPlatform.claude.rawValue] }
        if preferred != preferredPlatforms { preferredPlatforms = preferred }
    }

    var hookConsentPresented = false
    /// 新建技能 sheet（v16：原创作页降级）
    var newSkillSheetPresented = false
    var missHits: [MissHit] = [] { didSet { inboxInputRevision &+= 1 } }
    var ignoredMisses: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "atlasIgnoredMisses") ?? [])

    func refreshMisses() {
        missHits = MissDetect.report(skills: skills).filter { !ignoredMisses.contains($0.directory) }
    }

    func ignoreMiss(_ hit: MissHit) {
        ignoredMisses.insert(hit.directory)
        UserDefaults.standard.set(Array(ignoredMisses), forKey: "atlasIgnoredMisses")
        missHits.removeAll { $0.directory == hit.directory }
    }

    /// 检查报告（预算模拟 + 超长描述 + 可回收）。后台算好再发布。
    var doctorReport: DoctorReport { cachedDoctorReport }

    func clearFilters() {
        category = "全部"
        platform = "全部"
        stateFilter = "全部"
        sourceFilter = "全部"
        search = ""
    }

    func clearFacetFilters() {
        category = "全部"
        platform = "全部"
        stateFilter = "全部"
        sourceFilter = "全部"
    }

    func openFolder(_ path: String) {
        let url = URL(fileURLWithPath: path)
        // 白名单：所有扫描根（CC Switch 源目录 + Claude/Codex 平台根目录）内的路径才允许打开
        let roots = ([
            SkillScanner.sourceRoot,
            SkillScanner.claudeRoot,
            SkillScanner.codexRoot,
            AtlasPaths.root,
            AtlasPaths.libraryRoot,
            AtlasPaths.backupsRoot,
        ] + AgentPlatform.allCases.map { $0.root(home: SkillScanner.home) })
            .map { $0.resolvingSymlinksInPath().standardizedFileURL.path }
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL.path
        guard roots.contains(where: { resolved == $0 || resolved.hasPrefix($0 + "/") }) else { return }
        NSWorkspace.shared.open(url)
    }

    /// 打开安全命中的原文文件（核对用；警告级多数不是要改的代码）
    func openFinding(_ finding: SecurityFinding, in skill: Skill) {
        let root = URL(fileURLWithPath: skill.sourcePath, isDirectory: true)
        let file = finding.file.isEmpty ? root : root.appendingPathComponent(finding.file)
        if FileManager.default.fileExists(atPath: file.path) {
            openFolder(file.path)
        } else {
            openFolder(skill.sourcePath)
        }
    }

    func copyToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    // MARK: - 调用语

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
                return LF("筛出 %d / %d", filteredSkills.count, summary.total)
            }
            let updates = updatableSkills.count
            return updates > 0
                ? LF("%d 个技能 · %d 个可更新", summary.total, updates)
                : LF("%d 个技能", summary.total)
        case .add:
            return L("装现成的，或自己做一个")
        case .check:
            let pending = inboxBadgeCount
            return pending > 0 ? LF("%d 件事要你处理", pending) : L("没有要处理的事")
        case .settings:
            if data.summary.migrated {
                return LF("已迁入 %d 个技能", data.summary.atlasCount)
            }
            if data.summary.hasCCSwitch {
                return L("可以把以前的技能收进来")
            }
            return L("外观和本库")
        }
    }

    // MARK: - 目录自动刷新（FSEvents + 2 秒防抖）

    @ObservationIgnored private let watcher = DirectoryWatcher()
    @ObservationIgnored private var watcherStarted = false
    @ObservationIgnored private var refreshDebounce: Task<Void, Never>?

    private func startWatchingIfNeeded() {
        guard !watcherStarted else { return }
        watcherStarted = true
        // 注意：不能监听 ~/.skill-atlas 根目录——usage-index.json / security-index.json
        // 就写在根下，监听它会形成 扫描→写缓存→FSEvents→再扫描 的自触发循环
        //（表现为右上角刷新箭头转个不停）。只监听技能目录与 CC Switch DB。
        let paths = Set([
            SkillScanner.claudeRoot.resolvingSymlinksInPath().path,
            SkillScanner.codexRoot.resolvingSymlinksInPath().path,
            SkillScanner.sourceRoot.resolvingSymlinksInPath().path,
            SkillScanner.databaseURL.path,
            AtlasPaths.libraryRoot.path,
        ] + AgentPlatform.allCases.map { $0.root(home: SkillScanner.home).path })
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
        guard skill.origin == .atlas, !skill.managed else { return }
        pauseWatching()
        do {
            try SkillActions.setPlatform(directory: skill.directory, platform: platform, enabled: enabled)
            Oplog.append(op: enabled ? "enable" : "disable", target: skill.directory, ok: true,
                         detail: platform.rawValue)
            // 手动动作优先于场景：你亲手点亮的，撤场景时不必再挂一遍
            if enabled { ScenarioMounts.forget(directory: skill.directory, platform: platform) }
            patchMounts(directory: skill.directory)
        } catch {
            actionError = error.localizedDescription
            // 只有失败才值得全量重扫：盘上到底成了什么样这时才是未知的
            Task { await rescan(keepSelection: true) }
        }
        resumeWatching()
    }

    /// 挂/摘一条软链后就地更新这一个技能，不走 rescan()。
    ///
    /// 以前这里是 `await rescan()`，于是点一下平台图标要付：全平台根全量扫描
    /// （147 技能 × 11 根）+ 触发词两两比对 + **147 个技能的安全全扫** + 用法索引重建
    /// + 联网查更新。用户的原话是「转好久，卡的要死」。
    ///
    /// 但软链的挂摘不改技能内容：安全结论没变、用法没变、版本没变。真正变的只有
    /// 这一个技能的 mounts/platforms/problems/health，以及汇总里的计数。
    private func patchMounts(directory: String) {
        guard var current = data,
              let index = current.skills.firstIndex(where: { $0.directory == directory })
        else { return }
        let record = AtlasCatalog.load().skills[directory]
        let enabled = Dictionary(uniqueKeysWithValues: AgentPlatform.allCases.map {
            ($0, record?.isEnabled($0) ?? false)
        })
        current.skills[index] = SkillScanner.refreshMounts(skill: current.skills[index], enabled: enabled)
        // 汇总的每平台计数是侧栏与设置页读的，跟着一起对齐，否则数字会停在旧值
        for platform in AgentPlatform.allCases {
            let label = platform.label
            current.summary.enabled[label] = current.skills.filter { $0.platforms.contains(label) }.count
            current.summary.verified[label] = current.skills.filter {
                $0.mount(platform).status == .ok
            }.count
        }
        data = current
    }

    /// 收编本地直装：拷入本库、原散装目录替换成指向库的软链。
    /// 重扫后 origin 变 atlas，详情页原地解锁平台 logo 开关。
    /// 右键「收进本库…」的待确认目标（nil = 无）。
    /// 收编会改动原目录的所有权归属，不该有任何一条路径静默执行。
    var adoptTarget: Skill?

    func requestAdopt(_ skill: Skill) {
        adoptTarget = skill
    }

    func confirmAdopt() {
        guard let skill = adoptTarget else { return }
        adoptTarget = nil
        adoptLocalSkill(skill)
    }

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
    /// 收编前必须交代的事：外部实体收编后编辑原目录不再生效。
    /// 三个入口（发现页、设置、右键）共用这一句，否则同一个动作在不同路径下
    /// 知情程度不同——右键那条以前是静默执行的。
    func adoptConfirmMessage(_ targets: [Skill]) -> String {
        var text = L("拷进本库，原来的位置改成指向这里。之后在本应用里开关。")
        let external = targets.filter { SkillActions.isExternalSource($0) }.count
        if external > 0 {
            text += LF("其中 %lld 个的实体在平台目录之外，收编后编辑原目录不再生效。", external)
        }
        return text
    }

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

    @ObservationIgnored private var suppressMigrationOffer = false

    func offerMigrationIfNeeded() {
        if LaunchArgs.flag("atlasForceMigrate") {
            migrationSheetPresented = true
            return
        }
        if suppressMigrationOffer { return }
        if LaunchArgs.flag("atlasRollback") { return }
        if UserDefaults.standard.bool(forKey: "atlasQuit") && LaunchArgs.flag("atlasMigrate") {
            // 探针模式由 performMigration 接手，不弹向导
        }
        let hasCC = data?.summary.hasCCSwitch == true
        if LaunchArgs.flag("atlasShowMigrate") {
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
        let report = makeDoctorReport()
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
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastSkillUpdateCheckKey)
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
            var changed = false
            data.skills = data.skills.map { skill in
                var copy = skill
                if let flag = results[skill.directory], copy.updateAvailable != flag {
                    copy.updateAvailable = flag
                    changed = true
                }
                return copy
            }
            if changed { self.data = data }
        }
    }

    // MARK: - 安全复扫（二期 F3：防「几个月后变恶意」）

    /// 后台静态复扫已装技能（atlas/local；CC Switch 只读来源跳过——修复动作是迁移）。
    /// 逐文件 (path, mtime, size) 缓存落盘，冷启动几乎只读索引。
    private func rescanSecurity(for skills: [Skill]) {
        let targets = skills
            .filter { $0.origin != .ccSwitch && !$0.disabled }
            .map { (directory: $0.directory, path: $0.sourcePath) }
        Task { [weak self] in
            let scanned = await Task.detached(priority: .utility) {
                SecurityScanner.scanInstalled(targets: targets)
            }.value
            guard let self else { return }
            // 可疑项（非 info）进体检展示；info 级外链清单不再单独收集
            var visible: [String: [SecurityFinding]] = [:]
            for (directory, findings) in scanned {
                let suspicious = findings.filter { $0.severity != .info }
                if !suspicious.isEmpty { visible[directory] = suspicious }
            }
            if self.securityFindings != visible { self.securityFindings = visible }
            let criticalDirs = visible.filter { _, findings in findings.contains { $0.severity == .critical } }
            // 通知要能说出是哪个技能，「有 4 个技能」既看不懂也没法行动
            let nameByDir = Dictionary(uniqueKeysWithValues: self.skills.map { ($0.directory, $0.name) })
            AtlasNotify.securityHit(critical: criticalDirs.keys.map {
                (directory: $0, name: nameByDir[$0] ?? $0)
            })
        }
    }

    // MARK: - 二期探针（F1 触发模拟）

    @ObservationIgnored private var phase2ProbesDone = false

    private func runPhase2ProbesIfRequested(skills: [Skill]) async {
        guard !phase2ProbesDone else { return }
        phase2ProbesDone = true
        // -atlasTriggerProbe "做个PPT" -atlasProbeOut /path.json
        if let phrase = LaunchArgs.value("atlasTriggerProbe"),
           let out = LaunchArgs.value("atlasProbeOut") {
            let atRiskNames = Set(makeDoctorReport().atRisk.map(\.skill.name))
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
        let probeKeys = ["atlasTriggerProbe"]
        if probeKeys.contains(where: { LaunchArgs.value($0) != nil }) {
            quitIfRequested()
        }
    }

    // MARK: - 启动错峰 / 后台派生计算

    /// 无头验收 / 调试探针：跳过错峰，立刻跑完后续工作
    private var skipLaunchStagger: Bool {
        LaunchArgs.flag("atlasQuit")
            || LaunchArgs.flag("atlasCheckSkillUpdates")
            || UserDefaults.standard.bool(forKey: "atlasCheckSkillUpdates")
            || LaunchArgs.value("atlasTriggerProbe") != nil
            || UserDefaults.standard.string(forKey: "atlasUpdateReviewProbe") != nil
            || LaunchArgs.value("atlasAction") != nil
            || UserDefaults.standard.string(forKey: "atlasToggle") != nil
            || UserDefaults.standard.string(forKey: "atlasDoctorProbe") != nil
    }

    /// 扫描先落地，使用统计 / 安全复扫 / git fetch 错开启动前几秒的合成窗口。
    private func scheduleBackgroundWork(skills: [Skill]) {
        deferredWork?.cancel()
        let stagger = firstLaunchDeferred && !skipLaunchStagger
        firstLaunchDeferred = false
        usageIndex.begin()
        deferredWork = Task { [weak self] in
            if stagger {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
            }
            guard !Task.isCancelled else { return }
            self?.startUsageIndex(for: skills)

            if stagger {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
            }
            guard !Task.isCancelled else { return }
            self?.rescanSecurity(for: skills)

            if LaunchArgs.flag("atlasQuit") { return }
            if stagger {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
            guard !Task.isCancelled else { return }
            await self?.checkSkillUpdates(interactive: false)
        }
    }

    private func makeDoctorReport() -> DoctorReport {
        ContextDoctor.report(
            skills: skills,
            usage: usage,
            staleDirectories: Set(staleSkills.map(\.directory)),
            contextWindowTokens: contextWindowTokens
        )
    }

    private func scheduleDoctorReport() {
        let revision = dataRevision
        let window = contextWindowTokens
        if let cache = doctorReportCache, cache.revision == revision, cache.window == window {
            return
        }
        let snapshotSkills = skills
        let snapshotUsage = usage
        let stale = Set(staleSkills.map(\.directory))
        doctorComputeTask?.cancel()
        doctorComputeTask = Task { [weak self] in
            let report = await Task.detached(priority: .utility) {
                ContextDoctor.report(
                    skills: snapshotSkills,
                    usage: snapshotUsage,
                    staleDirectories: stale,
                    contextWindowTokens: window
                )
            }.value
            guard !Task.isCancelled, let self else { return }
            self.cachedDoctorReport = report
            self.doctorReportCache = (revision, window, report)
        }
    }

    // MARK: - 使用频率统计（后台增量索引）

    @ObservationIgnored private var usageTask: Task<Void, Never>?

    func reindexUsage(for skills: [Skill]) {
        usageIndex.begin()
        startUsageIndex(for: skills)
    }

    private func startUsageIndex(for skills: [Skill]) {
        usageTask?.cancel()
        let knownDirs = Set(skills.map(\.directory))
        // AppStore 与应用同生命周期，任务内强捕获（新一轮索引会先 cancel 旧任务）
        usageTask = Task { [self] in
            let progress = usageIndex
            let result = await Task.detached(priority: .utility) {
                UsageIndexer.index(knownDirs: knownDirs) { fraction in
                    Task { @MainActor in progress.report(fraction) }
                }
            }.value
            guard !Task.isCancelled else { return }
            if usage != result.usage { usage = result.usage }
            mergeHookStats()
            usageIndex.finish()
            usageIndexInfo = String(
                format: L("%d 个会话文件（增量解析 %d 个），耗时 %.1f 秒"),
                result.scannedFiles, result.reparsedFiles, result.duration
            )
        }
    }

    // MARK: - Hook 实时遥测（三期 G5）

    /// hook 事件口径（目录 → 精确计量），与 grep 口径并存展示
    var hookStats: [String: HookTelemetry.HookStats] = [:]

    /// 把 hook 事件并进 usage：hook 是 Claude 主源，grep 回填（hook 没有的才用 grep）。
    func mergeHookStats() {
        let nameToDirectory = Dictionary(uniqueKeysWithValues: skills.map { ($0.name, $0.directory) })
        Task { [weak self] in
            let stats = await Task.detached(priority: .utility) {
                HookTelemetry.stats(nameToDirectory: nameToDirectory)
            }.value
            guard let self else { return }
            if self.hookStats != stats { self.hookStats = stats }
            var next = self.usage
            for (directory, record) in stats {
                var merged = next[directory] ?? SkillUsage()
                merged.claudeSessions = max(record.sessions, merged.claudeSessions)
                if let last = record.last, last > (merged.lastUsed ?? .distantPast) { merged.lastUsed = last }
                next[directory] = merged
            }
            if next != self.usage { self.usage = next }
        }
    }

    /// 长期未用批量停用（首次治理主入口：一键把吃灰技能移出 listing）。
    /// CC Switch 来源只读跳过；全部处理完只重扫一次。
    func disableAllStale() {
        let targets = staleSkills.filter { skill in
            skill.origin != .ccSwitch && !skill.disabled
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
        guard !usageIndex.indexing else { return [] }
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
    nonisolated static func triggerPhrases(of skill: Skill) -> Set<String> {
        var phrases = Set<String>()
        let text = skill.description
        let range = NSRange(text.startIndex..., in: text)
        for match in TriggerLab.quotedPhrase.matches(in: text, range: range) {
            if let swiftRange = Range(match.range(at: 1), in: text) {
                phrases.insert(String(text[swiftRange]))
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
    nonisolated static func computeTriggerOverlaps(_ allSkills: [Skill]) -> [TriggerOverlap] {
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
        let platformBits = AgentPlatform.allCases.compactMap { platform -> String? in
            let count = summary.enabled[platform.label] ?? 0
            return count > 0 ? "\(platform.displayName) \(count)" : nil
        }
        lines.append("- 平台可用：" + (platformBits.isEmpty ? L("无") : platformBits.joined(separator: " · ")))
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
