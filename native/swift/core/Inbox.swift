import CryptoKit
import Foundation

// MARK: - 收件箱（2.1 ADR-10）
//
// 渲染时聚合，不建新采集面：九类事项全部来自既有引擎（PendingReviews / SecurityScan /
// Doctor / MissDetect / UpdateChecker / RxFollowup），这里只定统一条目模型、内容寻址
// id、排序与裁决记录。唯一新增持久化是 inbox-state.json（忽略与清零时间）。
// 条目 id 内容寻址：源头内容一变 id 即变，旧的忽略自动失效。

package enum InboxKind: String, CaseIterable, Codable {
    case approval
    case securityCritical = "security_critical"
    case securityWarning = "security_warning"
    case mount
    case miss
    case update
    case overlap
    case overlong
    case rx

    /// 0 挡住使用 / 1 建议处理 / 2 整理
    package var severity: Int {
        switch self {
        case .approval, .securityCritical, .mount: return 0
        case .miss, .update, .securityWarning: return 1
        case .overlap, .overlong, .rx: return 2
        }
    }

    /// 同 severity 内的固定顺序（approval 永远最先）
    package var rank: Int {
        switch self {
        case .approval: return 0
        case .securityCritical: return 1
        case .mount: return 2
        case .miss: return 3
        case .update: return 4
        case .securityWarning: return 5
        case .overlap: return 6
        case .overlong: return 7
        case .rx: return 8
        }
    }

    /// 安全关键、挡住使用、待审批不许被静音（护栏 §7-17）
    package var ignorable: Bool {
        switch self {
        case .approval, .securityCritical, .mount: return false
        default: return true
        }
    }
}

package struct InboxItem: Identifiable, Equatable {
    package var kind: InboxKind
    /// 技能目录名或审批 token
    package var target: String
    package var title: String
    package var detail: String
    /// 内容寻址基材：源头状态一变，digest 变，id 随之变
    package var digest: String
    package var skillName: String?

    package var id: String { "\(kind.rawValue):\(target):\(Inbox.hash8(digest))" }
    package var deepLink: String { "skillatlas://inbox/\(id)" }

    package init(kind: InboxKind, target: String, title: String, detail: String,
                 digest: String, skillName: String? = nil) {
        self.kind = kind
        self.target = target
        self.title = title
        self.detail = detail
        self.digest = digest
        self.skillName = skillName
    }
}

package enum Inbox {
    /// 深链 inbox/<id> 的待定位条目（App 设置，页面消费后清空）
    package static var pendingFocusID: String?

    package static func hash8(_ text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined().prefix(8).lowercased()
    }

    package static func sorted(_ items: [InboxItem]) -> [InboxItem] {
        items.sorted {
            if $0.kind.severity != $1.kind.severity { return $0.kind.severity < $1.kind.severity }
            if $0.kind.rank != $1.kind.rank { return $0.kind.rank < $1.kind.rank }
            return $0.title.localizedCompare($1.title) == .orderedAscending
        }
    }
}

// MARK: - 裁决记录（inbox-state.json）

package enum InboxState {
    package struct Decision: Codable, Equatable {
        package var action: String
        package var at: Int
    }

    package struct FileData: Codable {
        package var version: Int = 1
        package var decisions: [String: Decision] = [:]
        // 今后新增字段一律 Optional——理由同 AtlasSkillRecord
    }

    package static var url: URL { AtlasPaths.root.appendingPathComponent("inbox-state.json") }

    /// 进程内缓存：侧栏徽标每次求值都要问「这条裁决了没」，不能每次读盘
    private static var cache: FileData?

    package static func load() -> FileData {
        if let cache { return cache }
        guard let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(FileData.self, from: data) else {
            let empty = FileData()
            cache = empty
            return empty
        }
        cache = file
        return file
    }

    package static func decided(_ id: String) -> Bool {
        load().decisions[id] != nil
    }

    /// 最近一次裁决时间（清零态的「上次清零」口径）
    package static var lastDecisionAt: Int? {
        load().decisions.values.map(\.at).max()
    }

    package enum DecideResult: Equatable {
        case ok
        case notIgnorable
        case failed(String)
    }

    /// 裁决落盘。区分「这一类不能忽略」与「写盘失败」——以前两者都返回 false，
    /// 磁盘满被伪装成产品规则。
    @discardableResult
    package static func decide(id: String, kind: InboxKind, action: String) -> DecideResult {
        if action == "ignored" && !kind.ignorable { return .notIgnorable }
        var file = load()
        file.decisions[id] = Decision(action: action, at: Int(Date().timeIntervalSince1970))
        // 只增不减会无限膨胀：超过 500 条时把最老的一半清掉（源头早已变化，id 不会再复现）
        if file.decisions.count > 500 {
            let sorted = file.decisions.sorted { $0.value.at > $1.value.at }
            file.decisions = Dictionary(uniqueKeysWithValues: sorted.prefix(250).map { ($0.key, $0.value) })
        }
        do {
            try FileManager.default.createDirectory(at: AtlasPaths.root, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(file).write(to: url, options: .atomic)
            cache = file
            Oplog.append(op: "inbox-decide", target: id, ok: true, detail: action)
            return .ok
        } catch {
            cache = nil
            Oplog.append(op: "inbox-decide", target: id, ok: false, detail: error.localizedDescription)
            return .failed(error.localizedDescription)
        }
    }
}
