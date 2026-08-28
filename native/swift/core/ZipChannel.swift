import CryptoKit
import Foundation

// MARK: - SkillHub zip 直装通道（2.1 ADR-16）
//
// 下载（302 → 腾讯 COS）→ sha256 → bsdtar 安全解包 → 把解包目录交给既有安装管线
//（detect → 装前扫描 → 审阅 → clonefile 入库，一道门不少）。
//
// 解包安全边界（2026-08-27 本机 bsdtar 实测）：
//   - `..` 条目：bsdtar 拒绝并 exit≠0 → 我们整包拒收
//   - 绝对路径条目：bsdtar 剥掉引导 `/`，落在目标目录内
//   - 穿过符号链接写文件：bsdtar 拒绝并 exit≠0 → 整包拒收
//   - 符号链接条目本身：bsdtar 会解出 → 解包后全树遍历，见链即整包拒收
//     （软链进库会悬空或指向任意路径，技能包里不该有）
// 归档寻址：sha256(zip) 进 oplog；上游换版本内容即变，与 repo@commit 同一语义。

package enum ZipChannel {
    package struct Fetched {
        package var unpackedDir: URL
        package var sha256Hex: String
        package var archiveBytes: Int
    }

    package struct ZipError: Error {
        package let message: String
        package init(_ m: String) { message = m }
    }

    /// 体积上限：技能包以文本为主，50MB 封顶（防把安装通道当下载器用）
    private static let maxBytes = 50 * 1024 * 1024

    /// 下载 SkillHub 安装包并安全解包。返回的临时目录由调用方用完清理。
    package static func fetchSkillHub(slug: String) async throws -> Fetched {
        var components = URLComponents(string: "\(SkillSources.skillHubBase)/api/v1/download")
        components?.queryItems = [URLQueryItem(name: "slug", value: slug)]
        guard let url = components?.url else { throw ZipError(L("下载地址不合法。")) }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = false
        let (fileURL, response) = try await URLSession(configuration: config).download(from: url)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw ZipError(L("下载失败，稍后重试或到网页安装。"))
        }
        let size = ((try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.size] as? Int) ?? 0
        guard size > 0, size <= maxBytes else {
            throw ZipError(L("安装包体积异常，已拒绝。"))
        }
        let data = try Data(contentsOf: fileURL)
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()

        let dest = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("skill-atlas-zip-\(hash.prefix(8))")
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        do {
            try await unpack(archive: fileURL, to: dest)
        } catch {
            try? FileManager.default.removeItem(at: dest)
            throw error
        }
        return Fetched(unpackedDir: dest, sha256Hex: hash, archiveBytes: size)
    }

    /// bsdtar 解包 + 符号链接全树拒收。exit≠0 一律整包拒（覆盖 `..` 与穿链两类攻击）。
    package static func unpack(archive: URL, to dest: URL) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-x", "-f", archive.path, "-C", dest.path]
        let stderrPipe = Pipe()
        process.standardOutput = Pipe()
        process.standardError = stderrPipe
        try process.run()
        await withCheckedContinuation { continuation in
            process.terminationHandler = { _ in continuation.resume() }
        }
        guard process.terminationStatus == 0 else {
            let raw = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let brief = raw.split(separator: "\n").first.map(String.init) ?? L("未知错误")
            throw ZipError(LF("安装包解包被安全拒绝：%@", brief))
        }
        if let walker = FileManager.default.enumerator(
            at: dest, includingPropertiesForKeys: [.isSymbolicLinkKey], options: [], errorHandler: nil
        ) {
            for case let item as URL in walker {
                if (try? item.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true {
                    throw ZipError(L("安装包里有符号链接，已整包拒收。"))
                }
            }
        }
    }

    /// 离线验收探针：`-atlasZipProbe <zip路径> [-atlasScanProbe <输出json>]`，
    /// 解包成功 exit 0，安全拒收 exit 3。沿用既有 -atlasXxx 探针惯例，不出网。
    package static func runProbeIfRequested() {
        guard let zipPath = LaunchArgs.value("atlasZipProbe") else { return }
        let out = LaunchArgs.value("atlasScanProbe")
        let dest = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("zip-probe-\(UUID().uuidString.prefix(6))")
        var payload: [String: Any]
        var ok = false
        do {
            try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
            let semaphore = DispatchSemaphore(value: 0)
            let box = ProbeBox()
            Task {
                do {
                    try await unpack(archive: URL(fileURLWithPath: zipPath), to: dest)
                } catch {
                    box.error = error
                }
                semaphore.signal()
            }
            semaphore.wait()
            if let error = box.error { throw error }
            let files = (FileManager.default.enumerator(at: dest, includingPropertiesForKeys: nil)?
                .allObjects as? [URL])?.count ?? 0
            payload = ["ok": true, "files": files]
            ok = true
        } catch {
            payload = ["ok": false, "error": (error as? ZipError)?.message ?? error.localizedDescription]
        }
        try? FileManager.default.removeItem(at: dest)
        if let out,
           let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            try? text.write(toFile: out, atomically: true, encoding: .utf8)
        }
        exit(ok ? 0 : 3)
    }

    private final class ProbeBox: @unchecked Sendable {
        var error: Error?
    }
}
