import Foundation

// MARK: - 场景在非 Claude 平台上的落地（2.4）
//
// 背景：场景（Profile）原本只对 Claude Code 生效，因为只有它有 skillOverrides
// 这个「装着、但不进开场清单」的开关。Codex / Gemini / Cursor 这些只有装或不装
// 两种状态，没有中间档。
//
// 那就用它们有的那一档：**摘软链**。场景一开，非成员技能在选中的平台上摘掉；
// 场景一撤，原样挂回来。
//
// ## 为什么要单独一本账，不直接改 catalog 的 enabled 位
//
// catalog 里的 `enabled[platform]` 是**你的意图**（「我要这个技能在 Codex 上用」）。
// 场景是**临时覆盖**。如果应用场景时把 enabled 改成 false，那么：
//
// - 撤场景时分不清哪些是场景关的、哪些是你本来就关的 —— 一撤就把你自己关掉的
//   也打开了，等于吃掉你的设置；
// - 反过来若不改 enabled、只摘软链，扫描器会看到「说好要挂、盘上没有」，
//   于是检查页立刻冒出一堆假的「装了但用不了」。
//
// 所以：**enabled 位一个字节都不动**，另记一本账，写明「这几条软链是场景摘的」。
// 扫描器读这本账，把这些位置当成「有意关着」而不是「挂载缺失」。
//
// ## 只记我们真摘掉的
//
// 应用时若某条软链本来就不在（你自己关的），不记账也不碰。撤场景时只挂回账上
// 记着的那些 —— 撤回来的一定是我们拿走的，不多不少。
//
// ## 存独立文件的理由同 Profiles.swift
//
// 老版本 App 的 AtlasCatalog.save() 会把不认识的键整段丢掉，而 ~/.skill-atlas 是
// git 同步仓库，混版本机器一次保存就把账本清空 —— 那之后就再也挂不回来了。

/// 账上的一条：某个技能在某个平台上的软链被场景摘掉了
package struct SuppressedMount: Codable, Equatable, Hashable {
    package var directory: String
    /// AgentPlatform.rawValue
    package var platform: String

    package init(directory: String, platform: String) {
        self.directory = directory
        self.platform = platform
    }
}

package struct ScenarioMountState: Codable, Equatable {
    package var version: Int = 1
    /// 当前生效的场景 id（仅供 UI 显示「现在是哪套」）
    package var profileID: String?
    package var appliedAt: Int = 0
    /// 我们摘掉的软链。撤场景时按这份原样挂回。
    package var suppressed: [SuppressedMount] = []

    package init(
        version: Int = 1,
        profileID: String? = nil,
        appliedAt: Int = 0,
        suppressed: [SuppressedMount] = []
    ) {
        self.version = version
        self.profileID = profileID
        self.appliedAt = appliedAt
        self.suppressed = suppressed
    }
}

