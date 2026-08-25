import SwiftUI
import AppKit

// MARK: - 场景 Profile 界面（三期 G8）
//
// 两个 sheet：ProfileSheet（管理与成员勾选）与 ProfileApplySheet（写盘前的确认页）。
// 确认页是硬要求——这个功能会改用户自己的 ~/.claude/settings.json 与项目配置，
// 必须让人看清「写哪个文件、摘掉哪些技能、原文备份到哪」再决定。

struct ProfileSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID: String?
    @State private var draftName = ""
    @State private var search = ""

    private var selected: AtlasProfile? {
        store.profiles.profiles.first { $0.id == selectedID }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1)
            HStack(spacing: 0) {
                sidebar.frame(width: 240)
                Rectangle().fill(Color.primary.opacity(0.06)).frame(width: 1)
                detail.frame(maxWidth: .infinity)
            }
        }
        .frame(width: 820, height: 600)
        .background(.regularMaterial)
        .onAppear {
            store.loadProfiles()
            if selectedID == nil { selectedID = store.profiles.profiles.first?.id }
        }
    }

    private var header: some View {
        HStack(spacing: Theme.Space.s12) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 28, height: 28)
                .background {
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .fill(Theme.accent.opacity(0.12))
                }
            VStack(alignment: .leading, spacing: 1) {
                Text(L("场景"))
                    .font(Theme.Fonts.panelTitle)
                    .foregroundStyle(Theme.textPrimary)
                Text(L("只给当前工作留需要的技能。随时可撤。"))
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 28, height: 28)
                    .quietControl()
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, Theme.Space.s20)
        .padding(.vertical, Theme.Space.s16)
    }

    // MARK: 左：Profile 列表

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(store.profiles.profiles) { profile in
                        profileRow(profile)
                    }
                }
                .padding(Theme.Space.s8)
            }
            .panelScroll()
            Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1)
            HStack(spacing: Theme.Space.s8) {
                Button {
                    let profile = AtlasProfile.new(name: L("新场景"))
                    store.upsertProfile(profile)
                    selectedID = profile.id
                    draftName = profile.name
                } label: {
                    Label(L("新建"), systemImage: "plus")
                        .font(Theme.Fonts.calloutEmphasis)
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, Theme.Space.s8)
                        .frame(height: 26)
                        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                }
                .buttonStyle(PressableButtonStyle())
                .quietControl()
                if let selected {
                    Button(role: .destructive) {
                        store.deleteProfile(selected)
                        selectedID = store.profiles.profiles.first?.id
                    } label: {
                        Label(L("删除"), systemImage: "trash")
                            .font(Theme.Fonts.calloutEmphasis)
                            .foregroundStyle(Theme.error)
                            .padding(.horizontal, Theme.Space.s8)
                            .frame(height: 26)
                            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                    }
                    .buttonStyle(PressableButtonStyle())
                    .quietControl()
                    .help(L("删除前会先撤销它写过的所有配置"))
                }
                Spacer()
            }
            .padding(Theme.Space.s8)
        }
    }

    private func profileRow(_ profile: AtlasProfile) -> some View {
        let active = store.profiles.activeProfileID == profile.id
        return Button {
            selectedID = profile.id
            draftName = profile.name
        } label: {
            HStack(spacing: Theme.Space.s8) {
                Image(systemName: profile.symbol)
                    .font(.system(size: 11))
                    .foregroundStyle(active ? Theme.accent : Theme.textSecondary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(profile.name)
                        .font(Theme.Fonts.calloutEmphasis)
                        .foregroundStyle(Theme.textPrimary)
                    Text(LF("%d 个技能", profile.members.count))
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer()
                if active {
                    Text(L("默认"))
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, Theme.Space.s4 + 2)
                        .frame(height: 17)
                        .background(Capsule().fill(Theme.accent.opacity(0.12)))
                }
            }
            .padding(.horizontal, Theme.Space.s8)
            .frame(height: 40)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if selectedID == profile.id {
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .fill(Color.primary.opacity(0.07))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: 右：成员勾选与动作

    @ViewBuilder
    private var detail: some View {
        if let profile = selected {
            VStack(alignment: .leading, spacing: Theme.Space.s12) {
                nameRow(profile)
                exclusionRow(profile)
                memberPicker(profile)
                bindingsBlock(profile)
                actionRow(profile)
            }
            .padding(Theme.Space.s16)
        } else {
            VStack(spacing: Theme.Space.s8) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 24))
                    .foregroundStyle(Theme.textTertiary)
                Text(L("左边新建一个场景，勾选这个场景里要用的技能"))
                    .font(Theme.Fonts.secondary)
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func nameRow(_ profile: AtlasProfile) -> some View {
        HStack(spacing: Theme.Space.s8) {
            TextField(L("场景名"), text: $draftName)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 260)
                .onSubmit {
                    var copy = profile
                    copy.name = draftName.trimmingCharacters(in: .whitespaces)
                    if !copy.name.isEmpty { store.upsertProfile(copy) }
                }
            Text(LF("已选 %d / %d", profile.members.count, store.skills.filter { !$0.disabled }.count))
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.textTertiary)
            Spacer()
            Button {
                var copy = profile
                copy.members = store.skills.filter { !$0.disabled }.map(\.directory)
                store.upsertProfile(copy)
            } label: {
                Text(L("全选"))
                    .font(Theme.Fonts.caption)
                    .padding(.horizontal, Theme.Space.s8)
                    .frame(height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
            .quietControl()
            Button {
                var copy = profile
                copy.members = []
                store.upsertProfile(copy)
            } label: {
                Text(L("清空"))
                    .font(Theme.Fonts.caption)
                    .padding(.horizontal, Theme.Space.s8)
                    .frame(height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
            .quietControl()
        }
    }

    private func exclusionRow(_ profile: AtlasProfile) -> some View {
        HStack(spacing: Theme.Space.s8) {
            Text(L("没勾的技能："))
                .font(Theme.Fonts.secondary)
                .foregroundStyle(Theme.textSecondary)
            Picker("", selection: Binding(
                get: { profile.exclusion },
                set: { value in
                    var copy = profile
                    copy.exclusion = value
                    store.upsertProfile(copy)
                }
            )) {
                ForEach(ProfileExclusion.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 320)
            Spacer()
        }
    }

    private func memberPicker(_ profile: AtlasProfile) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s8) {
            TextField(L("筛选技能"), text: $search)
                .textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(filteredSkills) { skill in
                        memberRow(profile: profile, skill: skill)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .quietControl(cornerRadius: Theme.Radius.tile)
            .panelScroll()
        }
        .frame(maxHeight: .infinity)
    }

    private var filteredSkills: [Skill] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        let pool = store.skills.filter { !$0.disabled }
        guard !query.isEmpty else { return pool }
        return pool.filter {
            $0.name.lowercased().contains(query) || $0.description.lowercased().contains(query)
        }
    }

    private func memberRow(profile: AtlasProfile, skill: Skill) -> some View {
        let checked = profile.members.contains(skill.directory)
        return Button {
            var copy = profile
            if checked {
                copy.members.removeAll { $0 == skill.directory }
            } else {
                copy.members.append(skill.directory)
            }
            store.upsertProfile(copy)
        } label: {
            HStack(spacing: Theme.Space.s8) {
                Image(systemName: checked ? "checkmark.square.fill" : "square")
                    .font(.system(size: 12))
                    .foregroundStyle(checked ? Theme.accent : Theme.textTertiary)
                Text(skill.name)
                    .font(Theme.Fonts.secondary)
                    .foregroundStyle(Theme.textPrimary)
                Text(skill.category)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
            }
            .padding(.horizontal, Theme.Space.s8)
            .frame(height: 26)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func bindingsBlock(_ profile: AtlasProfile) -> some View {
        let bound = store.profiles.bindings.filter { $0.profileID == profile.id }
        if !bound.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.s4) {
                Text(L("已绑定目录"))
                    .font(Theme.Fonts.secondaryEmphasis)
                    .foregroundStyle(Theme.textPrimary)
                ForEach(bound) { binding in
                    HStack(spacing: Theme.Space.s8) {
                        Text(binding.directory.replacingOccurrences(of: AtlasPaths.home.path, with: "~"))
                            .font(Theme.Fonts.mono)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button(L("解除")) { store.unbindDirectory(binding) }
                            .buttonStyle(.plain)
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
            .padding(Theme.Space.s8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .quietControl(cornerRadius: Theme.Radius.control)
        }
    }

    private func actionRow(_ profile: AtlasProfile) -> some View {
        HStack(spacing: Theme.Space.s8) {
            Text(L("只对 Claude Code 生效；其他平台没有等价机制。"))
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.textTertiary)
            Spacer()
            if store.profiles.activeProfileID == profile.id {
                Button {
                    store.revertDefaultProfile()
                } label: {
                    Text(L("取消默认"))
                        .font(Theme.Fonts.calloutEmphasis)
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, Theme.Space.s12)
                        .frame(height: 28)
                        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                }
                .buttonStyle(PressableButtonStyle())
                .quietControl()
            }
            Button {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.allowsMultipleSelection = false
                panel.prompt = L("绑定")
                panel.message = L("选一个项目目录：在这个目录里开的会话按本场景加载技能")
                if panel.runModal() == .OK, let url = panel.url {
                    store.requestProfileApply(profile, directory: url)
                }
            } label: {
                Text(L("绑定到目录…"))
                    .font(Theme.Fonts.calloutEmphasis)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, Theme.Space.s12)
                    .frame(height: 28)
                    .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            }
            .buttonStyle(PressableButtonStyle())
            .quietControl()
            Button {
                store.requestProfileApply(profile, directory: nil)
            } label: {
                Text(L("设为默认…"))
                    .font(Theme.Fonts.calloutEmphasis)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Theme.Space.s16)
                    .frame(height: 28)
                    .contentShape(Capsule())
            }
            .buttonStyle(PressableButtonStyle())
            .accentGlass(Capsule(style: .continuous))
        }
    }
}

/// 写盘确认页：改用户配置前，把要做的事一条条摊开
struct ProfileApplySheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private var request: AppStore.ProfileApplyRequest? { store.profileRequest }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1)
            content.padding(Theme.Space.s20)
        }
        .frame(width: 620, height: 520)
        .background(.regularMaterial)
    }

    private var header: some View {
        HStack(spacing: Theme.Space.s12) {
            Image(systemName: "doc.badge.gearshape")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.warning)
                .frame(width: 28, height: 28)
                .background {
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .fill(Theme.warning.opacity(0.12))
                }
            VStack(alignment: .leading, spacing: 1) {
                Text(L("确认写入配置"))
                    .font(Theme.Fonts.panelTitle)
                    .foregroundStyle(Theme.textPrimary)
                Text(request?.plan.targetPath ?? "")
                    .font(Theme.Fonts.mono)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button {
                store.profileRequest = nil
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 28, height: 28)
                    .quietControl()
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, Theme.Space.s20)
        .padding(.vertical, Theme.Space.s16)
    }

    @ViewBuilder
    private var content: some View {
        if let request {
            VStack(alignment: .leading, spacing: Theme.Space.s12) {
                summaryBlock(request)
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.s8) {
                        listBlock(
                            title: LF("将摘出自动清单（%d）", request.plan.excluded.count),
                            names: request.plan.excluded, tint: Theme.warning
                        )
                        if !request.plan.conflicts.isEmpty {
                            listBlock(
                                title: LF("重名，无法单独处置，保持原样（%d）", request.plan.conflicts.count),
                                names: request.plan.conflicts, tint: Theme.error
                            )
                        }
                        if !request.plan.foreignKeys.isEmpty {
                            listBlock(
                                title: LF("你自己设过的覆盖，保持不动（%d）", request.plan.foreignKeys.count),
                                names: request.plan.foreignKeys, tint: Theme.textTertiary
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .panelScroll()
                footer
            }
        }
    }

    private func summaryBlock(_ request: AppStore.ProfileApplyRequest) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s4) {
            Label(
                request.directory == nil
                    ? LF("把「%@」设为默认场景：管所有没有单独绑定的会话。", request.profile.name)
                    : LF("把「%@」绑定到这个目录：只影响在该目录里开的会话。", request.profile.name),
                systemImage: "info.circle"
            )
            .font(Theme.Fonts.calloutEmphasis)
            .foregroundStyle(Theme.textPrimary)
            Text(LF("保留 %d 个技能；非成员写成「%@」。原文件会先备份到 ~/.skill-atlas/settings-backups/，随时可在这里撤销。",
                    request.plan.kept.count, request.plan.exclusion.title))
                .font(Theme.Fonts.secondary)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(Theme.Space.s8 + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .fill(Theme.accent.opacity(0.08))
        }
    }

    private func listBlock(title: String, names: [String], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Theme.Fonts.secondaryEmphasis)
                .foregroundStyle(tint)
            Text(names.joined(separator: "、"))
                .font(Theme.Fonts.secondary)
                .foregroundStyle(Theme.textSecondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Theme.Space.s8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .quietControl(cornerRadius: Theme.Radius.control)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button {
                store.confirmProfileApply()
                dismiss()
            } label: {
                HStack(spacing: Theme.Space.s4) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 11, weight: .semibold))
                    Text(L("备份并写入"))
                        .font(Theme.Fonts.calloutEmphasis)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, Theme.Space.s16)
                .frame(height: 28)
                .contentShape(Capsule())
            }
            .buttonStyle(PressableButtonStyle())
            .accentGlass(Capsule(style: .continuous))
            .keyboardShortcut(.defaultAction)
        }
    }
}
