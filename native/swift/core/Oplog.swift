import Darwin
import Foundation

// MARK: - 操作日志（ADR-5）
//
// 追加写 ~/.skill-atlas/oplog.jsonl，每行一个独立 JSON 对象：
//   {"ts":unix,"actor":"cli"|"app","op":"...","target":"<dir>","ok":bool,"detail":"..."}
// 只做「记下来」，不做查询/聚合——那是 App 维护区/miss 检测（后续 WP）的事。
// 调用方自己决定何时记（通常在拿到 AtlasLock 之后，变更尝试无论成功失败都记一笔）。
package enum Oplog {
    package static var url: URL { AtlasPaths.root.appendingPathComponent("oplog.jsonl") }

    /// 超过这个大小就截半（保留后半部分，丢最老的），避免无限增长
    package static let rotateThreshold = 2 * 1024 * 1024 // 2MB

    package static func record(actor: String, op: String, target: String, ok: Bool, detail: String) {
        let entry: [String: Any] = [
            "ts": Int(Date().timeIntervalSince1970),
            "actor": actor,
            "op": op,
            "target": target,
            "ok": ok,
            "detail": detail,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]) else { return }
        appendLine(data)
    }

    /// App 侧便捷入口，actor 默认 "app"。
    package static func append(op: String, target: String, ok: Bool, detail: String, actor: String = "app") {
        record(actor: actor, op: op, target: target, ok: ok, detail: detail)
    }

    // MARK: - 内部

    /// fopen("a") 追加。FileHandle(forWritingTo:) 在部分机器上 seek+write 会 SIGBUS。
    private static func appendLine(_ line: Data) {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: AtlasPaths.root, withIntermediateDirectories: true)
        rotateIfNeeded()
        url.path.withCString { path in
            guard let file = fopen(path, "a") else { return }
            defer { fclose(file) }
            line.withUnsafeBytes { raw in
                guard let base = raw.bindMemory(to: UInt8.self).baseAddress, raw.count > 0 else { return }
                _ = fwrite(base, 1, raw.count, file)
            }
            fputc(Int32(0x0A), file)
        }
    }

    /// 按行截半：找中点之后第一个换行，从那里开始保留到文件尾。
    /// 用字节操作而非整体转 String 再 split——oplog 可能积累到 2MB，没必要整篇进内存两遍。
    private static func rotateIfNeeded() {
        let fileManager = FileManager.default
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? Int, size > rotateThreshold,
              let data = try? Data(contentsOf: url) else { return }
        let midpoint = data.count / 2
        guard let newlineIndex = data[midpoint...].firstIndex(of: 0x0A) else { return }
        let kept = data[data.index(after: newlineIndex)...]
        try? Data(kept).write(to: url, options: .atomic)
    }
}
