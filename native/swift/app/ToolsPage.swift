import AppKit
import SwiftUI
#if SWIFT_PACKAGE
import AtlasCore
#endif

// MARK: - 软件（内置平台 + 自定义工具 + 发现扫描 + 项目）
//
// skills-hub 的 Tools / 项目范围搬到这一页。设置只留外观和来源。

struct ToolsPage: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Space.s20) {
                PlatformsGroup()
                CustomToolsGroup()
                DiscoveryScanGroup()
                ProjectsGroup()
            }
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
            .padding(Theme.Space.s24)
            .id(store.hubRevision)
        }
        .panelScroll()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentSurface()
    }
}

struct CustomToolsGroup: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let file = CustomTools.load()
        let detected = ToolPresets.detected()
        SettingsGroup(title: "更多软件") {
            if file.tools.isEmpty && detected.isEmpty {
                SettingsRow(
                    title: "还没有额外软件",
                    subtitle: "本机已支持的那几个在上面。这里加 Trae、Copilot 这类，或自己选一个目录。",
                    divider: false
                ) {
                    Button(L("添加目录…")) { addDirectory() }
                        .buttonStyle(.plain)
                        .font(Theme.Fonts.secondaryEmphasis)
                        .foregroundStyle(Theme.accent)
                }
            } else {
                ForEach(Array(file.tools.enumerated()), id: \.element.id) { index, tool in
                    SettingsRow(
                        title: tool.label,
                        subtitle: tool.skillsDir,
                        divider: index < file.tools.count - 1 || !detected.isEmpty
                    ) {
                        HStack(spacing: Theme.Space.s8) {
                            Button(L("去掉")) { store.removeCustomTool(id: tool.id) }
                                .buttonStyle(.plain)
                                .font(Theme.Fonts.caption)
                                .foregroundStyle(Theme.textTertiary)
                            Toggle("", isOn: Binding(
                                get: { tool.enabled },
                                set: { store.setCustomToolEnabled(id: tool.id, enabled: $0) }
                            ))
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .labelsHidden()
                        }
                    }
                }
                ForEach(Array(detected.enumerated()), id: \.element.id) { index, preset in
                    SettingsRow(
                        title: preset.label,
                        subtitle: LF("本机有这个软件，技能目录：%@", preset.skillsDir),
                        divider: index < detected.count - 1
                    ) {
                        Button(L("加上")) { store.addToolPreset(preset) }
                            .buttonStyle(.plain)
                            .font(Theme.Fonts.secondaryEmphasis)
                            .foregroundStyle(Theme.accent)
                    }
                }
                if !file.tools.isEmpty || !detected.isEmpty {
                    SettingsRow(title: "自己加一个", subtitle: "选这个软件实际读取技能的目录。", divider: false) {
                        Button(L("添加目录…")) { addDirectory() }
                            .buttonStyle(.plain)
                            .font(Theme.Fonts.secondaryEmphasis)
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
        }
    }

    private func addDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = L("选定")
        panel.message = L("选这个软件实际读取技能的目录")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.addCustomTool(label: url.lastPathComponent, skillsDir: url.path)
    }
}

struct DiscoveryScanGroup: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        SettingsGroup(title: "发现扫描") {
            Text(L("关掉的目录不再出现「还没收进本库」的技能。上面点亮软件和这里是两回事。"))
                .font(Theme.Fonts.secondary)
                .foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, Theme.Space.s16)
                .padding(.top, Theme.Space.s12)
            ForEach(Array(AgentPlatform.allCases.enumerated()), id: \.element.id) { index, platform in
                SettingsRow(
                    title: platform.displayName,
                    subtitle: nil,
                    divider: index < AgentPlatform.allCases.count - 1 || !CustomTools.load().tools.isEmpty
                ) {
                    Toggle("", isOn: Binding(
                        get: { DiscoveryPrefs.isEnabled(platform.rawValue) },
                        set: { store.setDiscovery(platform.rawValue, enabled: $0) }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                }
            }
            let extras = CustomTools.load().tools
            ForEach(Array(extras.enumerated()), id: \.element.id) { index, tool in
                SettingsRow(title: tool.label, divider: index < extras.count - 1) {
                    Toggle("", isOn: Binding(
                        get: { DiscoveryPrefs.isEnabled(tool.id) },
                        set: { store.setDiscovery(tool.id, enabled: $0) }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                }
            }
        }
    }
}

struct ProjectsGroup: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let projects = ProjectSync.load().projects
        SettingsGroup(title: "项目") {
            if projects.isEmpty {
                SettingsRow(
                    title: "还没有项目",
                    subtitle: "技能仍只在本库一份。勾上项目后，会在那个文件夹里建软链。",
                    divider: false
                ) {
                    Button(L("添加文件夹…")) { addProject() }
                        .buttonStyle(.plain)
                        .font(Theme.Fonts.secondaryEmphasis)
                        .foregroundStyle(Theme.accent)
                }
            } else {
                ForEach(Array(projects.enumerated()), id: \.element.id) { index, project in
                    SettingsRow(
                        title: project.displayName,
                        subtitle: project.path,
                        divider: index < projects.count - 1
                    ) {
                        Button(L("去掉")) { store.removeSyncProject(id: project.id) }
                            .buttonStyle(.plain)
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                SettingsRow(title: "再加一个", subtitle: "选项目根目录，技能软链会写到它的技能文件夹里。", divider: false) {
                    Button(L("添加文件夹…")) { addProject() }
                        .buttonStyle(.plain)
                        .font(Theme.Fonts.secondaryEmphasis)
                        .foregroundStyle(Theme.accent)
                }
            }
        }
    }

    private func addProject() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = L("选定")
        panel.message = L("选要同步技能的项目文件夹")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.addSyncProject(path: url.path)
    }
}
