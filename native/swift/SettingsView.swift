import SwiftUI

// MARK: - 设置页（v7 重排：系统设置式分组，居中 640 列）
//
// 四组：外观（界面样式 / 菜单栏 / 语言）· 技能库（位置 / 扫描范围 / 重扫）
//      · 从 CC Switch 迁移（机制图 + 状态 + 动作）· 应用（版本 / 更新）
// 全部是真设置：界面样式立即生效并持久化，菜单栏开关直接撤下图标。

struct SettingsPage: View {
    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Space.s20) {
                AppearanceGroup()
                LibraryGroup()
                SyncGroup()
                MigrationGroup()
                AppGroup()
            }
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
            .padding(Theme.Space.s24)
        }
        .panelScroll()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentSurface()
    }
}

// MARK: - 分组骨架

/// 组标题在卡外（系统设置惯例），卡内行之间发丝分隔
private struct SettingsGroup<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s8) {
            Text(L(title))
                .font(Theme.Fonts.secondaryEmphasis)
                .foregroundStyle(Theme.textSecondary)
                .padding(.leading, Theme.Space.s4)
            VStack(spacing: 0) {
                content
            }
            .quietControl(cornerRadius: Theme.Radius.tile)
        }
    }
}

/// 标准设置行：左侧标题 + 副文案，右侧控件
private struct SettingsRow<Trailing: View>: View {
    var title: String
    var subtitle: String?
    var divider = true
    @ViewBuilder var trailing: Trailing

    init(title: String, subtitle: String? = nil, divider: Bool = true, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.divider = divider
        self.trailing = trailing()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: Theme.Space.s12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L(title))
                        .font(Theme.Fonts.body)
                        .foregroundStyle(Theme.textPrimary)
                    if let subtitle {
                        Text(L(subtitle))
                            .font(Theme.Fonts.secondary)
                            .lineSpacing(2)
                            .foregroundStyle(Theme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: Theme.Space.s16)
                trailing
            }
            .padding(.horizontal, Theme.Space.s16)
            .padding(.vertical, Theme.Space.s12)
            if divider {
                Rectangle()
                    .fill(Color.primary.opacity(0.06))
                    .frame(height: 1)
                    .padding(.leading, Theme.Space.s16)
            }
        }
    }
}

// MARK: - 外观

private struct AppearanceGroup: View {
    @EnvironmentObject private var store: AppStore
    @AppStorage("atlasMenuBarEnabled") private var menuBarEnabled = true
    @State private var mode = AppearanceMode.stored

