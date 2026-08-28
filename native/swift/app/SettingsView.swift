import ServiceManagement
import SwiftUI
#if SWIFT_PACKAGE
import AtlasCore
#endif

// MARK: - 设置页（居中 640 列，系统设置式分组）
//
// 分组：外观 · 通知 · 我在用的软件（平台开关 + 目录）· 技能库 · 发现来源
//      · 收件箱入口 · 导入与迁移 · 应用 · 进阶（使用记录 / 多机同步）
//
// 这里只放长期配置。运维事项归收件箱、供给归供给页、收编与迁移归发现页，
// 设置里只留一行指路——同一件事不给第二个入口（DESIGN v15）。
//
// 「我在用的软件」一格管两件事：界面里出不出现，以及新装技能默不默认勾选。
// 它们曾是相隔很远的两组开关，读起来就是同一个矩阵配了两遍。

struct SettingsPage: View {
    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Space.s20) {
                AppearanceGroup()
                NotifyGroup()
                PlatformsGroup()
                LibraryGroup()
                DiscoverySourcesGroup()
                InboxLinkGroup()
                LegacyImportGroup()
                AppGroup()
                AdvancedSettings()
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

/// Profile / Hook / Git 对第一次用的人没必要先看见。
private struct AdvancedSettings: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s12) {
            Button {
                if reduceMotion {
                    open.toggle()
                } else {
                    withAnimation(Motion.standard) { open.toggle() }
                }
            } label: {
                HStack(spacing: Theme.Space.s8) {
                    Text(L("进阶"))
                        .font(Theme.Fonts.secondaryEmphasis)
                        .foregroundStyle(Theme.textSecondary)
                    Text(L("场景、使用记录、多机同步"))
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.textTertiary)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                        .rotationEffect(.degrees(open ? 90 : 0))
                }
                .padding(.leading, Theme.Space.s4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(open ? L("收起进阶设置") : L("展开进阶设置"))
            if open {

                ProfileEntryGroup()
                TelemetryGroup()
                SyncGroup()
            }
        }
    }
}

// MARK: - 场景 Profile（三期 G8）

/// 场景包（v16：从供给页降到进阶）。作者本机数据：定义 1 个、绑定 0、生效 0、
/// 登记项目 0——投入几百行换来 0 使用率。留着入口，不占一级页。
private struct ProfileEntryGroup: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        SettingsGroup(title: "场景包") {
            HStack(spacing: Theme.Space.s12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("给不同项目配不同的技能"))
                        .font(Theme.Fonts.rowTitle)
                        .foregroundStyle(Theme.textPrimary)
                    Text(L("比如写基金材料时不想看到编程技能。只对 Claude Code 生效——只有它有「装着、但不进开场清单」这个开关。别的软件只有装或不装两种状态，没有中间档，场景在那边无从谈起。"))
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Theme.Space.s8)
                Button(L("管理场景…")) {
                    store.loadProfiles()
                    store.profileSheetPresented = true
                }
                .buttonStyle(.plain)
                .font(Theme.Fonts.secondaryEmphasis)
                .foregroundStyle(Theme.accent)
            }
            .padding(.horizontal, Theme.Space.s12)
            .frame(height: 56)
        }
    }
}

// MARK: - Hook 实时遥测（三期 G5）

private struct TelemetryGroup: View {
    @Environment(AppStore.self) private var store
    @State private var installed = false
    @State private var errorText: String?
    @State private var message: String?
    /// 事件计数缓存：只在 onAppear/动作后刷新——body 里直接读文件会每帧全量 I/O
    @State private var eventsCount = 0

