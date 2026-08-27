import Foundation
#if SWIFT_PACKAGE
import AtlasCore
#endif

// MARK: - atlas install <github-url|owner/repo|本地路径> [--platforms a,b] [--json]
//
// 复用 InstallerModel 的 parse→clone→detect→scan→clonefile 管线。
// 关键级命中：写 pending-review，退出码 3，等人在 GUI 批准后重跑。

@MainActor
enum InstallCommand {
    static func run(_ args: Args) async -> Int32 {
        let raw = args.positionals.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else {
            return fail(op: "install", json: args.json, code: .usage,
                        message: L("用法：atlas install <github-url|owner/repo|本地路径>"))
        }
        let source = expandInstallSource(raw)
        let parsed = parsePlatformList(args.platforms)
        if let message = parsed.error {
            return fail(op: "install", json: args.json, code: .usage,
                        message: message, hint: knownPlatformsList())
        }
        return await install(source: source, platforms: parsed.platforms ?? PreferredPlatforms.current, json: args.json)
    }

    private static func install(source: String, platforms: Set<String>, json: Bool) async -> Int32 {
        guard AtlasLock.acquire(timeout: 5) else {
            return fail(op: "install", json: json, code: .locked,
                        message: L("技能库正在被另一个 Skill Atlas 进程写入，请稍后再试。"))
        }
        defer { AtlasLock.release() }

        let model = InstallerModel()
        model.selectedPlatforms = platforms
        do {
            try await model.prepare(from: source)
        } catch {
            let message = (error as? InstallerModel.InstallError)?.message ?? error.localizedDescription
            let code: ExitCode = message.contains("网络") || message.contains("克隆失败") ? .network : .general
            return fail(op: "install", json: json, code: code, message: message)
        }

        let chosen = model.candidates.filter { $0.selected && !$0.conflict }
        if chosen.isEmpty {
            let conflicts = model.candidates.filter(\.conflict).map(\.directory)
            return fail(op: "install", json: json, code: .conflict,
                        message: L("没有可安装的技能（同名已存在或仓库为空）。"),
                        hint: conflicts.isEmpty ? nil : conflicts.joined(separator: ", "))
        }

        let repo = model.parsedRepoDisplay
        let commit = model.sourceCommit
        let critical = chosen.filter { $0.criticalCount > 0 }
        if !critical.isEmpty {
            let unapproved = critical.filter {
                !PendingReviews.isApproved(repo: repo, commit: commit, dir: $0.directory)
            }
            if !unapproved.isEmpty {
                return emitApprovalRequired(model: model, repo: repo, commit: commit, json: json)
            }
            model.markReviewConfirmed()
        }

        let host = CLIInstallHost()
        model.install(store: host)
        let installed = model.results.filter(\.installed)
        let failed = model.results.filter { !$0.installed }
        Oplog.record(
            actor: "cli", op: "install", target: installed.map(\.directory).joined(separator: ","),
            ok: !installed.isEmpty, detail: model.results.map { "\($0.directory):\($0.note)" }.joined(separator: "; ")
        )
        if installed.isEmpty {
            let conflict = failed.contains { $0.note.contains("同名") }
            return fail(op: "install", json: json, code: conflict ? .conflict : .general,
                        message: failed.first?.note ?? L("安装失败"))
        }
        let data: [String: Any] = [
            "installed": installed.map { ["dir": $0.directory, "note": $0.note] },
            "skipped": failed.map { ["dir": $0.directory, "note": $0.note] },
            "platforms": Array(platforms).sorted(),
            "commit": commit,
        ]
        return succeed(op: "install", json: json, data: data) {
            for row in model.results { say("\(row.directory)\t\(row.note)") }
        }
    }

    private static func emitApprovalRequired(model: InstallerModel, repo: String, commit: String, json: Bool) -> Int32 {
        let dirs = model.candidates.filter { $0.selected }.map(\.directory)
        let token = PendingReviews.token(url: repo, commit: commit, dirs: dirs)
        let findings = model.candidates.flatMap { candidate in
            candidate.findings.filter { $0.severity == .critical }.map {
                PendingReview.Finding(
                    severity: "critical", rule: $0.rule, file: $0.file,
                    line: $0.line, excerpt: $0.excerpt, directory: candidate.directory
                )
            }
        }
        let review = PendingReview(
            token: token,
            createdAt: Int(Date().timeIntervalSince1970),
            source: .init(url: repo, branch: "main", commit: commit),
            candidates: model.candidates.map {
                .init(dir: $0.directory, name: $0.displayName, desc: truncatedDescription($0.description))
            },
            findings: findings,
            requestedBy: "cli"
        )
        do {
            try PendingReviews.save(review)
        } catch {
            return fail(op: "install", json: json, code: .general, message: error.localizedDescription)
        }
        let url = "skillatlas://review/\(token)"
        let payload: [String: Any] = [
            "reviewToken": token,
            "reviewURL": url,
            "findings": findings.map {
                ["severity": $0.severity, "rule": $0.rule, "file": $0.file,
                 "line": $0.line, "excerpt": $0.excerpt, "dir": $0.directory] as [String: Any]
            },
        ]
        if json {
            JSONOut.emit(op: "install", ok: false, code: .approvalRequired, data: payload,
                         error: (L("安装需要人批准：关键级安全命中。把 reviewURL 交给用户，停下等待，然后重跑同一条 install。"), url))
        } else {
            say(L("安装需要人批准：关键级安全命中。"))
            say(url)
            say(L("在 Skill Atlas 里打开这条链接批准后，重跑同一条 install。"))
        }
        return ExitCode.approvalRequired.rawValue
    }
}

@MainActor
final class CLIInstallHost: InstallHost {
    var skills: [Skill] = []
    func pauseWatching() {}
    func resumeWatching() {}
    func select(_ name: String) {}
    func rescan(keepSelection: Bool) async {}
}
