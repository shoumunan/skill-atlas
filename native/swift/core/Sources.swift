import Foundation

// MARK: - 多源发现（2.1 ADR-15）
//
// 市场只是发现层：每个源提供搜索与精选，结果统一为 SourceHit；安装一律汇入既有
// 管线——GitHub 型走 InstallerModel（装前扫描 / 审批一道不少），SkillHub 托管型
// 先打开网页（zip 通道 = ADR-16，WP-M 残项）。评分、认证、审核标签只作展示，
// 不减免任何本地门。新市场源三关：公开只读 API / 匿名安装物 / 内容寻址
//（护栏 §7-19），接入只改本文件。出网受 SkillRegistry.enabled 总闸 + 每源开关双控。

package enum SourceKind: String, CaseIterable, Identifiable {
    case skillssh
    case skillhub

    package var id: String { rawValue }

    package var displayName: String {
        switch self {
        case .skillssh: return "skills.sh"
        case .skillhub: return "SkillHub"
        }
    }

    /// 每源独立开关；`atlasRegistryEnabled` 是总闸（关掉即全部市场搜索零出网）
    package var enabledKey: String {
        switch self {
        case .skillssh: return "atlasSourceSkillsSh"
        case .skillhub: return "atlasSourceSkillHub"
        }
    }

    package var enabled: Bool {
        guard SkillRegistry.enabled else { return false }
        return UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }
}

package struct SourceHit: Identifiable, Equatable {
    package var kind: SourceKind
    /// 源内主键（skills.sh 的 owner/repo；SkillHub 的 @handle/slug）
    package var key: String
    package var name: String
    package var summary: String
    /// 排名指标（skills.sh 装机数 / SkillHub 下载数），只用于排序与展示
    package var metric: Int
    /// GitHub 型：进既有安装管线
    package var repoURL: String?
    /// 托管型或非 GitHub：打开网页
    package var webURL: String?
    /// SkillHub 企业认证名（仅展示，不改变任何门槛）
    package var publisher: String?
    package var requiresKey: Bool
    package var version: String?

    package var id: String { "\(kind.rawValue):\(key)" }

    package init(kind: SourceKind, key: String, name: String, summary: String, metric: Int,
                 repoURL: String?, webURL: String?, publisher: String?, requiresKey: Bool, version: String?) {
        self.kind = kind
        self.key = key
        self.name = name
        self.summary = summary
        self.metric = metric
        self.repoURL = repoURL
        self.webURL = webURL
        self.publisher = publisher
        self.requiresKey = requiresKey
        self.version = version
    }
}