    var body: some View {
        SettingsGroup(title: "使用记录") {
            SettingsRow(
                title: installed ? "已接入 Claude Code" : "接入 Claude Code",
                subtitle: installed
                    ? LF("每次真正调用技能都会记一行（已累计 %d 条）。", eventsCount)
                    : "接入后统计更准。写入前会备份原设置，随时可撤。",
                divider: false
            ) {
                HStack(spacing: Theme.Space.s8) {
                    if let message {
                        Text(message)
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(Theme.healthy)
                    }
                    if installed {
                        Button {
                            do {
                                try HookTelemetry.uninstall()
                                refresh()
                                flash(L("已移除，备份已留"))
                            } catch { errorText = error.localizedDescription }
                        } label: {
                            Text(L("移除接入"))
                                .font(Theme.Fonts.calloutEmphasis)
                                .foregroundStyle(Theme.textPrimary)
                                .padding(.horizontal, Theme.Space.s12)
                                .frame(height: 26)
                                .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                        }
                        .buttonStyle(PressableButtonStyle())
                        .quietControl()
                        .help(L("从 settings.json 移除本应用的 hook 条目（其余配置不动），并删除 hook 脚本"))
                    } else {
                        Button {
                            do {
                                try HookTelemetry.install()
                                refresh()
                                flash(L("已接入"))
                                store.mergeHookStats()
                            } catch { errorText = error.localizedDescription }
                        } label: {
                            Text(L("接入…"))
                                .font(Theme.Fonts.calloutEmphasis)
                                .foregroundStyle(.white)
                                .padding(.horizontal, Theme.Space.s12 + 2)
                                .frame(height: 26)
                                .contentShape(Capsule())
                        }
                        .buttonStyle(PressableButtonStyle())
                        .accentGlass(Capsule(style: .continuous))
                        .help(L("写入 hook 前会先备份 settings.json；hook 脚本永远 exit 0，不会阻塞任何工具调用"))
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
        installed = HookTelemetry.installed()
        eventsCount = HookTelemetry.totalEvents
    }

    private func flash(_ text: String) {
        message = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { message = nil }
    }
}

// MARK: - 本地技能收编（散装 → 本库，人人可用）

// MARK: - 分组骨架

/// 组标题在卡外（系统设置惯例），卡内行之间发丝分隔
/// 平台行：品牌图标 + 名称 + 真实目录 + 目录改写 + 在用开关。
/// 图标从原「我在用的软件」那一格搬上来——两处开关合并后，识别度不能丢。
private struct PlatformSettingRow<Trailing: View>: View {
    var platform: AgentPlatform
    var subtitle: String
    var divider: Bool
    @ViewBuilder var trailing: Trailing

    init(platform: AgentPlatform, subtitle: String, divider: Bool, @ViewBuilder trailing: () -> Trailing) {
        self.platform = platform
        self.subtitle = subtitle
        self.divider = divider
        self.trailing = trailing()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.Space.s12) {
                PlatformLogo(platform: platform, size: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(platform.displayName)
                        .font(Theme.Fonts.rowTitle)
                        .foregroundStyle(Theme.textPrimary)
                    Text(subtitle)
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Theme.Space.s8)
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

/// v15 WP-M：发现来源开关（护栏 §7-19：总闸 + 每源双控，关闸即零出网）
private struct DiscoverySourcesGroup: View {
    @Environment(AppStore.self) private var store
    /// 开关落 ~/.skill-atlas/sources.json（App 与 CLI 共享），不是 UserDefaults：
    /// 两个可执行文件的 domain 不通，用 @AppStorage 的话设置页管不到 atlas 命令。
    @State private var revision = 0

    var body: some View {
        SettingsGroup(title: "发现来源") {
            sourceRow(
                title: L("远程发现"),
                caption: L("总闸。关掉后「添加技能」与 atlas search --remote 全部零出网。"),
                isOn: SourcePrefs.masterEnabled,
                enabled: true
            ) { try SourcePrefs.setMaster($0) }
            divider
            sourceRow(
                title: "skills.sh",
                caption: L("Vercel 全球索引，结果指向 GitHub 仓库，走既有安装管线。"),
                isOn: SourceKind.skillssh.enabled,
                enabled: SourcePrefs.masterEnabled
            ) { try SourcePrefs.set($0, for: .skillssh) }
            divider
            sourceRow(
                title: "SkillHub",
                caption: L("腾讯技能市场（skillhub.cn）。榜单与认证仅供参考，安装照样过扫描。"),
                isOn: SourceKind.skillhub.enabled,
                enabled: SourcePrefs.masterEnabled
            ) { try SourcePrefs.set($0, for: .skillhub) }
        }
        .id(revision)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.06))
            .frame(height: 1)
            .padding(.leading, Theme.Space.s12)
    }

    private func sourceRow(
        title: String,
        caption: String,
        isOn: Bool,
        enabled: Bool,
        write: @escaping (Bool) throws -> Void
    ) -> some View {
        HStack(spacing: Theme.Space.s12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Fonts.rowTitle)
                    .foregroundStyle(enabled ? Theme.textPrimary : Theme.textTertiary)
                Text(caption)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Theme.Space.s8)
            Toggle("", isOn: Binding(
                get: { isOn },
                set: { next in
                    do {
                        try write(next)
                        revision &+= 1
                    } catch {
                        store.actionError = error.localizedDescription
                    }
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            .disabled(!enabled)
            .accessibilityLabel(title)
        }
        .padding(.horizontal, Theme.Space.s12)
        .padding(.vertical, Theme.Space.s8 + 2)
    }
}

/// v15：收编与 CC Switch 迁移的家在发现页导入区，设置只留一行指路。
/// 完整的迁移向导（机制图 + 迁入 + 撤销 + 清理副本）仍由 MigrationSheet 承载。
private struct LegacyImportGroup: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        SettingsGroup(title: "导入与迁移") {
            HStack(spacing: Theme.Space.s12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("收编与迁移都在「添加技能」"))
                        .font(Theme.Fonts.rowTitle)
                        .foregroundStyle(Theme.textPrimary)
                    Text(subtitle)
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Theme.Space.s8)
                Button(L("去「添加技能」")) { store.nav = .add }
                    .buttonStyle(.plain)
                    .font(Theme.Fonts.secondaryEmphasis)
                    .foregroundStyle(Theme.accent)
                    .help(L("散落技能的收编与 CC Switch 迁入都在那里"))
            }
            .padding(.horizontal, Theme.Space.s12)
            .frame(height: 52)
            if store.canRollback {
                Rectangle()
                    .fill(Color.primary.opacity(0.06))
                    .frame(height: 1)
                    .padding(.leading, Theme.Space.s12)
                HStack(spacing: Theme.Space.s12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("撤销 CC Switch 迁移"))
                            .font(Theme.Fonts.rowTitle)
                            .foregroundStyle(Theme.textPrimary)
                        Text(L("把迁入的技能退回去，原文件本来就没动过。"))
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    Spacer(minLength: Theme.Space.s8)
                    Button(L("撤销迁移")) { store.rollbackMigration() }
                        .buttonStyle(.plain)
                        .font(Theme.Fonts.secondaryEmphasis)
                        .foregroundStyle(Theme.textSecondary)
                        .disabled(store.migrating)
                }
                .padding(.horizontal, Theme.Space.s12)
                .frame(height: 52)
            }
        }
    }

