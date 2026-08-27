import Foundation
#if SWIFT_PACKAGE
import AtlasCore
#endif

/// `atlas <command> [位置参数...] [--json] [--platform p] [--remote]`
/// 手写路由（ADR-2），命令面与 --json 信封见 PLAN.md §4.1。
/// 文件不叫 main.swift：swiftc -parse-as-library 与 @main 顶层类型冲突要求
/// 入口文件改名，SwiftPM 与 swiftc 兜底两路因此保持一致写法（WP0 已定）。
@main
enum AtlasCLI {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())

        // --version/-v 与裸子命令 "version" 触发；bare "version" 只在 args[0] 位置识别，
        // 否则 `atlas search version`（搜索词恰好是 "version"）会被误判成打印版本号。
        // --help/-h 与裸 "help" 同理。
        let hasVersionFlag = args.contains { $0 == "--version" || $0 == "-v" } || args.first == "version"
        let hasHelpFlag = args.contains { $0 == "--help" || $0 == "-h" } || args.first == "help"
        let wantsJSON = args.contains("--json")

        if hasVersionFlag {
            if wantsJSON {
                JSONOut.emit(
                    op: "version", ok: true, code: .ok,
                    data: ["version": AtlasVersion.string, "build": AtlasVersion.build], error: nil
                )
            } else {
                print("atlas \(AtlasVersion.string)")
            }
            exit(0)
        }

        if hasHelpFlag || args.isEmpty {
            printHelp()
            // 空调用按「用法错误」算（§4.1 退出码 2）；显式 --help/help 视为成功。
            exit(Int32(args.isEmpty ? 2 : 0))
        }

        let command = args[0]
        let rest = Array(args.dropFirst())
        let parsed = parseArgs(rest)

        let exitCode: Int32
        switch command {
        case "list": exitCode = ListCommand.run(parsed)
        case "search": exitCode = SearchCommand.run(parsed)
        case "info": exitCode = InfoCommand.run(parsed)
        case "enable": exitCode = EnableDisableCommand.run(op: "enable", parsed)
        case "disable": exitCode = EnableDisableCommand.run(op: "disable", parsed)
        case "simulate": exitCode = SimulateCommand.run(parsed)
        case "doctor": exitCode = DoctorCommand.run(parsed)
        case "bill": exitCode = BillCommand.run(parsed)
        case "paths": exitCode = PathsCommand.run(parsed)
        case "install": exitCode = await InstallCommand.run(parsed)
        case "review": exitCode = ReviewCommand.run(parsed)
        case "profile": exitCode = ProfileCommand.run(parsed)
        case "new": exitCode = NewCommand.run(parsed)
        case "sandbox": exitCode = SandboxCommand.run(parsed)
        case "slim": exitCode = SlimCommand.run(parsed)
        default:
            if wantsJSON {
                JSONOut.emit(
                    op: command, ok: false, code: .usage,
                    data: nil, error: (LF("未知命令：%@", command), helpLine())
                )
            } else {
                say(LF("未知命令：%@", command))
                say(helpLine())
            }
            exitCode = ExitCode.usage.rawValue
        }
        exit(exitCode)
    }

    private static func helpLine() -> String {
        L("用法：atlas list|search|info|enable|disable|simulate|doctor|bill|install|review|profile|new|sandbox|slim|paths|version [--json]")
    }

    private static func printHelp() {
        say(LF("atlas %@ — Skill Atlas 命令行", AtlasVersion.string))
        say(helpLine())
    }
}
