import Foundation

/// 命令行 / UserDefaults 调试开关。从 Store.swift 挪到 core：
/// Scanner / Installer 在无 UI 时也要认 `-atlasHome`、`-atlasQuit`。
package enum LaunchArgs {
    package static func value(_ name: String) -> String? {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "-\(name)"), index + 1 < args.count else { return nil }
        let next = args[index + 1]
        if next.hasPrefix("-") { return nil }
        return next
    }

    package static func flag(_ name: String) -> Bool {
        let args = CommandLine.arguments
        if args.contains("-\(name)") { return true }
        if let value = value(name) {
            return ["1", "YES", "yes", "true"].contains(value)
        }
        return false
    }
}