    private var subtitle: String {
        let adoptable = store.adoptableSkills.count
        if adoptable > 0 {
            return LF("现在有 %d 个散落技能可以收编。", adoptable)
        }
        return store.canMigrate
            ? L("检测到 CC Switch 的技能，可以在「添加技能」里迁入。")
            : L("散落在平台目录里的技能、CC Switch 的旧库，都从那里进来。")
    }
}

/// v15：维护组解散进收件箱（WP-I），设置只留一个入口行
private struct InboxLinkGroup: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        SettingsGroup(title: "检查") {
            HStack(spacing: Theme.Space.s12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("要你处理的事都在「检查」"))
                        .font(Theme.Fonts.rowTitle)
                        .foregroundStyle(Theme.textPrimary)
                    Text(L("等你点头、有危险写法、装了用不了、叫不动——只有这四类会来找你"))
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer(minLength: Theme.Space.s8)
                Button(L("去「检查」")) { store.nav = .check }
                    .buttonStyle(.plain)
                    .font(Theme.Fonts.secondaryEmphasis)
                    .foregroundStyle(Theme.accent)
            }
            .padding(.horizontal, Theme.Space.s12)
            .frame(height: 52)
        }
    }
}

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

private struct NotifyGroup: View {
    @AppStorage(AtlasNotify.securityKey) private var security = true
    @AppStorage(AtlasNotify.missKey) private var miss = false
    @AppStorage(AtlasNotify.updatesKey) private var updates = false

