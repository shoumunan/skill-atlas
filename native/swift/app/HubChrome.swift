import AppKit
import SwiftUI
#if SWIFT_PACKAGE
import AtlasCore
#endif

// MARK: - skills-hub 交互搬进本库的共用控件（视觉仍走 Theme）

struct TagChipRow: View {
    var names: [String]

    var body: some View {
        if names.isEmpty {
            Text(L("还没有标签"))
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.textTertiary)
        } else {
            HStack(spacing: 6) {
                ForEach(names, id: \.self) { name in
                    Text(name)
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Theme.accent.opacity(0.12), in: Capsule())
                }
            }
        }
    }
}

struct TagEditorSheet: View {
    @Environment(AppStore.self) private var store
    var directory: String
    @State private var draft: Set<String> = []
    @State private var newName = ""

    var body: some View {
        let all = SkillTags.withCounts()
        VStack(alignment: .leading, spacing: Theme.Space.s16) {
            Text(L("标签"))
                .font(Theme.Fonts.panelTitle)
            if all.isEmpty && newName.isEmpty {
                Text(L("标签只用来查找和整理，不会改同步到哪些软件。"))
                    .font(Theme.Fonts.secondary)
                    .foregroundStyle(Theme.textSecondary)
            }
            ForEach(all, id: \.tag.id) { row in
                Toggle(isOn: Binding(
                    get: { draft.contains(row.tag.id) },
                    set: { on in
                        if on { draft.insert(row.tag.id) } else { draft.remove(row.tag.id) }
                    }
                )) {
                    Text("\(row.tag.name) · \(row.count)")
                        .font(Theme.Fonts.callout)
                }
                .toggleStyle(.checkbox)
            }
            HStack {
                TextField(L("新标签"), text: $newName)
                    .textFieldStyle(.roundedBorder)
                Button(L("加上")) {
                    store.addTagName(newName, to: directory)
                    newName = ""
                    draft = Set(SkillTags.load().links[directory] ?? [])
                }
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            HStack {
                Spacer()
                Button(L("取消")) { store.tagEditorDirectory = nil }
                Button(L("保存")) {
                    store.setTags(directory: directory, tagIDs: Array(draft))
                    store.tagEditorDirectory = nil
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.Space.s20)
        .frame(width: 360)
        .onAppear { draft = Set(SkillTags.load().links[directory] ?? []) }
    }
}

struct ProjectEditorSheet: View {
    @Environment(AppStore.self) private var store
    var directory: String
    @State private var draft: Set<String> = []

    var body: some View {
        let projects = ProjectSync.load().projects
        VStack(alignment: .leading, spacing: Theme.Space.s16) {
            Text(L("同步到项目"))
                .font(Theme.Fonts.panelTitle)
            Text(L("技能仍只在本库一份，勾上的项目会建软链。"))
                .font(Theme.Fonts.secondary)
                .foregroundStyle(Theme.textSecondary)
            if projects.isEmpty {
                Text(L("还没有项目。到「软件」里添加一个文件夹。"))
                    .font(Theme.Fonts.secondary)
                    .foregroundStyle(Theme.textTertiary)
            }
            ForEach(projects) { project in
                Toggle(isOn: Binding(
                    get: { draft.contains(project.id) },
                    set: { on in
                        if on { draft.insert(project.id) } else { draft.remove(project.id) }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(project.displayName).font(Theme.Fonts.callout)
                        Text(project.path)
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                    }
                }
                .toggleStyle(.checkbox)
            }
            HStack {
                Spacer()
                Button(L("取消")) { store.projectEditorDirectory = nil }
                Button(L("保存")) {
                    store.setProjects(directory: directory, projectIDs: Array(draft))
                    store.projectEditorDirectory = nil
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.Space.s20)
        .frame(width: 420)
        .onAppear { draft = Set(ProjectSync.load().targets[directory] ?? []) }
    }
}

struct BulkToolsSheet: View {
    @Environment(AppStore.self) private var store
    var skills: [Skill]
    @State private var platforms: Set<String> = []
    @State private var extra: Set<String> = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s16) {
            Text(LF("给 %d 个技能设定同步到哪些软件", skills.count))
                .font(Theme.Fonts.panelTitle)
            Text(L("勾上的会挂上，没勾的会从这些技能上摘下来。"))
                .font(Theme.Fonts.secondary)
                .foregroundStyle(Theme.textSecondary)
            ForEach(store.visiblePlatforms) { platform in
                Toggle(platform.displayName, isOn: Binding(
                    get: { platforms.contains(platform.rawValue) },
                    set: { on in
                        if on { platforms.insert(platform.rawValue) } else { platforms.remove(platform.rawValue) }
                    }
                ))
            }
            let tools = CustomTools.active()
            if !tools.isEmpty {
                Divider()
                ForEach(tools) { tool in
                    Toggle(tool.label, isOn: Binding(
                        get: { extra.contains(tool.id) },
                        set: { on in
                            if on { extra.insert(tool.id) } else { extra.remove(tool.id) }
                        }
                    ))
                }
            }
            HStack {
                Spacer()
                Button(L("取消")) { dismiss() }
                Button(L("应用")) {
                    store.applyTools(to: skills, platforms: platforms, extra: extra)
                    store.skillTable?.clearMultiSelection()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.Space.s20)
        .frame(width: 400)
        .onAppear {
            if let first = skills.first {
                platforms = Set(AgentPlatform.allCases.filter { first.mount($0).enabled }.map(\.rawValue))
                extra = Set(first.extraMounts.filter { $0.value.enabled }.map(\.key))
            }
        }
    }
}

struct SkillFileTree: View {
    var skill: Skill
    @State private var selected: String?
    @State private var preview: String?

    var body: some View {
        let nodes = SkillFiles.list(root: URL(fileURLWithPath: skill.sourcePath, isDirectory: true))
        VStack(alignment: .leading, spacing: Theme.Space.s8) {
            ForEach(nodes.filter { !$0.isDirectory }) { node in
                Button {
                    selected = node.relativePath
                    preview = SkillFiles.read(
                        root: URL(fileURLWithPath: skill.sourcePath, isDirectory: true),
                        relative: node.relativePath
                    )
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: node.isMarkdown ? "doc.richtext" : "doc")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textTertiary)
                        Text(node.relativePath)
                            .font(Theme.Fonts.mono)
                            .foregroundStyle(selected == node.relativePath ? Theme.accent : Theme.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)
            }
            if let preview {
                ScrollView {
                    Text(preview)
                        .font(Theme.Fonts.mono)
                        .foregroundStyle(Theme.textPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 120, maxHeight: 280)
                .padding(Theme.Space.s8)
                .quietControl(cornerRadius: Theme.Radius.tile)
            }
        }
    }
}

struct DiscoveryBanner: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let count = store.adoptableSkills.count
        if count > 0 {
            HStack(spacing: Theme.Space.s12) {
                Image(systemName: "tray.and.arrow.down")
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(LF("发现 %d 个还没收进本库的技能", count))
                        .font(Theme.Fonts.calloutEmphasis)
                    Text(L("可以收编，或到「软件」里改哪些目录参与扫描。"))
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer(minLength: 0)
                Button(L("先看看")) { store.jumpToLocalSkills() }
                    .buttonStyle(.plain)
                    .font(Theme.Fonts.secondaryEmphasis)
                    .foregroundStyle(Theme.accent)
            }
            .padding(Theme.Space.s12)
            .quietControl(cornerRadius: Theme.Radius.tile)
        }
    }
}

struct UpdateRunCard: View {
    var run: UpdateRun

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s8) {
            Text(L("最近一次检查"))
                .font(Theme.Fonts.secondaryEmphasis)
                .foregroundStyle(Theme.textSecondary)
            Text(LF("查了 %d 个，有新版本 %d，跳过 %d", run.checked, max(0, run.checked - run.skipped), run.skipped))
                .font(Theme.Fonts.callout)
            if run.updated > 0 {
                Text(LF("已更新 %d 个", run.updated))
                    .font(Theme.Fonts.secondary)
                    .foregroundStyle(Theme.textSecondary)
            }
            if !run.failures.isEmpty {
                ForEach(run.failures) { failure in
                    Text(failure.reason)
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.error)
                }
            }
            Text(Format.clock.string(from: Date(timeIntervalSince1970: TimeInterval(run.at))))
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.textTertiary)
        }
    }
}

struct ExtraToolsToggles: View {
    @Environment(AppStore.self) private var store
    var skill: Skill

    var body: some View {
        let tools = CustomTools.active()
        if !tools.isEmpty, skill.origin == .atlas, !skill.managed {
            VStack(alignment: .leading, spacing: Theme.Space.s8) {
                Text(L("更多软件"))
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textTertiary)
                ForEach(tools) { tool in
                    Toggle(tool.label, isOn: Binding(
                        get: { skill.extraMounts[tool.id]?.enabled == true },
                        set: { store.setExtraTool(skill, toolID: tool.id, enabled: $0) }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
            }
        }
    }
}
