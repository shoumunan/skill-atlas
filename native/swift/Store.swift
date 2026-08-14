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
    @Published var data: AtlasData?
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
    @Published var usage: [String: SkillUsage] = [:]
    @Published var usageIndexing = false
    @Published var usageProgress = 0.0
    /// 最近一次索引的统计口径（报告/帮助文案用）
    @Published var usageIndexInfo = ""

    /// 技能库排序：名称 / 使用频率
    @Published var sortOrder = "名称"

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
            startWatchingIfNeeded()
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
            // 调试钩子：-atlasAction disable/enable 对当前选中技能执行停用/恢复（验收用，只跑一次）
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
                                "libraryExists": FileManager.default.fileExists(atPath: library.path),
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

    /// UI 展示的平台固定四个：Claude Code / Codex / Gemini / Grok。
    /// OpenCode、Hermes 仅保留数据兼容（已有软链不动），不再出现在界面上。
    var visiblePlatforms: [AgentPlatform] {
        [.claude, .codex, .gemini, .grokbuild]
    }

    /// 体检报告（预算模拟 + 超长描述 + 可回收）
    var doctorReport: DoctorReport {
        ContextDoctor.report(
            skills: skills,
            usage: usage,
            staleDirectories: Set(staleSkills.map(\.directory)),
            contextWindowTokens: contextWindowTokens
        )
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
            "listingSoftCap": ContextDoctor.listingSoftCap,
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

    func pullSkill(_ skill: Skill) {
        guard skill.origin == .atlas, !updatingDirectories.contains(skill.directory) else { return }
        pauseWatching()
        updatingDirectories.insert(skill.directory)
        Task {
            let source = URL(fileURLWithPath: skill.sourcePath, isDirectory: true)
            let result = await Task.detached(priority: .userInitiated) {
                Result { try SkillGit.pullFF(source: source) }
            }.value
            updatingDirectories.remove(skill.directory)
            if case .failure(let error) = result {
                actionError = error.localizedDescription
            }
            resumeWatching()
            await rescan(keepSelection: true)
            await checkSkillUpdates(interactive: false)
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
            usageIndexing = false
            usageIndexInfo = String(
                format: L("%d 个会话文件（增量解析 %d 个），耗时 %.1f 秒"),
                result.scannedFiles, result.reparsedFiles, result.duration
            )
        }
    }

    /// 长期未用批量停用（首次治理主入口：一键把吃灰技能移出 listing）。
    /// CC Switch 来源只读跳过；全部处理完只重扫一次。
    func disableAllStale() {
        let targets = staleSkills.filter { $0.origin != .ccSwitch && !$0.disabled }
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
        let cutoff = Date().addingTimeInterval(-90 * 86400)
        return skills.filter { skill in
            guard !skill.disabled else { return false }  // 已停用的不再算「吃灰」
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

    // MARK: - 批量更新

    func updateAllSkills() {
        let targets = updatableSkills.filter { $0.origin == .atlas }
        guard !targets.isEmpty else { return }
        pauseWatching()
        updatingDirectories.formUnion(targets.map(\.directory))
        Task {
            var failures: [String] = []
            for skill in targets {
                let source = URL(fileURLWithPath: skill.sourcePath, isDirectory: true)
                let result = await Task.detached(priority: .userInitiated) {
                    Result { try SkillGit.pullFF(source: source) }
                }.value
                if case .failure(let error) = result {
                    failures.append("\(skill.name)：\(error.localizedDescription)")
                }
                updatingDirectories.remove(skill.directory)
            }
            resumeWatching()
            if !failures.isEmpty {
                actionError = L("部分技能未能快进更新：") + "\n" + failures.joined(separator: "\n")
            }
            await rescan(keepSelection: true)
            await checkSkillUpdates(interactive: false)
        }
    }
}
