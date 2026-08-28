import Foundation

// MARK: - 平台技能目录覆盖（2.1.1）
//
// 为什么要可改：不是所有 agent 都把技能放在固定的 `~/.<name>/skills`。
// 豆包这类「办公模式」读的是**用户在它里面指定的文件夹**，写死路径会让同步
// 点亮却实际无效——那比不支持更糟。
//
// 存文件而不是 UserDefaults：App 与 CLI 是两个可执行文件、两个 UserDefaults
// 域（见 cli/Shared.swift 的注记），只有落到 ~/.skill-atlas/ 下的文件才能让
// 两边看到同一份配置。

package enum PlatformRoots {
    package static var url: URL { AtlasPaths.root.appendingPathComponent("platform-roots.json") }

    /// 进程内缓存：root(home:) 在渲染路径上被高频调用，不能每次读盘。
    /// 键 = (修改时间, 大小)，外部改文件后自动重读。
    private nonisolated(unsafe) static var cache: (key: String, map: [String: String])?

    package static func all() -> [String: String] {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let modified = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let size = (attributes?[.size] as? Int) ?? 0
        let key = "\(modified)|\(size)"
        if let cache, cache.key == key { return cache.map }
        var map: [String: String] = [:]
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            map = decoded
        }
        cache = (key, map)
        return map
    }

    /// 覆盖路径（已展开 ~）。空字符串视为未设置。
    package static func override(for platform: AgentPlatform) -> URL? {
        guard let raw = all()[platform.rawValue]?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: (raw as NSString).expandingTildeInPath, isDirectory: true)
    }

    /// 传 nil 清除覆盖，恢复内置默认路径
    package static func set(_ path: String?, for platform: AgentPlatform) throws {
        var map = all()
        let trimmed = path?.trimmingCharacters(in: .whitespaces) ?? ""
        if trimmed.isEmpty {
            map.removeValue(forKey: platform.rawValue)
        } else {
            map[platform.rawValue] = trimmed
        }
        try FileManager.default.createDirectory(at: AtlasPaths.root, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(map).write(to: url, options: .atomic)
        cache = nil
    }
}
