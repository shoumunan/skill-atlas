import Foundation
#if SWIFT_PACKAGE
import AtlasCore
#endif

/// WP0 骨架：只保证 target 能编译链接、`atlas --version` 能从 .app 里跑出来。
/// 完整命令面（list/search/install/enable/simulate/doctor/bill/…，见 PLAN.md §4.1）
/// 是 WP1（及后续）的事，这里不要提前实现子命令逻辑。
/// 文件不叫 main.swift：swiftc -parse-as-library 与 @main 顶层类型冲突要求
/// 入口文件改名，SwiftPM 与 swiftc 兜底两路因此保持一致写法。
@main
enum AtlasCLI {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        if args.contains(where: { $0 == "--version" || $0 == "-v" || $0 == "version" }) {
            print("atlas \(AtlasVersion.string)")
            return
        }
        let isHelp = args.contains(where: { $0 == "--help" || $0 == "-h" || $0 == "help" })
        if args.isEmpty || isHelp {
            fputs(LF("atlas %@ — Skill Atlas 命令行", AtlasVersion.string) + "\n", stderr)
            fputs(L("用法：atlas --version / atlas --help") + "\n", stderr)
            fputs(L("完整子命令随 2.0 CLI 提供。") + "\n", stderr)
            // 空调用按「用法错误」算（PLAN.md §4.1 退出码 2）；显式 --help 视为成功。
            exit(Int32(args.isEmpty ? 2 : 0))
        }
        fputs(L("未知命令。当前骨架只提供 --version / --help。") + "\n", stderr)
        exit(2)
    }
}
