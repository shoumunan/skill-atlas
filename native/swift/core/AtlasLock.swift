import Foundation
import Darwin

// MARK: - 库互斥锁（ADR-5）
//
// 两个写者（App、CLI）一个真源（文件系统），用 O_EXCL 创建 ~/.skill-atlas/.lock
// 做互斥，不上守护进程/socket。锁文件内容是持有者 pid，用于陈锁判定：
//   · 文件 mtime 超过 120 秒——大概率进程卡死或异常退出后没清理，直接抢占
//   · 文件里的 pid 已经不存在（kill(pid, 0) → ESRCH）——同上
// CLI 侧等 5 秒拿不到锁就退出码 6（见 §4.1 退出码总表）；App 侧本 WP 不强制接入。
//
// 只做互斥，不做重入：同一进程内不要在已持锁的调用栈里再次 acquire，会一直等到超时。
package enum AtlasLock {
    /// 拿不到锁（等待超时）。CLI 侧映射退出码 6。
    package struct Busy: LocalizedError {
        package init() {}
        package var errorDescription: String? {
            L("技能库正在被另一个 Skill Atlas 进程写入，请稍后再试。")
        }
    }

    /// 锁文件本身创建不出来（目录不可写等文件系统错误，不是「被占用」）
    package struct CannotCreate: LocalizedError {
        package let detail: String
        package init(_ detail: String) { self.detail = detail }
        package var errorDescription: String? { LF("无法创建库锁：%@", detail) }
    }

    package static var lockURL: URL { AtlasPaths.root.appendingPathComponent(".lock") }

    /// 陈锁判定阈值：mtime 超过这个秒数，不管 pid 是否存活都视为陈锁
    package static let staleAfter: TimeInterval = 120

    /// 等待最多 `timeout` 秒获取锁；超时返回 false（调用方决定报什么错/什么退出码）。
    /// 成功返回 true 时调用方必须之后调 `release()`——优先用 `withLock` 包装避免忘记。
    package static func acquire(timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            reclaimStaleIfNeeded()
            if tryAcquireOnce() { return true }
            if Date() >= deadline { return false }
            usleep(100_000) // 100ms 轮询，5 秒超时内最多 ~50 次，可忽略不计的开销
        }
    }

    package static func release() {
        try? FileManager.default.removeItem(at: lockURL)
    }

    /// 便捷包装：拿不到锁抛 `Busy`；拿到了保证 body 执行完（无论成功/失败）都会释放。
    @discardableResult
    package static func withLock<T>(timeout: TimeInterval = 5, _ body: () throws -> T) throws -> T {
        guard acquire(timeout: timeout) else { throw Busy() }
        defer { release() }
        return try body()
    }

    // MARK: - 内部

    /// 单次尝试：O_EXCL 保证「创建」这一步是原子的，两个进程同时抢只有一个能成功。
    private static func tryAcquireOnce() -> Bool {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: AtlasPaths.root, withIntermediateDirectories: true)
        let fd = lockURL.path.withCString { path in
            open(path, O_CREAT | O_EXCL | O_WRONLY, 0o644)
        }
        guard fd >= 0 else { return false }
        defer { close(fd) }
        let pidLine = "\(ProcessInfo.processInfo.processIdentifier)\n"
        _ = pidLine.withCString { write(fd, $0, strlen($0)) }
        return true
    }

    /// 锁文件存在但已经死透——mtime 超过阈值，或持有者 pid 已不存在——直接删掉重抢。
    /// 删除失败（比如刚好被原持有者释放）不当回事，下一轮 tryAcquireOnce 自然会体现结果。
    private static func reclaimStaleIfNeeded() {
        let fileManager = FileManager.default
        guard let attributes = try? fileManager.attributesOfItem(atPath: lockURL.path) else { return }
        let mtime = (attributes[.modificationDate] as? Date) ?? .distantPast
        var stale = Date().timeIntervalSince(mtime) > staleAfter

        if !stale, let content = try? String(contentsOf: lockURL, encoding: .utf8) {
            let pidText = content.trimmingCharacters(in: .whitespacesAndNewlines)
            if let pid = pid_t(pidText) {
                // kill(pid, 0)：不发信号，只探测进程是否存在。ESRCH = 没有这个进程。
                // 权限不够（EPERM）说明进程确实存在，不算陈锁。
                if kill(pid, 0) != 0, errno == ESRCH {
                    stale = true
                }
            } else {
                // 锁文件内容不是合法 pid：视为损坏的锁，一并当陈锁处理
                stale = true
            }
        }
        if stale {
            try? fileManager.removeItem(at: lockURL)
        }
    }
}
