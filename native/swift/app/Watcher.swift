import Foundation
import CoreServices
#if SWIFT_PACKAGE
import AtlasCore
#endif

// MARK: - 目录自动刷新（FSEvents）
//
// 监听所有扫描根（resolve 后的真实路径）+ CC Switch DB 文件。
// 事件回调只负责通知，2 秒防抖与 rescan 由 AppStore 处理；
// 自家写操作（停用/恢复）期间调用 pause()/resume() 避免自触发。

final class DirectoryWatcher {
    private var stream: FSEventStreamRef?
    private var onChange: (() -> Void)?
    private(set) var paused = false
    /// 计数式暂停：并发操作各自 pause/resume，归零才真正恢复。
    /// 布尔版在暂停窗口重叠时会被第一个 resume 提前解除——FSEvents 在另一
    /// 操作 git fetch 写 .git 时送达，形成自触发重扫（历史上修过的循环复发形态）。
    private var pauseCount = 0

    func start(paths: [String], onChange: @escaping () -> Void) {
        stop()
        let existing = paths.filter { FileManager.default.fileExists(atPath: $0) }
        guard !existing.isEmpty else { return }
        self.onChange = onChange

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<DirectoryWatcher>.fromOpaque(info).takeUnretainedValue()
            guard !watcher.paused else { return }
            watcher.onChange?()
        }
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            existing as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,  // FSEvents 自身的合并窗口；应用层另有 2s 防抖
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagIgnoreSelf)
        ) else { return }

        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    func pause() {
        pauseCount += 1
        paused = true
    }

    func resume() {
        pauseCount = max(0, pauseCount - 1)
        if pauseCount == 0 { paused = false }
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
        onChange = nil
    }

    deinit { stop() }
}
