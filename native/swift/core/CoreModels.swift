import Foundation

// MARK: - 基础模型（与历史 JSON 结构一一对应）
//
// 本文件是 AtlasCore 的一部分：只放纯数据结构与不依赖 UI 框架的逻辑。
// 颜色 / SF Symbol 等 UI 元数据在 app/ModelsUI.swift（对本文件类型做 extension）。
// 病根：原先整文件依赖 SwiftUI（颜色类型），CLI 与核心层无法共享。

package enum Health: String, CaseIterable {
    case healthy, warning, error

    package var label: String {
        switch self {
        case .healthy: return L("健康")
        case .warning: return L("警告")
        case .error: return L("异常")
        }
    }
}

package enum MountStatus: String {
    case ok, disabled, missing, broken, wrong, directory, unexpected

    package var label: String {
        switch self {
        case .ok: return L("已挂载")
        case .disabled: return L("未启用")
        case .missing: return L("缺失")
        case .broken: return L("断链")
        case .wrong: return L("目标错误")
        case .directory: return L("普通目录")
        case .unexpected: return L("未启用但存在")
        }
    }
}

package struct Mount: Equatable {
    package var enabled: Bool
    package var status: MountStatus
    package var path: String
    package var isLink: Bool
    package var target: String

    package init(enabled: Bool, status: MountStatus, path: String, isLink: Bool, target: String) {
        self.enabled = enabled
        self.status = status
        self.path = path
        self.isLink = isLink
        self.target = target
    }
}

/// 技能来源：CC Switch 管理 or 用户直接装在 ~/.claude/skills、~/.codex/skills 的本地技能
package enum SkillOrigin: String, CaseIterable, Equatable {
    case atlas, ccSwitch, local

    package var label: String {
        switch self {
        case .atlas: return "Skill Atlas"
        case .ccSwitch: return "CC Switch"
        case .local: return L("本地安装")
        }
    }
}

package struct Skill: Identifiable, Equatable {
    package var id: String { name }
    package var dbId: Int
    package var name: String
    package var directory: String
    package var description: String
    package var category: String
    package var whenToUse: String
    package var examplePrompts: [String]
    package var platforms: [String]
    package var sourcePath: String
    package var skillFile: String
    package var repo: String
    package var repoOwner: String = ""
    package var repoName: String = ""
    package var repoBranch: String = "main"
    package var installedAt: Int
    package var updatedAt: Int
    package var health: Health
    package var problems: [String]
    /// 各平台挂载态。缺省平台视为未启用。
    package var mounts: [AgentPlatform: Mount]
    package var origin: SkillOrigin
    /// 已停用（本地技能被移入 .disabled/）：灰显、不计入健康统计与可用数
    package var disabled: Bool = false
    /// 关联 git 仓库有可拉取的新提交（后台检查后写入）
    package var updateAvailable: Bool = false
    /// catalog.managed；meta-skill 为 true。默认 false 让旧初始化点不用改这个参数。
    package var managed: Bool = false
    package var searchText: String

    package func mount(_ platform: AgentPlatform) -> Mount {
        mounts[platform] ?? Mount(enabled: false, status: .disabled, path: "", isLink: false, target: "")
    }

    package var mountClaude: Mount { mount(.claude) }
    package var mountCodex: Mount { mount(.codex) }
}

package struct Summary {
    package var total: Int
    /// 平台 label → 启用数（跨来源）
    package var enabled: [String: Int]
    /// 平台 label → 挂载验证通过数
    package var verified: [String: Int]
    package var enabledCodex: Int { enabled["Codex"] ?? 0 }
    package var enabledClaude: Int { enabled["Claude"] ?? 0 }
    package var enabledGrokBuild: Int { enabled["GrokBuild"] ?? 0 }
    package var verifiedCodex: Int { verified["Codex"] ?? 0 }
    package var verifiedClaude: Int { verified["Claude"] ?? 0 }
    package var codexCount: Int { enabledCodex }
    package var claudeCount: Int { enabledClaude }
    package var ccSwitchCount: Int
    package var localCount: Int
    package var atlasCount: Int
    /// CC Switch 数据库是否存在（决定统计带/健康页文案的来源感知）
    package var hasCCSwitch: Bool
    /// 已从 CC Switch 迁入 Skill Atlas 库
    package var migrated: Bool
    package var health: [Health: Int]
    package var sourceRoot: String
    package var database: String
    /// 扫描时实际检查过的路径（空状态引导页展示）
    package var checkedPaths: [String]
    package var scannedAt: Date
}

package struct AtlasData {
    package var skills: [Skill]
    package var summary: Summary
}

// MARK: - 规则常量（分类 / 示例 / 别名；不依赖 UI）