    var body: some View {
        SettingsGroup(title: "外观") {
            SettingsRow(title: "界面样式", subtitle: "跟随系统会随日落自动切换深浅色。") {
                stylePicker
            }
            SettingsRow(
                title: "菜单栏快速搜索",
                subtitle: "常驻菜单栏图标，在任何应用里按 ⌥⌘K 搜技能、回车复制调用语。"
            ) {
                Toggle("", isOn: $menuBarEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }
            SettingsRow(
                title: "语言",
                subtitle: "切换立即生效，技能本身的名称和描述保持原文。",
                divider: false
            ) {
                languagePicker
            }
        }
    }

    /// 语言菜单：语言名用它自己的语言写，当前项打勾
    private var languagePicker: some View {
        Menu {
            ForEach(AppLanguage.allCases) { language in
                Button {
                    store.selectLanguage(language)
                } label: {
                    if store.uiLanguage == language {
                        Label(language.label, systemImage: "checkmark")
                    } else {
                        Text(language.label)
                    }
                }
            }
        } label: {
            HStack(spacing: Theme.Space.s4) {
                Text(store.uiLanguage.label)
                    .font(Theme.Fonts.calloutEmphasis)
                    .foregroundStyle(Theme.textPrimary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, Theme.Space.s8 + 2)
            .frame(height: 26)
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .quietControl()
    }

    private var stylePicker: some View {
        HStack(spacing: 2) {
            ForEach(AppearanceMode.allCases) { candidate in
                let active = mode == candidate
                Button {
                    mode = candidate
                    AppearanceMode.select(candidate)
                } label: {
                    HStack(spacing: Theme.Space.s4) {
                        Image(systemName: candidate.symbol)
                            .font(.system(size: 10, weight: .medium))
                        Text(candidate.label)
                            .font(active ? Theme.Fonts.calloutEmphasis : Theme.Fonts.callout)
                    }
                    .foregroundStyle(active ? Theme.textPrimary : Theme.textSecondary)
                    .padding(.horizontal, Theme.Space.s8 + 2)
                    .frame(height: 24)
                    .background {
                        if active {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(.background)
                                .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .quietControl()
    }
}

// MARK: - 技能库

private struct LibraryGroup: View {
    @EnvironmentObject private var store: AppStore
    @State private var pathsExpanded = false

    var body: some View {
        SettingsGroup(title: "技能库") {
            SettingsRow(
                title: "库位置",
                subtitle: "技能源目录、卸载备份、迁移回滚清单都在这一个文件夹里。"
            ) {
                HStack(spacing: Theme.Space.s8) {
                    Text("~/.skill-atlas/")
                        .font(Theme.Fonts.mono)
                        .foregroundStyle(Theme.textSecondary)
                        .textSelection(.enabled)
                    Button(L("在访达中显示")) {
                        store.openFolder(AtlasPaths.root.path)
                    }
                    .buttonStyle(.plain)
                    .font(Theme.Fonts.calloutEmphasis)
                    .foregroundStyle(Theme.accent)
                }
            }
            SettingsRow(
                title: "扫描范围",
                subtitle: "本库 + CC Switch 源（只读）+ 各平台技能目录，软链去重后合并展示。"
            ) {
                Button {
                    withAnimation(Motion.control) { pathsExpanded.toggle() }
                } label: {
                    HStack(spacing: Theme.Space.s4) {
                        Text(LF("%lld 个目录", store.data?.summary.checkedPaths.count ?? 0))
                            .font(Theme.Fonts.callout)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                            .rotationEffect(.degrees(pathsExpanded ? 180 : 0))
                    }
                    .foregroundStyle(Theme.textSecondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if pathsExpanded {
                VStack(alignment: .leading, spacing: Theme.Space.s4) {
                    ForEach(store.data?.summary.checkedPaths ?? [], id: \.self) { path in
                        Text(path)
                            .font(Theme.Fonts.mono)
                            .textSelection(.enabled)
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .padding(.horizontal, Theme.Space.s16)
                .padding(.bottom, Theme.Space.s12)
                .frame(maxWidth: .infinity, alignment: .leading)
                Rectangle()
                    .fill(Color.primary.opacity(0.06))
                    .frame(height: 1)
                    .padding(.leading, Theme.Space.s16)
            }
            SettingsRow(
                title: "重新扫描",
                subtitle: "目录有变化会自动刷新（FSEvents）；这里是手动兜底。",
                divider: false
            ) {
                Button {
                    Task { await store.rescan() }
                } label: {
                    Text(L("重新扫描"))
                        .font(Theme.Fonts.calloutEmphasis)
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, Theme.Space.s12)
                        .frame(height: 26)
                        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                }
                .buttonStyle(PressableButtonStyle())
                .quietControl()
                .disabled(store.scanning)
                .help(L("重新扫描全部目录（⌘R）"))
            }
        }
    }
}

// MARK: - 从 CC Switch 迁移

private struct MigrationGroup: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        SettingsGroup(title: "从 CC Switch 迁移") {
            VStack(alignment: .leading, spacing: Theme.Space.s12) {
                // 机制：一张图讲清「复制进库，软链出去」
                MigrationFlow()
                Text(L("迁移做两件事：把 CC Switch 库里的技能完整复制进本库（原文件一个不动），再把各平台技能目录里的软链改指本库。之后开关平台、更新、卸载都在这里完成；CC Switch 的数据库和原目录始终只读。撤销迁移只把软链指回去，本库副本保留。"))
                    .font(Theme.Fonts.secondary)
                    .lineSpacing(3)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(L("没用过 CC Switch？不需要这一步：用「安装技能」直接装进本库；已经散装在各平台目录里的技能会被自动收录展示，随时可选择收进库统一管理。"))
                    .font(Theme.Fonts.secondary)
                    .lineSpacing(3)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Theme.Space.s16)
            .frame(maxWidth: .infinity, alignment: .leading)
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 1)
                .padding(.leading, Theme.Space.s16)
            SettingsRow(title: "状态", subtitle: nil, divider: store.data?.summary.migrated == true) {
                Text(migrationStatus)
                    .font(Theme.Fonts.callout)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.trailing)
            }
            if store.data?.summary.migrated == true {
                SettingsRow(
                    title: "清理 CC Switch 副本",
                    subtitle: "迁移是复制，原文件还在 ~/.cc-switch/skills 占着空间。清理前会逐个校验迁移结果，未通过的不动；操作前有明确的不可逆警告。",
                    divider: false
                ) {
                    Button {
                        store.cleanupSheetPresented = true
                    } label: {
                        Text(L("检查并清理…"))
                            .font(Theme.Fonts.calloutEmphasis)
                            .foregroundStyle(Theme.textPrimary)
                            .padding(.horizontal, Theme.Space.s12)
                            .frame(height: 26)
                            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                    }
                    .buttonStyle(PressableButtonStyle())
                    .quietControl()
                }
            }
            HStack(spacing: Theme.Space.s8) {
                Spacer()
                Button {
                    store.rollbackMigration()
                } label: {
                    Text(L("撤销迁移"))
                        .font(Theme.Fonts.calloutEmphasis)
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, Theme.Space.s12)
                        .frame(height: 26)
                        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                }
                .buttonStyle(PressableButtonStyle())
                .quietControl()
                .disabled(!store.canRollback || store.migrating)
                Button {
                    store.migrationSheetPresented = true
                } label: {
                    Text(L("迁入…"))
                        .font(Theme.Fonts.calloutEmphasis)
                        .foregroundStyle(.white)
                        .padding(.horizontal, Theme.Space.s12 + 2)
                        .frame(height: 26)
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableButtonStyle())
                .accentGlass(Capsule(style: .continuous))
                .disabled(!store.canMigrate || store.migrating)
                .opacity(store.canMigrate && !store.migrating ? 1 : 0.4)
                .help(store.canMigrate ? L("把 CC Switch 里的技能收进本库") : L("已迁入或本机没有 CC Switch 数据"))
            }
            .padding(.horizontal, Theme.Space.s16)
            .padding(.bottom, Theme.Space.s12)
        }
    }

    private var migrationStatus: String {
        guard let summary = store.data?.summary else { return "尚未扫描" }
        if summary.migrated {
            return "已迁入 \(summary.atlasCount) 个技能"
        }
        if summary.hasCCSwitch {
            let plan = SkillMigrator.plan()
            return "发现 \(plan.total) 个技能可迁入"
        }
        return "本机没有 CC Switch 数据"
    }
}

/// 迁移机制图：CC Switch --复制--> 本库 --软链--> 四个平台（迁移引导 sheet 复用）
struct MigrationFlow: View {
    var body: some View {
        HStack(spacing: Theme.Space.s8) {
            node(title: "CC Switch", path: "~/.cc-switch/skills", note: "原文件不动")
            arrow(label: "复制")
            node(title: "Skill Atlas 库", path: "~/.skill-atlas/skills", note: "唯一管理点")
            arrow(label: "软链")
            VStack(alignment: .leading, spacing: Theme.Space.s4) {
                HStack(spacing: Theme.Space.s4) {
                    PlatformLogo(platform: .claude, size: 16)
                    PlatformLogo(platform: .codex, size: 16)
                    PlatformLogo(platform: .gemini, size: 16)
                    PlatformLogo(platform: .grokbuild, size: 16)
                }
                Text(L("各平台 skills 目录"))
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textSecondary)
                Text(L("软链指向本库"))
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(Theme.Space.s8 + 2)
            .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
            .quietControl(cornerRadius: Theme.Radius.row)
        }
        .frame(maxWidth: .infinity)
    }

    private func node(title: String, path: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s4) {
            Text(L(title))
                .font(Theme.Fonts.secondaryEmphasis)
                .foregroundStyle(Theme.textPrimary)
            Text(path)
                .font(Theme.Fonts.mono)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(L(note))
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(Theme.Space.s8 + 2)
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
        .quietControl(cornerRadius: Theme.Radius.row)
    }

    private func arrow(label: String) -> some View {
        VStack(spacing: 2) {
            Text(L(label))
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize()
            Image(systemName: "arrow.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
        }
    }
}

// MARK: - 应用

private struct AppGroup: View {
    @ObservedObject private var updates = UpdateChecker.shared

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.3.0"
    }

    var body: some View {
        SettingsGroup(title: "应用") {
            SettingsRow(
                title: "Skill Atlas \(version)",
                subtitle: updates.available.map { LF("发现新版本 %@，点右侧按钮更新。", $0.version) }
                    ?? (UpdateChecker.feedConfigured ? L("启动时自动检查一次新版本。") : L("本地构建 · 未配置更新源，重新构建即为最新。")),
                divider: false
            ) {
                Button {
                    UpdateChecker.shared.checkFromMenu()
                } label: {
                    Text(updates.available == nil ? L("检查更新…") : LF("更新到 %@", updates.available?.version ?? ""))
                        .font(Theme.Fonts.calloutEmphasis)
                        .foregroundStyle(updates.available == nil ? Theme.textPrimary : Theme.accent)
                        .padding(.horizontal, Theme.Space.s12)
                        .frame(height: 26)
                        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                }
                .buttonStyle(PressableButtonStyle())
                .quietControl(tint: updates.available == nil ? nil : Theme.accent)
            }
        }
    }
}


// MARK: - 多机同步（二期 F8：库 git 化最小闭环）

private struct SyncGroup: View {
    @State private var status: GitSync.Status?
    @State private var isRepo = GitSync.isRepo()
    @State private var message: String?
    @State private var errorText: String?

    var body: some View {
        SettingsGroup(title: "多机同步") {
            if !isRepo {
                SettingsRow(
                    title: "把库变成 Git 仓库",
                    subtitle: "对 ~/.skill-atlas/ 执行 git init 并做首次提交（使用缓存与卸载备份不入库）。换机时 clone 后重新扫描即可重建挂载。",
                    divider: false
                ) {
                    Button {
                        do {
                            try GitSync.initialize()
                            refresh()
                        } catch {
                            errorText = error.localizedDescription
                        }
                    } label: {
                        Text("初始化…")
                            .font(Theme.Fonts.calloutEmphasis)
                            .foregroundStyle(.white)
                            .padding(.horizontal, Theme.Space.s12 + 2)
                            .frame(height: 26)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(PressableButtonStyle())
                    .accentGlass(Capsule(style: .continuous))
                }
            } else {
                SettingsRow(
                    title: "仓库状态",
                    subtitle: status.map { LF("分支 %@ · 未提交改动 %d 项", $0.branch, $0.dirtyCount) }
                        ?? L("读取中…")
                ) {
                    Text(status?.lastCommit ?? "")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                SettingsRow(
                    title: "提交快照",
                    subtitle: "git add -A + commit。配远端与 push 在终端里做。",
                    divider: false
                ) {
                    HStack(spacing: Theme.Space.s8) {
                        if let message {
                            Text(message)
                                .font(Theme.Fonts.caption)
                                .foregroundStyle(Theme.healthy)
                        }
                        Button {
                            GitSync.openInTerminal()
                        } label: {
                            Text("在终端打开")
                                .font(Theme.Fonts.calloutEmphasis)
                                .foregroundStyle(Theme.textPrimary)
                                .padding(.horizontal, Theme.Space.s12)
                                .frame(height: 26)
                                .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                        }
                        .buttonStyle(PressableButtonStyle())
                        .quietControl()
                        Button {
                            do {
                                let committed = try GitSync.snapshot()
                                message = committed ? L("已提交") : L("没有改动")
                                refresh()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { message = nil }
                            } catch {
                                errorText = error.localizedDescription
                            }
                        } label: {
                            Text("提交快照")
                                .font(Theme.Fonts.calloutEmphasis)
                                .foregroundStyle(.white)
                                .padding(.horizontal, Theme.Space.s12 + 2)
                                .frame(height: 26)
                                .contentShape(Capsule())
                        }
                        .buttonStyle(PressableButtonStyle())
                        .accentGlass(Capsule(style: .continuous))
                    }
                }
            }
            if let errorText {
                Text(errorText)
                    .font(Theme.Fonts.secondary)
                    .foregroundStyle(Theme.error)
                    .padding(.horizontal, Theme.Space.s16)
                    .padding(.bottom, Theme.Space.s12)
            }
        }
        .onAppear { refresh() }
    }

    private func refresh() {
        isRepo = GitSync.isRepo()
        status = GitSync.status()
    }
}
