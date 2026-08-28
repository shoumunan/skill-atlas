import AppKit
import SwiftUI
#if SWIFT_PACKAGE
import AtlasCore
#endif

// MARK: - 发现（v15 一级页，WP-M）
//
// 回答「我没有的能力，怎么找到并安全装上」。上导入区三合一（链接与文件夹 / 收编 /
// CC Switch 迁移），下发现区（聚合搜索 + SkillHub 榜单）。GitHub 型结果进既有安装
// 管线（装前扫描一道不少）；SkillHub 托管型先打开网页（zip 通道 = ADR-16 残项）。
// 市场的评分与认证只作展示（ADR-15）。

struct DiscoverPage: View {
    @Environment(AppStore.self) private var store
    @State private var discover = DiscoverStore()
    @FocusState private var searchFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.s20) {
                importSection
                discoverSection
            }
            .padding(Theme.Space.s20)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .panelScroll()
        .contentSurface()
        .onAppear { discover.loadFeaturedIfNeeded() }
    }

    // MARK: 导入区（三合一）

    private var importSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s8) {
            Text(L("导入"))
                .font(Theme.Fonts.secondaryEmphasis)
                .foregroundStyle(Theme.textSecondary)
            HStack(spacing: Theme.Space.s12) {
                ImportTile(
                    symbol: "link",
                    title: L("从链接或文件夹…"),
                    caption: L("GitHub 仓库或本地目录，装前过安全扫描")
                ) {
                    store.installSheetPresented = true
                }
                if !store.adoptableSkills.isEmpty {
                    ImportTile(
                        symbol: "square.and.arrow.down.on.square",
                        title: LF("收编 %d 个本地技能", store.adoptableSkills.count),
                        caption: L("把散装在平台目录里的技能收进本库")
                    ) {
                        store.jumpToLocalSkills()
                    }
                }
                if store.canMigrate {
                    ImportTile(
                        symbol: "arrow.uturn.down",
                        title: L("从 CC Switch 迁入…"),
                        caption: L("原文件只读不动，随时可撤销")
                    ) {
                        store.migrationSheetPresented = true
                    }
                }
            }
        }
    }

    // MARK: 发现区（聚合搜索 + 榜单）

    @ViewBuilder
    private var discoverSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s12) {
            Text(L("市场"))
                .font(Theme.Fonts.secondaryEmphasis)
                .foregroundStyle(Theme.textSecondary)

            if !discover.anySourceEnabled {
                Text(L("远程发现已关闭。到设置里的「发现来源」打开。"))
                    .font(Theme.Fonts.secondary)
                    .foregroundStyle(Theme.textTertiary)
            } else {
                searchField
                if let installError = discover.installError {
                    ReceiptLine(text: installError, failed: true) {
                        discover.installError = nil
                    }
                }
                let trimmed = discover.query.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.count >= 2 {
                    resultList(discover.hits, emptyText: discover.searching ? L("搜索中…") : L("没搜到。换个说法，或直接粘贴 GitHub 链接。"))
                } else {
                    officialShelf
                    HStack(spacing: Theme.Space.s8) {
                        Text(L("SkillHub 热门"))
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(Theme.textTertiary)
                        if discover.loadingFeatured {
                            ProgressView().controlSize(.small)
                        }
                    }
                    resultList(discover.featured, emptyText: discover.loadingFeatured ? "" : L("榜单暂时拿不到。搜索仍可用。"))
                }
                Text(L("排名与认证来自市场，仅供参考；装什么都要过本地安全扫描。来源开关在设置。"))
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    /// 官方精选货架：硬编码高信任起点，零网络（本身就是 GitHub 仓库，走既有安装管线）
    private var officialShelf: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s8) {
            Text(L("官方精选"))
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.textTertiary)
            HStack(alignment: .center, spacing: Theme.Space.s12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Theme.Space.s8) {
                        Text("anthropics/skills")
                            .font(Theme.Fonts.rowTitle)
                            .foregroundStyle(Theme.textPrimary)
                        Text(L("官方"))
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, Theme.Space.s4 + 2)
                            .frame(height: 16)
                            .quietControl(tint: Theme.accent)
                    }
                    Text(L("Anthropic 官方技能仓库：pptx、xlsx、docx、pdf 等文档技能"))
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer(minLength: Theme.Space.s8)
                Button(L("安装…")) { store.beginInstall(url: "https://github.com/anthropics/skills") }
                    .buttonStyle(PressableButtonStyle())
                    .font(Theme.Fonts.secondaryEmphasis)
                    .foregroundStyle(Theme.accent)
                    .help(L("装前照样过安全扫描，可只勾选需要的技能"))
            }
            .padding(.horizontal, Theme.Space.s12)
            .padding(.vertical, Theme.Space.s8 + 2)
            .quietControl(cornerRadius: Theme.Radius.tile)
        }
    }

    private var searchField: some View {
        HStack(spacing: Theme.Space.s8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(searchFocused ? Theme.accent : Theme.textSecondary)
            TextField(L("搜市场里的能力，比如「甘特图」"), text: Binding(
                get: { discover.query },
                set: { discover.query = $0; discover.queryChanged() }
            ))
            .textFieldStyle(.plain)
            .font(Theme.Fonts.callout)
            .focused($searchFocused)
        }
        .padding(.horizontal, Theme.Space.s12)
        .frame(height: 34)
        .quietControl()
    }

    @ViewBuilder
    private func resultList(_ hits: [SourceHit], emptyText: String) -> some View {
        if hits.isEmpty {
            if !emptyText.isEmpty {
                Text(emptyText)
                    .font(Theme.Fonts.secondary)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.vertical, Theme.Space.s8)
            }
        } else {
            VStack(spacing: 0) {
                ForEach(Array(hits.enumerated()), id: \.element.id) { index, hit in
                    if index > 0 {
                        Rectangle()
                            .fill(Color.primary.opacity(0.05))
                            .frame(height: 1)
                            .padding(.leading, Theme.Space.s12)
                    }
                    SourceHitRow(discover: discover, hit: hit)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
            .quietControl(cornerRadius: Theme.Radius.tile)
        }
    }
}