package enum Rules {
    /// 分类关键词，顺序即优先级
    package static let categoryRules: [(String, [String])] = [
        ("基金与投研", ["fund", "基金", "stock", "股票", "finance", "投研", "研报", "wind"]),
        ("社交内容", ["xiaohongshu", "douyin", "wechat", "social", "copywriter", "writer", "文案", "内容", "热点"]),
        ("演示与文档", ["ppt", "slide", "deck", "docx", "document", "pdf", "spreadsheet", "excel", "notebook"]),
        ("网页与自动化", ["browser", "playwright", "chrome", "scrap", "web-access", "computer-use", "automation", "phone-harness"]),
        ("视觉与设计", ["image", "illustration", "canvas", "design", "frontend", "ui", "visual", "card", "gif"]),
        ("数据与研究", ["data", "research", "analytics", "report", "kpi", "market", "metric", "scraper"]),
        ("沟通与运营", ["email", "gmail", "outlook", "slack", "internal-comms", "account-executive", "strategy", "boss"]),
        ("开发与工具", ["mcp", "api", "coding", "code", "github", "cloudflare", "vercel", "skill-creator", "plugin", "agent"]),
        ("思考与协作", ["dbs", "think", "learn", "check", "review", "goal", "retro", "deconstruct"]),
    ]

    /// 手工维护的高质量示例
    package static let examplePrompts: [String: [String]] = [
        "fund-content-creative": [
            "根据这些要点，写一段给同事看的市场说明（不超过 200 字）",
            "把这份材料改成三条并列的结论，每条一句话",
        ],
        "browser-use": [
            "打开这个网页，帮我填写表单并截图确认",
            "从这个页面提取表格数据，保留来源链接",
        ],
        "weekly-video-data": [
            "采集本周抖音、视频号和 B 站视频数据，更新现有周报",
            "核对这周发布的视频，并区分常规短视频和直播切片",
        ],
        "pptx": [
            "读取这份 PPT，帮我梳理每页核心信息",
            "用这份模板制作一份 12 页汇报，并保留原版式",
        ],
        "humanizer-zh": [
            "把这段中文改得更自然，去掉 AI 腔但不要改变意思",
            "审阅这篇文章，标出并修复生硬、空泛的表达",
        ],
    ]

    package static let whenTemplates: [String: String] = [
        "基金与投研": "当任务涉及基金内容、金融数据、投资研究或市场信息时调用。",
        "社交内容": "当你要策划、撰写或改造社交媒体内容时调用。",
        "演示与文档": "当任务需要读取、创建或修改演示稿与办公文档时调用。",
        "网页与自动化": "当任务需要操作真实网页、采集页面信息或自动执行步骤时调用。",
        "视觉与设计": "当任务需要界面、图片、视觉物料或设计判断时调用。",
        "数据与研究": "当任务需要采集、验证、分析数据或形成研究结论时调用。",
        "沟通与运营": "当任务涉及沟通材料、客户协作或内容运营时调用。",
        "开发与工具": "当任务涉及代码、API、MCP、部署或开发工具时调用。",
        "思考与协作": "当问题需要结构化思考、复盘、审查或多人协作时调用。",
    ]

    package static let exampleTemplates: [String: String] = [
        "基金与投研": "请使用 %@ 帮我完成这项基金或投研任务：<写清目标和时间范围>",
        "社交内容": "请使用 %@ 把这份素材做成适合目标平台发布的内容",
        "演示与文档": "请使用 %@ 处理这个文件，并保持原有结构和格式",
        "网页与自动化": "请使用 %@ 打开目标页面，完成操作并给我验证结果",
        "视觉与设计": "请使用 %@ 根据这份需求生成或优化视觉方案",
        "数据与研究": "请使用 %@ 收集并验证这项数据，标明口径和来源",
        "沟通与运营": "请使用 %@ 整理这次沟通，并输出可执行的下一步",
        "开发与工具": "请使用 %@ 完成这个技术任务，并验证结果",
        "思考与协作": "请使用 %@ 分析这个问题，指出关键判断和下一步",
    ]

    /// 推荐引擎的中文别名扩展（移植自历史 web 端 recommend()）
    package static let recommendAliases: [String: [String]] = [
        "基金": ["fund", "基金", "投教", "投研"],
        "视频": ["video", "视频", "抖音", "bilibili"],
        "周报": ["weekly", "report", "周报"],
        "ppt": ["ppt", "slide", "deck", "演示"],
        "网页": ["browser", "web", "网页", "chrome", "playwright"],
        "图片": ["image", "视觉", "设计", "illustration"],
        "文案": ["copy", "writer", "文案", "写作", "human"],
        "数据": ["data", "analytics", "数据", "excel"],
        "邮件": ["email", "gmail", "outlook", "邮件"],
        "小红书": ["xiaohongshu", "小红书", "xhs"],
    ]
}

// MARK: - 小工具

package enum Format {
    package static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter
    }()

    package static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    package static func day(fromUnix timestamp: Int) -> String {
        guard timestamp > 0 else { return L("未知") }
        return day.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
    }
}
