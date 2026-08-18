import Foundation

// MARK: - 粘贴 GitHub 链接一键安装
//
// 流程：解析 URL → git clone --depth 1 到临时目录 → 检测 SKILL.md
// （根目录单技能 / 一层或 skills/<name> 两层 / URL 子路径直装）→
// 真实拷贝到 ~/.skill-atlas/skills/<name>（保留 .git 以便检查更新），
// 再按勾选平台在 Claude / Codex / GrokBuild 等目录建软链。
// 同名冲突跳过不覆盖。写入期间暂停 FSEvents 监听。

struct RepoRef: Equatable {
    var owner: String
    var repo: String
    var branch: String?
    var subpath: String?
    /// file:// 裸仓库时的直连克隆地址（离线验收用）
    var cloneOverride: String?
    /// 本地文件夹安装（不是 git clone）
    var localDirectory: String?

    var cloneURL: String { cloneOverride ?? "https://github.com/\(owner)/\(repo).git" }
    var display: String { "\(owner)/\(repo)" + (subpath.map { " → \($0)" } ?? "") }
    var isLocalFolder: Bool { localDirectory != nil }
}

struct InstallCandidate: Identifiable {
    var id: String { directory }
    /// 克隆目录内的相对路径（"." = 仓库根）
    var relativePath: String
    /// 安装后的目录名
    var directory: String
    /// SKILL.md frontmatter 里的名称（展示用）
    var displayName: String
    var description: String
    /// 目标位置已有同名目录 → 只能跳过
    var conflict: Bool
    var selected: Bool
    /// 装前静态安全扫描结果（二期 F3）
    var findings: [SecurityFinding] = []

    var criticalCount: Int { findings.filter { $0.severity == .critical }.count }
    var warningCount: Int { findings.filter { $0.severity == .warning }.count }
}

struct InstallResult: Identifiable {
    var id: String { directory }
    var directory: String
    var installed: Bool
    var note: String
}

@MainActor
final class InstallerModel: ObservableObject {
    enum Stage: Equatable {
        case input          // 等待粘贴
        case cloning        // git clone 中
        case detecting      // 扫描 SKILL.md
        case selecting      // 多技能勾选
        case reviewing      // 安全审阅（有关键级发现时强制过闸）
        case installing     // 拷贝中
        case done           // 结果清单
    }

    @Published var urlText = ""
    @Published var stage = Stage.input
    @Published var statusText = ""
    @Published var errorText: String?
    @Published var candidates: [InstallCandidate] = []
    @Published var selectedPlatforms: Set<String> = [AgentPlatform.claude.rawValue]
    @Published var results: [InstallResult] = []

    private var cloneDir: URL?
    private var parsedRef: RepoRef?
    private var ownsCloneDir = false
    /// 审阅页已确认「仍要安装」
    private var reviewConfirmed = false

    /// 即时校验（红字提示用）：空串不报错，非法格式报错
    var inlineError: String? {
        let text = urlText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return Self.parse(text) == nil
            ? L("支持 GitHub 链接，或本机已有 SKILL.md 的文件夹路径")
            : nil
    }

    var canStart: Bool {
        stage == .input && Self.parse(urlText.trimmingCharacters(in: .whitespaces)) != nil
    }

    // MARK: URL 解析