package enum ScenarioMounts {
    package static var url: URL {
        AtlasPaths.root.appendingPathComponent("scenario-mounts.json")
    }

    /// 读不到/解不开都返回空账。这里兜底是安全的：空账只意味着「没有场景在压着」，
    /// 扫描器会照 catalog 的意图位办事，不会误删任何东西。
    package static func load() -> ScenarioMountState {
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(ScenarioMountState.self, from: data) else {
            return ScenarioMountState()
        }
        return state
    }

    package static func save(_ state: ScenarioMountState) throws {
        try FileManager.default.createDirectory(at: AtlasPaths.root, withIntermediateDirectories: true)
        if state.suppressed.isEmpty && state.profileID == nil {
            // 空账就把文件删掉，别在仓库里留一个空壳
            try? FileManager.default.removeItem(at: url)
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: url, options: .atomic)
    }

    /// 扫描器用的查询集。每次扫描读一次，不要逐技能读文件。
    package static func suppressedSet() -> Set<SuppressedMount> {
        Set(load().suppressed)
    }

    /// 场景涉及的非 Claude 平台。Claude Code 走 skillOverrides，不在这里处理。
    package static func mountPlatforms(of profile: AtlasProfile) -> [AgentPlatform] {
        (profile.platforms ?? []).compactMap(AgentPlatform.init(rawValue:)).filter { $0 != .claude }
    }

    /// 应用：把非成员技能在指定平台上的软链摘掉，记账。
    ///
    /// 先撤掉上一套（revert），再压新的 —— 两套场景的账不能叠在一起，否则
    /// 第二次撤销会挂回第一套压着的东西，或者反过来永远挂不回来。
    ///
    /// 返回实际摘掉的条数。
    @discardableResult
    package static func apply(
        profile: AtlasProfile,
        skills: [Skill]
    ) throws -> Int {
        try revert(skills: skills)

        let platforms = mountPlatforms(of: profile)
        guard !platforms.isEmpty else { return 0 }

        let members = Set(profile.members)
        var recorded: [SuppressedMount] = []
        let fileManager = FileManager.default

        for skill in skills where !skill.disabled && skill.origin == .atlas && !skill.managed {
            // meta-skill 永不被场景摘掉（ADR-3：它是 agent 找得到这个库的唯一入口）
            if skill.directory == MetaSkill.directory { continue }
            if members.contains(skill.directory) { continue }
            for platform in platforms {
                let link = platform.resolvedRoot(home: AtlasPaths.home)
                    .appendingPathComponent(skill.directory)
                // 本来就没挂（你自己关的）→ 不记账也不碰，撤场景时才不会替你打开
                guard LinkTool.isSymlink(link) || fileManager.fileExists(atPath: link.path) else { continue }
                // 占位是真目录 → 那是别的东西，不是我们挂的，一律不动
                guard LinkTool.isSymlink(link) else { continue }
                try LinkTool.removeOurSymlink(at: link)
                recorded.append(SuppressedMount(directory: skill.directory, platform: platform.rawValue))
            }
        }

        try save(ScenarioMountState(
            profileID: profile.id,
            appliedAt: Int(Date().timeIntervalSince1970),
            suppressed: recorded
        ))
        return recorded.count
    }

    /// 撤销：把账上记着的软链原样挂回，清账。
    ///
    /// 挂回前再确认一次 catalog 仍然说该挂 —— 你可能在场景生效期间明确关掉了某个
    /// 技能，那就尊重你后来的决定，不要挂回去。
    @discardableResult
    package static func revert(skills: [Skill]) throws -> Int {
        let state = load()
        guard !state.suppressed.isEmpty else {
            if state.profileID != nil { try save(ScenarioMountState()) }
            return 0
        }
        let catalog = AtlasCatalog.load()
        let known = Set(skills.map(\.directory))
        var restored = 0

        for entry in state.suppressed {
            guard let platform = AgentPlatform(rawValue: entry.platform) else { continue }
            // 技能已经不在库里了（删了/停用了）→ 没什么可挂回的
            guard known.contains(entry.directory) else { continue }
            guard catalog.skills[entry.directory]?.isEnabled(platform) == true else { continue }
            let root = platform.resolvedRoot(home: AtlasPaths.home)
            let link = root.appendingPathComponent(entry.directory)
            // 场景生效期间你自己在那个位置放了别的东西 → 不覆盖
            if !LinkTool.isSymlink(link), FileManager.default.fileExists(atPath: link.path) { continue }
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try LinkTool.replaceSymlink(
                at: link, pointingTo: SkillActions.activeSource(directory: entry.directory)
            )
            restored += 1
        }

        try save(ScenarioMountState())
        return restored
    }

    /// 你手动点亮某个平台图标时，把这条从账上划掉：手动动作优先于场景。
    /// 否则撤场景时会再挂一次（无害但多余），而账上留着一条早已不成立的记录。
    package static func forget(directory: String, platform: AgentPlatform) {
        var state = load()
        let before = state.suppressed.count
        state.suppressed.removeAll {
            $0.directory == directory && $0.platform == platform.rawValue
        }
        guard state.suppressed.count != before else { return }
        try? save(state)
    }
}