    var body: some View {
        SettingsGroup(title: "通知") {
            SettingsRow(title: "新技能有可疑写法", subtitle: "只在新出现时提醒一次，已知的留在「检查」里排队。默认开。") {
                Toggle("", isOn: $security)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }
            SettingsRow(title: "本周 miss", subtitle: "有技能该触发却没触发时汇总提醒。默认关。") {
                Toggle("", isOn: $miss)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }
            SettingsRow(title: "可更新", subtitle: "每天最多一次。默认关。", divider: false) {
                Toggle("", isOn: $updates)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }
        }
        .onChange(of: security) { _, _ in AtlasNotify.requestAuthorization() }
    }
}

private struct PlatformsGroup: View {
    @Environment(AppStore.self) private var store
    @State private var rootRevision = 0

    var body: some View {
        SettingsGroup(title: "AI 软件") {
            ForEach(Array(AgentPlatform.allCases.enumerated()), id: \.element.id) { index, platform in
                PlatformSettingRow(
                    platform: platform,
                    subtitle: subtitle(for: platform),
                    divider: index < AgentPlatform.allCases.count - 1
                ) {
                    HStack(spacing: Theme.Space.s8) {
                        Button(L("目录…")) { chooseRoot(platform) }
                            .buttonStyle(.plain)
                            .font(Theme.Fonts.secondaryEmphasis)
                            .foregroundStyle(Theme.accent)
                            .help(L("改成这个软件真正读取的技能目录"))
                        if platform.hasCustomRoot {
                            Button(L("恢复默认")) { setRoot(nil, for: platform) }
                                .buttonStyle(.plain)
                                .font(Theme.Fonts.caption)
                                .foregroundStyle(Theme.textTertiary)
                        }
                        Toggle("", isOn: Binding(
                            get: { store.visiblePlatforms.contains(platform) },
                            set: { store.setVisible(platform, on: $0) }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                        .help(L("关掉后它不在界面出现，新装的技能也不会默认装到这里。已有软链不动。"))
                    }
                }
            }
        }
        .id(rootRevision)
    }

    /// 副文案就说这个平台的技能目录在哪——这是「同步点亮了却没生效」时
    /// 唯一能自查的信息，不该藏起来。
    private func subtitle(for platform: AgentPlatform) -> String {
        let path = platform.root(home: AtlasPaths.home).path
            .replacingOccurrences(of: AtlasPaths.home.path, with: "~")
        if platform.hasCustomRoot {
            return LF("已自定义：%@", path)
        }
        if platform.rootNeedsConfirmation {
            return LF("%@（豆包读的是你在它里面指定的文件夹，不一致就点「目录…」改）", path)
        }
        return path
    }

    private func chooseRoot(_ platform: AgentPlatform) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = L("选定")
        panel.message = LF("选择 %@ 实际读取技能的目录", platform.displayName)
        panel.directoryURL = platform.root(home: AtlasPaths.home)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setRoot(url.path, for: platform)
    }

    private func setRoot(_ path: String?, for platform: AgentPlatform) {
        do {
            try PlatformRoots.set(path, for: platform)
            Oplog.append(op: "platform-root", target: platform.rawValue, ok: true, detail: path ?? "default")
            rootRevision &+= 1
            Task { await store.rescan() }
        } catch {
            store.actionError = error.localizedDescription
        }
    }
}

private struct AppearanceGroup: View {
    @Environment(AppStore.self) private var store
    @AppStorage("atlasMenuBarEnabled") private var menuBarEnabled = true
    @State private var mode = AppearanceMode.stored

