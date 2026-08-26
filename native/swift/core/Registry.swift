import Foundation

// MARK: - 注册表发现（三期 G6-lite）
//
// 只做「发现」，不做「解析」：搜到结果后把 https://github.com/<owner>/<repo> 填进
// 现有的 URL 输入框，之后完全走既有的 parse → clone → detect → 装前扫描 → 勾选管线。
//
// 为什么砍掉完整版：注册表的 id 第三段是 SKILL.md 的 frontmatter name，不是仓库
// 子目录（实测 45 个高安装量技能里约两成推不出路径），完整版必须靠三四级启发式
// 猜路径，命中率由别人的仓库布局决定、会无声退化；而且那条路要把注册表返回的字符串
// 直接拼进文件系统路径，凭空开出一个路径穿越面。
// 降级版零新增解析、零新增穿越面：唯一的路径入口仍是 InstallerModel.parse（它硬限
// host == github.com）。detect 会扫一层子目录，以及没有 SKILL.md 的目录再往下
// 一层（skills/<name>/SKILL.md）；注册表仍只填仓库根地址，不猜子路径。

package struct RegistrySkill: Identifiable, Hashable, Decodable {
    package var id: String
    package var skillId: String
    package var name: String
    package var installs: Int
    package var source: String

    /// source 恰好一个斜杠才是 owner/repo。smithery.ai、modelscope.cn 这类裸主机名
    /// 是非 GitHub 来源，克隆不了——列表里必须提前置灰，不能让用户点进去才失败。
    /// 只拿 owner 段判点号：GitHub 的用户名与组织名不允许含点，而仓库名允许
    /// （vercel/next.js 是合法仓库），拿整串判会把它们误伤成「外部来源」。
    package var isGitHubBacked: Bool {
        let parts = source.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return false }
        return !parts[0].contains(".")
    }
    package var repoURL: String { "https://github.com/\(source)" }
}

package enum SkillRegistry {
    private struct SearchResponse: Decodable {
        var skills: [RegistrySkill]
    }

    /// 可被 -atlasRegistryBase 覆盖（离线验收指向 file:// 夹具）
    package static var baseURL: String {
        UserDefaults.standard.string(forKey: "atlasRegistryBase") ?? "https://www.skills.sh"
    }

    /// 关掉后界面完全不出现搜索框，也不会有任何出网请求
    package static var enabled: Bool {
        UserDefaults.standard.object(forKey: "atlasRegistryEnabled") as? Bool ?? true
    }

    package enum RegistryError: LocalizedError {
        case unreachable
        package var errorDescription: String? { L("连不上技能注册表，检查网络后重试。") }
    }

    /// 服务端对 <2 字符直接返回 400，本地先拦掉省一次往返
    package static func search(_ query: String) async throws -> [RegistrySkill] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }
        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(baseURL)/api/search?q=\(encoded)") else {
            throw RegistryError.unreachable
        }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 6
        config.timeoutIntervalForResource = 8
        config.waitsForConnectivity = false
        do {
            let (data, response) = try await URLSession(configuration: config).data(from: url)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw RegistryError.unreachable
            }
            return (try? JSONDecoder().decode(SearchResponse.self, from: data))?.skills ?? []
        } catch {
            throw RegistryError.unreachable
        }
    }
}