private struct ImportTile: View {
    var symbol: String
    var title: String
    var caption: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Theme.Space.s8) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.accent)
                Text(title)
                    .font(Theme.Fonts.rowTitle)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(caption)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Theme.Space.s12)
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .quietControl(cornerRadius: Theme.Radius.tile)
    }
}

// MARK: - 结果行 + 徽标原语

private struct SourceHitRow: View {
    @Environment(AppStore.self) private var store
    @Bindable var discover: DiscoverStore
    var hit: SourceHit

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Space.s12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Theme.Space.s8) {
                    Text(hit.name)
                        .font(Theme.Fonts.rowTitle)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    SourceBadge(hit: hit)
                    if hit.requiresKey {
                        RequiresKeyChip()
                    }
                }
                Text(hit.summary.isEmpty ? hit.key : hit.summary)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Theme.Space.s8)
            if hit.metric > 0 {
                Text(LF("%d 次安装", hit.metric))
                    .font(Theme.Fonts.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize()
            }
            if let repo = hit.repoURL {
                Button(L("安装…")) { store.beginInstall(url: repo) }
                    .buttonStyle(PressableButtonStyle())
                    .font(Theme.Fonts.secondaryEmphasis)
                    .foregroundStyle(Theme.accent)
                    .help(LF("从 %@ 安装，先过装前扫描", repo))
            } else if hit.kind == .skillhub {
                if discover.busyHitID == hit.id {
                    ProgressView()
                        .controlSize(.small)
                        .help(L("正在下载并安全解包…"))
                } else {
                    Button(L("安装…")) { discover.installFromSkillHub(hit, appStore: store) }
                        .buttonStyle(PressableButtonStyle())
                        .font(Theme.Fonts.secondaryEmphasis)
                        .foregroundStyle(Theme.accent)
                        .disabled(discover.busyHitID != nil)
                        .help(L("下载 zip 安装包，解包后照样过装前扫描与审阅"))
                }
                if let web = hit.webURL, let url = URL(string: web) {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Image(systemName: "safari")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textTertiary)
                            .frame(width: 22, height: 22)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(L("到 SkillHub 网页看详情与评测报告"))
                }
            } else if let web = hit.webURL, let url = URL(string: web) {
                Button(L("打开网页")) { NSWorkspace.shared.open(url) }
                    .buttonStyle(PressableButtonStyle())
                    .font(Theme.Fonts.secondaryEmphasis)
                    .foregroundStyle(Theme.textSecondary)
                    .help(L("该源的安装物暂不支持直装，先到网页查看"))
            }
        }
        .padding(.horizontal, Theme.Space.s12)
        .padding(.vertical, Theme.Space.s8 + 2)
    }
}

/// v15 SourceBadge：结果行来源徽标；企业认证只展示，不改变任何门槛
private struct SourceBadge: View {
    var hit: SourceHit

    var body: some View {
        HStack(spacing: Theme.Space.s4) {
            Text(hit.kind.displayName)
            if let publisher = hit.publisher {
                Image(systemName: "checkmark.seal")
                    .font(.system(size: 8, weight: .semibold))
                    .help(LF("市场认证发布方：%@（仅供参考）", publisher))
            }
        }
        .font(Theme.Fonts.caption)
        .foregroundStyle(Theme.textTertiary)
        .padding(.horizontal, Theme.Space.s4 + 2)
        .frame(height: 16)
        .quietControl()
    }
}

/// v15 RequiresKeyChip：装前提示需要额外账号或密钥
private struct RequiresKeyChip: View {
    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "key")
                .font(.system(size: 8, weight: .semibold))
            Text(L("要密钥"))
                .font(Theme.Fonts.caption)
        }
        .foregroundStyle(Theme.warning)
        .padding(.horizontal, Theme.Space.s4 + 2)
        .frame(height: 16)
        .quietControl(tint: Theme.warning)
        .help(L("这个技能需要额外注册账号或配置密钥才能用"))
    }
}