    var body: some View {
        SettingsGroup(title: "外观") {
            SettingsRow(title: "界面样式", subtitle: "跟随系统，或固定浅色 / 深色。") {
                stylePicker
            }
            SettingsRow(
                title: "菜单栏快速搜索",
                subtitle: "任何应用里按 ⌥⌘K 搜技能、复制调用语。"
            ) {
                Toggle("", isOn: $menuBarEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }
            SettingsRow(
                title: "语言",
                subtitle: "切换立即生效，技能本身的名称和描述保持原文。"
            ) {
                languagePicker
            }
            SettingsRow(
                title: "登录时打开",
                subtitle: "关窗后仍留在菜单栏。默认关。",
                divider: false
            ) {
                Toggle("", isOn: loginBinding)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }
        }
    }

    private var loginBinding: Binding<Bool> {
        Binding(
            get: { SMAppService.mainApp.status == .enabled },
            set: { on in
                do {
                    if on { try SMAppService.mainApp.register() }
                    else { try SMAppService.mainApp.unregister() }
                } catch {
                    store.actionError = error.localizedDescription
                }
            }
        )
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
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pathsExpanded = false

    var body: some View {
        SettingsGroup(title: "技能库") {
            SettingsRow(
                title: "库位置",
                subtitle: "技能文件、备份都在这里。"
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
                subtitle: "本库和各软件的技能目录。"
            ) {
                Button {
                    withAnimation(reduceMotion ? nil : Motion.control) { pathsExpanded.toggle() }
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
                subtitle: "目录有变化会自动刷新。这里是手动再扫一次。",
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

/// 迁移机制图：CC Switch --复制--> 本库 --软链--> 可见平台（迁移引导 sheet 复用）
struct MigrationFlow: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        HStack(spacing: Theme.Space.s8) {
            node(title: "CC Switch", path: "~/.cc-switch/skills", note: "原文件不动")
            arrow(label: "复制")
            node(title: "Skill Atlas 库", path: "~/.skill-atlas/skills", note: "唯一管理点")
            arrow(label: "软链")
            VStack(alignment: .leading, spacing: Theme.Space.s4) {
                HStack(spacing: Theme.Space.s4) {
                    ForEach(store.visiblePlatforms) { platform in
                        PlatformLogo(platform: platform, size: 16)
                    }
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
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.3.1"
    }

    /// 打包副本优先（与仓库 docs/handbook.md 同一份，构建脚本负责拷入）；
    /// swift build 裸二进制没有资源，退到 GitHub 原文。
    private func openHandbook() {
        if let bundled = Bundle.main.url(forResource: "handbook", withExtension: "md") {
            NSWorkspace.shared.open(bundled)
        } else if let remote = URL(string: "https://github.com/shoumunan/skill-atlas/blob/main/docs/handbook.md") {
            NSWorkspace.shared.open(remote)
        }
    }

    var body: some View {
        SettingsGroup(title: "应用") {
            SettingsRow(
                title: L("使用手册"),
                subtitle: L("四条工作流与边界都在这一份里。agent 不用读，元技能已教会它。"),
                divider: true
            ) {
                AtlasSecondaryButton(title: L("打开")) { openHandbook() }
                    .help(L("与仓库 docs/handbook.md 是同一份"))
            }
            SettingsRow(
                title: "Skill Atlas \(version)",
                subtitle: updates.available.map { LF("发现新版本 %@，点右侧按钮应用内自动更新（下载、校验、换装、重启一条龙）。", $0.version) }
                    ?? (UpdateChecker.feedConfigured ? L("启动时自动检查一次新版本；有新版可一键应用内更新。") : L("本地构建 · 未配置更新源，重新构建即为最新。")),
                divider: false
            ) {
                Button {
                    if let feed = updates.available {
                        updates.presentAvailable(feed)
                    } else {
                        UpdateChecker.shared.checkFromMenu()
                    }
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
                    subtitle: "把本库变成 Git 仓库。换电脑时拷过去再扫一次即可。",
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
                    subtitle: "记下当前改动。推到网上请在终端里做。",
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
