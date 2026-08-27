import CryptoKit
import Foundation

// MARK: - CLI 安装审批握手（ADR-4）
//
// 关键级安全命中：写 pending-reviews/<token>.json，退出码 3，深链唤起 GUI。
// 人在 App 里批准后写入 approvals.json（键 = sha256(repo@commit/dir)）。
// 上游偷偷改代码 → commit 变了 → 旧批准自动失效。

package struct PendingReview: Codable {
    package var token: String
    package var createdAt: Int
    package var source: Source
    package var candidates: [Candidate]
    package var findings: [Finding]
    package var requestedBy: String

    package struct Source: Codable {
        package var url: String
        package var branch: String
        package var commit: String
        package init(url: String, branch: String, commit: String) {
            self.url = url; self.branch = branch; self.commit = commit
        }
    }

    package struct Candidate: Codable {
        package var dir: String
        package var name: String
        package var desc: String
        package init(dir: String, name: String, desc: String) {
            self.dir = dir; self.name = name; self.desc = desc
        }
    }

    package struct Finding: Codable {
        package var severity: String
        package var rule: String
        package var file: String
        package var line: Int
        package var excerpt: String
        package var directory: String
        package init(severity: String, rule: String, file: String, line: Int, excerpt: String, directory: String) {
            self.severity = severity; self.rule = rule; self.file = file
            self.line = line; self.excerpt = excerpt; self.directory = directory
        }
    }

    package init(token: String, createdAt: Int, source: Source, candidates: [Candidate], findings: [Finding], requestedBy: String) {
        self.token = token; self.createdAt = createdAt; self.source = source
        self.candidates = candidates; self.findings = findings; self.requestedBy = requestedBy
    }
}

package enum PendingReviews {
    package static var root: URL { AtlasPaths.root.appendingPathComponent("pending-reviews") }
    package static var approvalsURL: URL { AtlasPaths.root.appendingPathComponent("approvals.json") }

    package static func token(url: String, commit: String, dirs: [String]) -> String {
        hex12(url + commit + dirs.sorted().joined(separator: ","))
    }

    package static func approvalKey(repo: String, commit: String, dir: String) -> String {
        sha256Hex("\(repo)@\(commit)/\(dir)")
    }

    package static func save(_ review: PendingReview) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("\(review.token).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(review).write(to: url, options: .atomic)
    }

    package static func load(_ token: String) -> PendingReview? {
        let url = root.appendingPathComponent("\(token).json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PendingReview.self, from: data)
    }

    package static func list() -> [PendingReview] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else {
            return []
        }
        return files.filter { $0.pathExtension == "json" }
            .compactMap { try? JSONDecoder().decode(PendingReview.self, from: Data(contentsOf: $0)) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    package static func remove(_ token: String) {
        try? FileManager.default.removeItem(at: root.appendingPathComponent("\(token).json"))
    }

    package static func isApproved(repo: String, commit: String, dir: String) -> Bool {
        loadApprovals().entries[approvalKey(repo: repo, commit: commit, dir: dir)] != nil
    }

    package static func approve(repo: String, commit: String, dirs: [String]) throws {
        var file = loadApprovals()
        let now = Int(Date().timeIntervalSince1970)
        for dir in dirs {
            file.entries[approvalKey(repo: repo, commit: commit, dir: dir)] = ApprovalEntry(approvedAt: now)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: AtlasPaths.root, withIntermediateDirectories: true)
        try encoder.encode(file).write(to: approvalsURL, options: .atomic)
    }

    private struct ApprovalsFile: Codable {
        var version: Int = 1
        var entries: [String: ApprovalEntry] = [:]
    }

    private struct ApprovalEntry: Codable {
        var approvedAt: Int
    }

    private static func loadApprovals() -> ApprovalsFile {
        guard let data = try? Data(contentsOf: approvalsURL),
              let file = try? JSONDecoder().decode(ApprovalsFile.self, from: data) else {
            return ApprovalsFile()
        }
        return file
    }

    private static func sha256Hex(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func hex12(_ text: String) -> String {
        String(sha256Hex(text).prefix(12))
    }
}

package enum GitRev {
    package static func head(in dir: URL) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", dir.path, "rev-parse", "HEAD"]
        process.currentDirectoryURL = dir
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.count >= 7 ? text : "local"
    }
}
