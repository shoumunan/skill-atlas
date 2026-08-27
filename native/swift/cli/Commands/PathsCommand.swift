import Foundation
#if SWIFT_PACKAGE
import AtlasCore
#endif

// MARK: - atlas paths [--json]
//
// 诊断用：打印 AtlasPaths 的关键路径 + 锁/oplog 文件位置 + ATLAS_HOME 是否生效。

enum PathsCommand {
    private static let orderedKeys = [
        "home", "root", "library", "disabled", "backups", "patches",
        "catalog", "usageIndex", "securityIndex", "migrationLog", "lock", "oplog",
    ]

    static func run(_ args: Args) -> Int32 {
        let env = ProcessInfo.processInfo.environment["ATLAS_HOME"]
        var data: [String: Any] = [
            "home": AtlasPaths.home.path,
            "root": AtlasPaths.root.path,
            "library": AtlasPaths.libraryRoot.path,
            "disabled": AtlasPaths.disabledRoot.path,
            "backups": AtlasPaths.backupsRoot.path,
            "patches": AtlasPaths.patchesRoot.path,
            "catalog": AtlasPaths.catalogURL.path,
            "usageIndex": AtlasPaths.usageIndexURL.path,
            "securityIndex": AtlasPaths.securityIndexURL.path,
            "migrationLog": AtlasPaths.migrationLog.path,
            "lock": AtlasLock.lockURL.path,
            "oplog": Oplog.url.path,
        ]
        data["atlasHomeEnv"] = jsonOrNull(env)

        return succeed(op: "paths", json: args.json, data: data) {
            say(L("诊断路径"))
            for key in orderedKeys {
                say("\(key): \(data[key] as? String ?? "")")
            }
        }
    }
}
