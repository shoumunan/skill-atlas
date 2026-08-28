import Foundation
import Dispatch
#if SWIFT_PACKAGE
import AtlasCore
#endif

// MARK: - atlas search <q> [--remote] [--json]

enum SearchCommand {
    static func run(_ args: Args) -> Int32 {
        let query = args.positionals.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        guard query.count >= 2 else {
            return fail(op: "search", json: args.json, code: .usage, message: L("搜索词至少两个字符。"))
        }

        let scanData: AtlasData
        do {
            scanData = try SkillScanner.scan()
        } catch {
            return fail(op: "search", json: args.json, code: .general, message: error.localizedDescription)
        }
        let usage = UsageIndexer.loadCached()

        // 本地匹配：直配 + 任务别名扩展（Rules.recommendAliases，与库页搜索框同一口径）
        let lowered = query.lowercased()
        var tokens = [lowered]
        for (key, values) in Rules.recommendAliases where lowered.contains(key) {
            tokens.append(contentsOf: values.map { $0.lowercased() })
        }
        let local = scanData.skills.filter { skill in
            tokens.contains { skill.searchText.contains($0) }
        }

        var remoteJSON: Any = NSNull()
        var remoteError: Any = NSNull()
        if args.remote {
            // --source 走多源聚合（ADR-15 增量面，2.1 唯一放行的 CLI 新参数）；
            // 不带 --source 保持 2.0 的 skills.sh 单源路径与输出结构，一个字不动（ADR-12）。
            if let sourceRaw = args.source {
                let only: SourceKind?
                switch sourceRaw {
                case "all", "": only = nil
                case "skillssh": only = .skillssh
                case "skillhub": only = .skillhub
                default:
                    return fail(op: "search", json: args.json, code: .usage,
                                message: LF("未知来源「%@」", sourceRaw),
                                hint: "--source skillssh|skillhub|all")
                }
                if !SkillRegistry.enabled {
                    remoteError = L("远程搜索不可用（已关闭或连不上）")
                } else {
                    switch runSync({ await SkillSources.search(query, only: only) }) {
                    case .success(let hits):
                        remoteJSON = hits.map { hit -> [String: Any] in
                            [
                                "id": hit.id,
                                "sourceKind": hit.kind.rawValue,
                                "key": hit.key,
                                "name": hit.name,
                                "summary": hit.summary,
                                "metric": hit.metric,
                                "repoURL": jsonOrNull(hit.repoURL),
                                "webURL": jsonOrNull(hit.webURL),
                                "publisher": jsonOrNull(hit.publisher),
                                "requiresKey": hit.requiresKey,
                                "version": jsonOrNull(hit.version),
                            ]
                        }
                    case .failure:
                        remoteError = L("远程搜索不可用（已关闭或连不上）")
                    }
                }
            } else if !SkillRegistry.enabled {
                remoteError = L("远程搜索不可用（已关闭或连不上）")
            } else {
                switch runSync({ try await SkillRegistry.search(query) }) {
                case .success(let results):
                    remoteJSON = results.map { result -> [String: Any] in
                        [
                            "id": result.id,
                            "skillId": result.skillId,
                            "name": result.name,
                            "installs": result.installs,
                            "source": result.source,
                            "isGitHubBacked": result.isGitHubBacked,
                            "repoURL": result.repoURL,
                        ]
                    }
                case .failure:
                    remoteError = L("远程搜索不可用（已关闭或连不上）")
                }
            }
        }

        let data: [String: Any] = [
            "query": query,
            "local": local.map { listEntryJSON($0, usage: usage) },
            "remote": remoteJSON,
            "remoteError": remoteError,
        ]
        return succeed(op: "search", json: args.json, data: data) {
            say(LF("共 %d 项", local.count))
            for skill in local {
                say("\(skill.name)\t\(skill.directory)")
            }
        }
    }

    // MARK: 同步桥接 async（唯一用途：--remote 时调一次 SkillRegistry.search）
    //
    // 不把 main() 改成 async——ADR-2 的兜底构建路径已经很脆（-parse-as-library +
    // 非 main.swift 命名），没必要为一个可选分支牵动入口签名。语义靠 semaphore
    // 的 signal/wait 建立 happens-before，box 用 @unchecked Sendable 免去误报。

    private final class ResultBox<T>: @unchecked Sendable {
        var value: Result<T, Error>?
    }

    private static func runSync<T>(_ operation: @escaping () async throws -> T) -> Result<T, Error> {
        let semaphore = DispatchSemaphore(value: 0)
        let box = ResultBox<T>()
        Task {
            do {
                box.value = .success(try await operation())
            } catch {
                box.value = .failure(error)
            }
            semaphore.signal()
        }
        semaphore.wait()
        return box.value ?? .failure(AtlasError("internal: runSync 没有结果"))
    }
}