    static func parse(_ input: String) -> RepoRef? {
        guard let url = URL(string: input), url.scheme == "https",
              url.host?.lowercased() == "github.com" else { return localFolderRef(input) }
        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }
        let owner = parts[0]
        var repo = parts[1]
        if repo.hasSuffix(".git") { repo = String(repo.dropLast(4)) }
        guard !owner.isEmpty, !repo.isEmpty else { return nil }
        var ref = RepoRef(owner: owner, repo: repo)
        if parts.count >= 4, parts[2] == "tree" {
            ref.branch = parts[3]
            if parts.count >= 5 {
                ref.subpath = parts[4...].joined(separator: "/")
            }
        } else if parts.count > 2 {
            return nil  // 其他子路径形态（blob/issues/…）不支持
        }
        return ref
    }

    private static func localFolderRef(_ input: String) -> RepoRef? {
        if let git = localFileRef(input) { return git }
        let path = (input as NSString).expandingTildeInPath
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            return nil
        }
        let name = URL(fileURLWithPath: path).lastPathComponent
        guard !name.isEmpty else { return nil }
        return RepoRef(owner: "local", repo: name, localDirectory: path)
    }

    /// file:// 裸仓库（离线验收 git clone 全流程用，界面文案不宣传）
    private static func localFileRef(_ input: String) -> RepoRef? {
        guard input.hasPrefix("file://"), input.hasSuffix(".git") else { return nil }
        let name = URL(string: input)?.deletingPathExtension().lastPathComponent ?? ""
        guard !name.isEmpty else { return nil }
        return RepoRef(owner: "local", repo: name, cloneOverride: input)
    }

    /// 选的文件夹已在平台技能根 / CC Switch 源里：拦下改道，不做重复拷贝安装。
    /// 拷贝安装会留下「库里一份 + 原地一份普通目录」，建链跳过后落成 .directory 警告态；
    /// 正确路径是技能库列表里的收编（平台目录）或迁移（CC Switch）。
    static func adoptionRedirect(for path: String) -> String? {
        let real = URL(fileURLWithPath: path, isDirectory: true)
            .resolvingSymlinksInPath().standardizedFileURL.path
        let ccRoot = SkillScanner.sourceRoot.resolvingSymlinksInPath().standardizedFileURL.path
        if real == ccRoot || real.hasPrefix(ccRoot + "/") {
            return L("这个文件夹由 CC Switch 管理。请在设置页执行「从 CC Switch 迁入」，不要重复安装。")
        }
        for platform in AgentPlatform.allCases {
            let root = platform.resolvedRoot(home: AtlasPaths.home).standardizedFileURL.path
            if real == root || real.hasPrefix(root + "/") {
                return LF("这个文件夹已经在 %@ 的技能目录里，不用重装：回到技能库列表选中它，在「管理」区收进本库接管（列表顶部也有「全部收编」）。", platform.displayName)
            }
        }
        return nil
    }

    // MARK: 主流程

    func start() {
        let text = urlText.trimmingCharacters(in: .whitespaces)
        guard let ref = Self.parse(text) else { return }
        parsedRef = ref
        errorText = nil
        stage = .cloning
        statusText = LF("正在克隆 %@…", ref.display)

        Task {
            do {
                let dir: URL
                if let local = ref.localDirectory {
                    if let redirect = Self.adoptionRedirect(for: local) {
                        throw InstallError(redirect)
                    }
                    dir = URL(fileURLWithPath: local)
                    ownsCloneDir = false
                    cloneDir = dir
                    stage = .detecting
                    statusText = L("正在检测 SKILL.md…")
                } else {
                    stage = .cloning
                    statusText = "正在克隆 \(ref.display)…"
                    dir = try await clone(ref)
                    ownsCloneDir = true
                    cloneDir = dir
                    stage = .detecting
                    statusText = "正在检测 SKILL.md…"
                }
                var found = try detect(in: dir, ref: ref)
                // 装前安全扫描：逐候选静态扫（毫秒级，离线）
                for index in found.indices {
                    let source = found[index].relativePath == "."
                        ? dir
                        : dir.appendingPathComponent(found[index].relativePath)
                    found[index].findings = SecurityScanner.scan(directory: source)
                }
                candidates = found
                writeScanProbeIfRequested()
                if found.isEmpty {
                    throw InstallError(L("仓库里没有找到 SKILL.md（检查了根目录、一层子目录，以及 skills/<name> 两层布局）。"))
                }
                stage = .selecting
                statusText = ""
            } catch {
                stage = .input
                statusText = ""
                let message = (error as? InstallError)?.message ?? error.localizedDescription
                errorText = message
                writeErrorProbeIfRequested(message)
            }
        }
    }

    /// 调试钩子：-atlasScanProbe 也承接错误路径（安装拦截改道等验收用）
    private func writeErrorProbeIfRequested(_ message: String) {
        guard let path = UserDefaults.standard.string(forKey: "atlasScanProbe"), !path.isEmpty else { return }
        if let data = try? JSONSerialization.data(withJSONObject: ["error": message], options: [.prettyPrinted]),
           let text = String(data: data, encoding: .utf8) {
            try? text.write(toFile: path, atomically: true, encoding: .utf8)
        }
        if LaunchArgs.flag("atlasQuit") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { exit(0) }
        }
    }

    func install(store: AppStore) {
        let chosen = candidates.filter { $0.selected && !$0.conflict }
        // 关键级安全发现 → 强制进入审阅页；「仍要安装」后才放行
        if !reviewConfirmed, chosen.contains(where: { $0.criticalCount > 0 }) {
            stage = .reviewing
            return
        }
        let skippedConflicts = candidates.filter(\.conflict)
        guard let cloneDir else { return }
        stage = .installing
        statusText = L("正在安装…")

        let fileManager = FileManager.default
        let atlasRoot = AtlasPaths.libraryRoot

        store.pauseWatching()
        var outcome: [InstallResult] = []
        for candidate in chosen {
            let source = Self.resolve(cloneDir, relative: candidate.relativePath)
            let target = atlasRoot.appendingPathComponent(candidate.directory)
            do {
                // 落盘兜底：directory 来自第三方仓库里的目录名，appendingPathComponent
                // 不做规范化，`..` 或内嵌斜杠能把拷贝写到库外；点开头的目录还会被
                // scanAtlasLibrary 的隐藏项过滤吃掉——装进去了却在列表里看不见、卸不掉。
                let insideLibrary = target.standardizedFileURL.path
                    .hasPrefix(atlasRoot.standardizedFileURL.path + "/")
                guard insideLibrary,
                      !candidate.directory.hasPrefix("."),
                      !candidate.directory.contains("/") else {
                    outcome.append(.init(directory: candidate.directory, installed: false,
                                         note: L("目录名不合法，已拒绝安装")))
                    continue
                }
                try fileManager.createDirectory(at: atlasRoot, withIntermediateDirectories: true)
                guard !fileManager.fileExists(atPath: target.path) else {
                    outcome.append(.init(directory: candidate.directory, installed: false,
                                         note: L("已存在同名目录，跳过")))
                    continue
                }
                // clonefile 而非逐字节拷贝：同盘近乎零成本，与收编走同一条路径
                try FileClone.cloneDirectory(from: source, to: target)

                var enabled: [String: Bool] = [:]
                for platform in AgentPlatform.allCases {
                    enabled[platform.rawValue] = selectedPlatforms.contains(platform.rawValue)
                }
                try AtlasCatalog.upsert(AtlasSkillRecord(
                    directory: candidate.directory,
                    enabled: enabled,
                    repoOwner: parsedRef?.owner ?? "",
                    repoName: parsedRef?.repo ?? "",
                    repoBranch: parsedRef?.branch ?? "main",
                    installedAt: Int(Date().timeIntervalSince1970),
                    updatedAt: Int(Date().timeIntervalSince1970)
                ))

                var linked: [String] = []
                for platform in AgentPlatform.allCases where selectedPlatforms.contains(platform.rawValue) {
                    let root = platform.resolvedRoot(home: AtlasPaths.home)
                    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
                    let link = root.appendingPathComponent(candidate.directory)
                    if fileManager.fileExists(atPath: link.path) {
                        continue
                    }
                    try fileManager.createSymbolicLink(at: link, withDestinationURL: target)
                    linked.append(platform.label)
                }
                let note = linked.isEmpty
                    ? L("已装入 Skill Atlas 库")
                    : LF("已装入 Skill Atlas 库 + %@ 软链", linked.joined(separator: " / "))
                outcome.append(.init(directory: candidate.directory, installed: true, note: note))
            } catch {
                outcome.append(.init(directory: candidate.directory, installed: false,
                                     note: LF("安装失败：%@", error.localizedDescription)))
            }
        }
        for skipped in skippedConflicts {
            outcome.append(.init(directory: skipped.directory, installed: false,
                                 note: L("已存在同名目录，跳过")))
        }
        store.resumeWatching()

        results = outcome
        stage = .done
        statusText = ""
        cleanupClone()
        Task { await store.rescan(keepSelection: true) }
    }

    /// 审阅页「仍要安装」：放行一次
    func confirmReviewAndInstall(store: AppStore) {
        reviewConfirmed = true
        install(store: store)
    }

    func backToSelection() {
        stage = .selecting
    }

    /// 调试钩子：-atlasScanProbe <path> 把扫描结果写盘（验收用）
    private func writeScanProbeIfRequested() {
        guard let path = UserDefaults.standard.string(forKey: "atlasScanProbe"), !path.isEmpty else { return }
        let payload: [[String: Any]] = candidates.map { candidate in
            [
                "directory": candidate.directory,
                "critical": candidate.criticalCount,
                "warning": candidate.warningCount,
                "findings": candidate.findings.map {
                    ["severity": $0.severity.rawValue, "rule": $0.rule,
                     "file": $0.file, "line": $0.line, "excerpt": $0.excerpt]
                },
            ]
        }
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            try? text.write(toFile: path, atomically: true, encoding: .utf8)
        }
        if LaunchArgs.flag("atlasQuit") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { exit(0) }
        }
    }

    func reset() {
        reviewConfirmed = false
        cleanupClone()
        urlText = ""
        stage = .input
        statusText = ""
        errorText = nil
        candidates = []
        results = []
    }

    private func cleanupClone() {
        if ownsCloneDir, let cloneDir {
            try? FileManager.default.removeItem(at: cloneDir)
        }
        cloneDir = nil
        ownsCloneDir = false
    }

    // MARK: git

    struct InstallError: Error { let message: String; init(_ m: String) { message = m } }

    private func clone(_ ref: RepoRef) async throws -> URL {
        // /usr/bin/git 在未装 CLT 的机器上是弹窗替身，先探测再跑
        let probe = Process()
        probe.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        probe.arguments = ["-p"]
        probe.standardOutput = Pipe(); probe.standardError = Pipe()
        try? probe.run(); probe.waitUntilExit()
        guard probe.terminationStatus == 0 else {
            throw InstallError(L("没有可用的 git。请先安装命令行工具：终端里执行 xcode-select --install"))
        }

        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("skill-atlas-install-\(UUID().uuidString.prefix(8))")
        var args = ["clone", "--depth", "1"]
        if let branch = ref.branch { args += ["--branch", branch] }
        args += [ref.cloneURL, tmp.path]

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        // 不存在的仓库 git 会转而要求输入凭据（与私有仓库不可区分）——禁掉交互直接失败
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_TERMINAL_PROMPT"] = "0"
        process.environment = environment
        let stderrPipe = Pipe()
        process.standardOutput = Pipe()
        process.standardError = stderrPipe
        try process.run()
        await withCheckedContinuation { continuation in
            process.terminationHandler = { _ in continuation.resume() }
        }
        guard process.terminationStatus == 0 else {
            let raw = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            try? FileManager.default.removeItem(at: tmp)
            if raw.contains("could not resolve host") || raw.contains("Could not resolve host") {
                throw InstallError(L("网络不可用，克隆失败。检查网络后重试。"))
            }
            if raw.contains("not found") || raw.contains("Repository not found")
                || raw.contains("could not read Username") || raw.contains("Authentication failed") {
                throw InstallError(LF("仓库不存在或无权访问：%@", ref.display))
            }
            let brief = raw.split(separator: "\n").last.map(String.init) ?? L("未知错误")
            throw InstallError(LF("克隆失败：%@", brief))
        }
        return tmp
    }

    // MARK: 检测

    /// 相对路径按 `/` 拆开再拼接，避免 `appendingPathComponent("a/b")` 把斜杠当文件名。
    private static func resolve(_ root: URL, relative: String) -> URL {
        if relative == "." { return root }
        return relative.split(separator: "/").reduce(root) {
            $0.appendingPathComponent(String($1))
        }
    }

    private func detect(in dir: URL, ref: RepoRef) throws -> [InstallCandidate] {
        let fileManager = FileManager.default
        let atlasRoot = AtlasPaths.libraryRoot

        func candidate(relative: String, directory: String) -> InstallCandidate? {
            let skillFile = Self.resolve(dir, relative: relative).appendingPathComponent("SKILL.md")
            guard fileManager.fileExists(atPath: skillFile.path) else { return nil }
            let meta = SkillScanner.readFrontmatter(skillFile)
            let conflict = fileManager.fileExists(atPath: atlasRoot.appendingPathComponent(directory).path)
            return InstallCandidate(
                relativePath: relative,
                directory: directory,
                displayName: meta["name"].flatMap { $0.isEmpty ? nil : $0 } ?? directory,
                description: (meta["description"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                conflict: conflict,
                selected: !conflict
            )
        }

        func childDirectories(of parent: URL) -> [URL] {
            ((try? fileManager.contentsOfDirectory(
                at: parent, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
            )) ?? [])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        }

        // URL 带子路径 → 直装该子目录
        if let subpath = ref.subpath {
            let name = subpath.split(separator: "/").last.map(String.init) ?? ref.repo
            guard let hit = candidate(relative: subpath, directory: name) else {
                throw InstallError(LF("子目录 %@ 里没有 SKILL.md。", subpath))
            }
            return [hit]
        }
        // 仓库根有 SKILL.md → 单技能
        if let root = candidate(relative: ".", directory: ref.repo) {
            return [root]
        }
        // 一层子目录；没有 SKILL.md 的目录再往下看一层（skills/<name>/SKILL.md）
        // 同名叶目录只留较浅的那份，避免勾选两项却装进同一个库目录。
        var found: [InstallCandidate] = []
        var seen: Set<String> = []
        for entry in childDirectories(of: dir) {
            let name = entry.lastPathComponent
            if let hit = candidate(relative: name, directory: name) {
                found.append(hit)
                seen.insert(name)
                continue
            }
            for nested in childDirectories(of: entry) {
                let leaf = nested.lastPathComponent
                guard !seen.contains(leaf),
                      let hit = candidate(relative: "\(name)/\(leaf)", directory: leaf) else { continue }
                found.append(hit)
                seen.insert(leaf)
            }
        }
        return found
    }
}