package enum SkillSources {
    /// 聚合搜索：各源并发、各自超时降级，一源失败不拖垮整体。
    /// 去重：同一 GitHub 仓库多源出现时按 metric 高者留一条。
    package static func search(_ query: String, only: SourceKind? = nil) async -> [SourceHit] {
        var hits: [SourceHit] = []
        await withTaskGroup(of: [SourceHit].self) { group in
            for kind in SourceKind.allCases where kind.enabled && (only == nil || only == kind) {
                group.addTask { (try? await fetch(kind: kind, query: query)) ?? [] }
            }
            for await part in group { hits.append(contentsOf: part) }
        }
        var seenRepos = Set<String>()
        var out: [SourceHit] = []
        for hit in hits.sorted(by: { $0.metric > $1.metric }) {
            if let repo = hit.repoURL?.lowercased() {
                guard seenRepos.insert(repo).inserted else { continue }
            }
            out.append(hit)
        }
        return out
    }

    /// 精选榜（空搜索词）：SkillHub score 榜。skills.sh 无榜单端点。
    package static func featured() async -> [SourceHit] {
        guard SourceKind.skillhub.enabled else { return [] }
        return (try? await skillHubList(query: nil)) ?? []
    }

    private static func fetch(kind: SourceKind, query: String) async throws -> [SourceHit] {
        switch kind {
        case .skillssh: return try await skillsShSearch(query)
        case .skillhub: return try await skillHubList(query: query)
        }
    }

    // MARK: skills.sh（既有 Registry 的适配面，Registry 纪律照旧：只填仓库地址不猜子路径）

    private static func skillsShSearch(_ query: String) async throws -> [SourceHit] {
        try await SkillRegistry.search(query).map { hit in
            SourceHit(
                kind: .skillssh,
                key: hit.source,
                name: hit.name,
                summary: hit.source,
                metric: hit.installs,
                repoURL: hit.isGitHubBacked ? hit.repoURL : nil,
                webURL: hit.isGitHubBacked ? nil : "https://www.skills.sh",
                publisher: nil,
                requiresKey: false,
                version: nil
            )
        }
    }

    // MARK: SkillHub（腾讯；端点契约 2026-08-27 实测，见 PLAN §5-M。接口变更时静默降级为空）

    /// 可被夹具覆盖（离线验收指向本地 HTTP / file 夹具）
    package static var skillHubBase: String {
        UserDefaults.standard.string(forKey: "atlasSkillHubBase") ?? "https://api.skillhub.cn"
    }

    private struct SkillHubEnvelope: Decodable {
        var code: Int
        var data: SkillHubData?
    }

    /// 单条解码失败只丢那一条，不炸整包（实测有记录的 score 是小数，严格 Int 解码会整包失败）
    private struct Lossy<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: Decoder) {
            value = try? T(from: decoder)
        }
    }

    private struct SkillHubData: Decodable {
        var skills: [Lossy<SkillHubSkill>]
    }

    private struct SkillHubSkill: Decodable {
        struct Namespace: Decodable {
            var canonicalName: String?
            var handle: String?
            var publicSlug: String?
        }
        struct Publisher: Decodable {
            var name: String?
            var verified: Bool?
            var certifiedName: String?
        }
        var name: String
        var description_zh: String?
        var description: String?
        // 实测既有整数也有小数（score 52144.366…），一律按 Double 收
        var downloads: Double?
        var score: Double?
        var version: String?
        var upstream_url: String?
        var labels: [String: String]?
        var namespace: Namespace?
        var publisher: Publisher?
    }

    private static func skillHubList(query: String?) async throws -> [SourceHit] {
        var components = URLComponents(string: "\(skillHubBase)/api/skills")
        var items = [
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "pageSize", value: "20"),
        ]
        if let query, !query.isEmpty {
            // 实测坑：带 sortBy 时服务端会忽略 search，所以搜索请求不带排序参数
            items.append(URLQueryItem(name: "search", value: query))
        } else {
            items.append(URLQueryItem(name: "sortBy", value: "score"))
            items.append(URLQueryItem(name: "order", value: "desc"))
        }
        components?.queryItems = items
        guard let url = components?.url else { return [] }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 6
        config.timeoutIntervalForResource = 8
        config.waitsForConnectivity = false
        let (data, response) = try await URLSession(configuration: config).data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return [] }
        let envelope = try JSONDecoder().decode(SkillHubEnvelope.self, from: data)
        guard envelope.code == 0, let skills = envelope.data?.skills.compactMap(\.value) else { return [] }
        return skills.compactMap { skill in
            let handle = skill.namespace?.handle ?? ""
            let slug = skill.namespace?.publicSlug ?? ""
            let canonical = skill.namespace?.canonicalName ?? "@\(handle)/\(slug)"
            guard !handle.isEmpty, !slug.isEmpty else { return nil }
            let upstream = skill.upstream_url
            let isGitHub = upstream?.lowercased().hasPrefix("https://github.com/") == true
            let summary = (skill.description_zh ?? skill.description ?? "")
                .replacingOccurrences(of: "\n", with: " ")
            return SourceHit(
                kind: .skillhub,
                key: canonical,
                name: skill.name,
                summary: String(summary.prefix(120)),
                metric: Int(skill.downloads ?? skill.score ?? 0),
                repoURL: isGitHub ? upstream : nil,
                webURL: "https://skillhub.cn/skills/\(handle)/\(slug)",
                publisher: (skill.publisher?.verified == true)
                    ? (skill.publisher?.certifiedName ?? skill.publisher?.name)
                    : nil,
                requiresKey: skill.labels?["requires_api_key"] == "true",
                version: skill.version
            )
        }
    }
}
