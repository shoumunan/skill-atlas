import Foundation

// MARK: - 退出码总表（PLAN.md §4.1）

enum ExitCode: Int32 {
    case ok = 0
    case general = 1
    case usage = 2
    case approvalRequired = 3 // 本 WP 不产生（install 专属，WP2）
    case network = 4 // 本 WP 不产生（CLI 无出网写操作；search --remote 失败走优雅降级）
    case conflict = 5
    case locked = 6
    case notFound = 7
}

// MARK: - 手写参数路由（ADR-2：不引 swift-argument-parser，兜底 swiftc 路径解析不了 SPM 依赖）
//
// 形状固定为 `atlas <command> [位置参数...] [--flag] [--option value]`。
// 子命令名必须是 args[0]（不支持子命令前面插 flag）——已够用且零歧义，
// 换来的是不用处理「--platform 的值和子命令名撞在一起」这类边角情形。

struct Args {
    var positionals: [String] = []
    var flags: Set<String> = []
    var options: [String: String] = [:]

    var json: Bool { flags.contains("json") }
    var remote: Bool { flags.contains("remote") }
    var platform: String? { options["platform"] }
    var platforms: String? { options["platforms"] ?? options["platform"] }
    var project: String? { options["project"] }
}

/// 解析子命令名之后的其余 token。`--platform` 是唯一取值 flag，其余 `--x` 一律当布尔开关。
func parseArgs(_ raw: [String]) -> Args {
    var result = Args()
    let valueOptions: Set<String> = ["platform", "platforms", "project"]
    var index = 0
    while index < raw.count {
        let token = raw[index]
        if token.hasPrefix("--") {
            let name = String(token.dropFirst(2))
            if valueOptions.contains(name) {
                if index + 1 < raw.count, !raw[index + 1].hasPrefix("--") {
                    result.options[name] = raw[index + 1]
                    index += 1
                } else {
                    result.options[name] = ""
                }
            } else {
                result.flags.insert(name)
            }
        } else {
            result.positionals.append(token)
        }
        index += 1
    }
    return result
}

// MARK: - 输出通道
//
// §4.1 原文：「--json（机器模式：stdout 恰好一个 JSON 对象，人话与进度全走 stderr）」。
// 落地成一条统一规则：人话/进度永远走 stderr；stdout 只在 --json 模式下出现，且
// 只出现这一个信封对象。非 --json 模式 stdout 保持空——人不会去解析它，日志都在 stderr。

/// 人话与进度：一律 stderr。
func say(_ text: String) {
    FileHandle.standardError.write((text + "\n").data(using: .utf8) ?? Data())
}

enum JSONOut {
    /// `{"ok":bool,"code":int,"op":"<子命令>","data":{…},"error":{"message":"…","hint":"…"}|null}`
    static func emit(op: String, ok: Bool, code: ExitCode, data: [String: Any]?, error: (message: String, hint: String?)?) {
        var envelope: [String: Any] = ["ok": ok, "code": Int(code.rawValue), "op": op]
        envelope["data"] = data ?? NSNull()
        if let error {
            var errorObject: [String: Any] = ["message": error.message]
            errorObject["hint"] = error.hint.map { $0 as Any } ?? NSNull()
            envelope["error"] = errorObject
        } else {
            envelope["error"] = NSNull()
        }
        guard let payload = try? JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys]) else {
            say("JSON 编码失败")
            return
        }
        FileHandle.standardOutput.write(payload)
        FileHandle.standardOutput.write(Data([0x0A]))
    }
}

/// 失败的统一出口：json 模式写信封到 stdout，人话模式写 message/hint 到 stderr；
/// 两种模式都返回对应退出码，调用方直接 `return fail(...)` 即可。
@discardableResult
func fail(op: String, json: Bool, code: ExitCode, message: String, hint: String? = nil) -> Int32 {
    if json {
        JSONOut.emit(op: op, ok: false, code: code, data: nil, error: (message, hint))
    } else {
        say(message)
        if let hint { say(hint) }
    }
    return code.rawValue
}

/// 成功的统一出口：json 模式写信封，人话模式回调 `human()` 自己 say(...)。
@discardableResult
func succeed(op: String, json: Bool, data: [String: Any], human: () -> Void) -> Int32 {
    if json {
        JSONOut.emit(op: op, ok: true, code: .ok, data: data, error: nil)
    } else {
        human()
    }
    return ExitCode.ok.rawValue
}
