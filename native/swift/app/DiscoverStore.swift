import Observation
import SwiftUI
#if SWIFT_PACKAGE
import AtlasCore
#endif

// MARK: - 发现页状态（WP-M）
//
// ADR-14：页面自建 store。这里只管搜索词、聚合结果与榜单缓存；
// 安装动作全部回到 AppStore 既有管线（beginInstall → 装前扫描 sheet）。

@MainActor
@Observable
final class DiscoverStore {
    var query = ""
    var hits: [SourceHit] = []
    var featured: [SourceHit] = []
    var searching = false
    var loadingFeatured = false
    @ObservationIgnored private var loadedFeatured = false
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    var anySourceEnabled: Bool {
        SourceKind.allCases.contains { $0.enabled }
    }

    /// 正在下载解包的条目 id（同一时间只放一个直装）
    var busyHitID: String?
    var installError: String?

    /// SkillHub zip 直装（ADR-16）：下载 → sha256 → 安全解包 → 交给既有安装 sheet
    ///（detect → 装前扫描 → 审阅 → 入库全复用；溯源经 pendingProvenance 交接）。
    func installFromSkillHub(_ hit: SourceHit, appStore: AppStore) {
        guard hit.kind == .skillhub, busyHitID == nil else { return }
        // 来源开关关掉后，缓存里的旧结果不该还能触发出网（护栏 §7-19）
        guard SourceKind.skillhub.enabled else {
            installError = L("SkillHub 已在设置里关闭。打开后再安装。")
            return
        }
        busyHitID = hit.id
        installError = nil
        Task {
            do {
                let fetched = try await ZipChannel.fetchSkillHub(slug: hit.key)
                InstallerModel.pendingProvenance = ("skillhub", hit.version, fetched.sha256Hex)
                appStore.beginInstall(url: fetched.unpackedDir.path)
            } catch {
                installError = (error as? ZipChannel.ZipError)?.message ?? error.localizedDescription
            }
            busyHitID = nil
        }
    }

    /// 开关变了就丢掉旧结果：否则关掉 SkillHub 后它的榜单还留在屏幕上
    func syncEnabledSources() {
        let signature = SourceKind.allCases.filter(\.enabled).map(\.rawValue).joined(separator: ",")
        guard signature != lastEnabledSignature else { return }
        lastEnabledSignature = signature
        featured = []
        hits = []
        loadedFeatured = false
        loadFeaturedIfNeeded()
    }

    @ObservationIgnored private var lastEnabledSignature = ""

    func loadFeaturedIfNeeded() {
        guard !loadedFeatured, anySourceEnabled else { return }
        loadedFeatured = true
        loadingFeatured = true
        Task {
            let list = await SkillSources.featured()
            self.featured = list
            self.loadingFeatured = false
        }
    }

    /// 350ms 防抖后聚合搜索；空词回到榜单
    func queryChanged() {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            hits = []
            searching = false
            return
        }
        searching = true
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            let results = await SkillSources.search(trimmed)
            guard !Task.isCancelled else { return }
            self.hits = results
            self.searching = false
        }
    }
}
