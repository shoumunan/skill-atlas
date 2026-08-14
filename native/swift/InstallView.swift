import SwiftUI
import AppKit

// MARK: - 安装技能 sheet（宽 560）

struct InstallSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = InstallerModel()
    @FocusState private var urlFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 1)
            content
                .padding(Theme.Space.s20)
        }
        .frame(width: 560)
        .background(.regularMaterial)
        .onAppear {
            // 调试钩子：-atlasInstallURL <url> 预填并自动开始（验收截图用）
            if let preset = UserDefaults.standard.string(forKey: "atlasInstallURL"), model.urlText.isEmpty {
                model.urlText = preset
                if UserDefaults.standard.bool(forKey: "atlasInstallCodex") {
                    model.selectedPlatforms.insert(AgentPlatform.codex.rawValue)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { model.start() }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { urlFocused = true }
            }
        }
        .onChange(of: model.stage) { _, stage in
            // 调试钩子：-atlasInstallGo 1 检测完成后自动安装选中项（验收用）
            if stage == .selecting, UserDefaults.standard.bool(forKey: "atlasInstallGo") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { model.install(store: store) }
            }
        }
    }

    private var header: some View {
        HStack(spacing: Theme.Space.s12) {
            Image(systemName: "square.and.arrow.down.on.square")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 28, height: 28)
                .background {
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .fill(Theme.accent.opacity(0.12))
                }
            VStack(alignment: .leading, spacing: 1) {
                Text("安装技能")
                    .font(Theme.Fonts.panelTitle)
                    .foregroundStyle(Theme.textPrimary)
                Text("粘贴 GitHub 仓库链接，或选择本地文件夹，装入 Skill Atlas 技能库")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            Button {
                model.reset()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 28, height: 28)
                    .quietControl()
            }
            .buttonStyle(.plain)
            .keyboardShortcut("w", modifiers: .command)
            .help("关闭（⌘W / Esc）")
        }
        .padding(.horizontal, Theme.Space.s20)
        .padding(.vertical, Theme.Space.s16)
    }

    @ViewBuilder
    private var content: some View {
        switch model.stage {
        case .input:
            inputStage
        case .cloning, .detecting, .installing:
            progressStage
        case .selecting:
            selectingStage
        case .done:
            doneStage
        }
    }

    // MARK: 输入

    private var inputStage: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s12) {
            HStack(spacing: Theme.Space.s8) {
                Image(systemName: "link")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                TextField("https://github.com/<owner>/<repo>", text: $model.urlText)
                    .textFieldStyle(.plain)
                    .font(Theme.Fonts.mono)
                    .focused($urlFocused)
                    .onSubmit { if model.canStart { model.start() } }
            }
            .padding(.horizontal, Theme.Space.s12)
            .frame(height: 34)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                            .strokeBorder(
                                model.inlineError != nil ? Theme.error.opacity(0.6) : Color.primary.opacity(0.08),
                                lineWidth: 1
                            )
                    }
            }
            if let inlineError = model.inlineError {
                Text(inlineError)
                    .font(Theme.Fonts.secondary)
                    .foregroundStyle(Theme.error)
            }
            if let errorText = model.errorText {
                HStack(alignment: .top, spacing: Theme.Space.s8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.warning)
                    Text(errorText)
                        .font(Theme.Fonts.secondary)
                        .foregroundStyle(Theme.textSecondary)
                        .textSelection(.enabled)
                }
                .padding(Theme.Space.s12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .fill(Theme.warning.opacity(0.08))
                }
            }
            Text("支持 GitHub 仓库、/tree/<分支>/<子目录>，以及本机已有 SKILL.md 的文件夹。")
                .font(Theme.Fonts.secondary)
                .foregroundStyle(Theme.textTertiary)
            HStack {
                Button("选择本地文件夹…") {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = false
                    panel.message = L("选择包含 SKILL.md 的技能文件夹，或含多个技能子目录的文件夹")
                    if panel.runModal() == .OK, let url = panel.url {
                        model.urlText = url.path
                        model.start()
                    }
                }
                .buttonStyle(.link)
                Spacer()
                Button {
                    model.start()
                } label: {
                    Text("安装")
                        .font(Theme.Fonts.calloutEmphasis)
                        .foregroundStyle(.white)
                        .padding(.horizontal, Theme.Space.s16)
                        .frame(height: 28)
                        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                }
                .buttonStyle(PressableButtonStyle())
                .accentGlass(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                .opacity(model.canStart ? 1 : 0.4)
                .disabled(!model.canStart)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: 进度

    private var progressStage: some View {
        HStack(spacing: Theme.Space.s12) {
            ProgressView().controlSize(.small)
            Text(model.statusText)
                .font(Theme.Fonts.body)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
        }
        .padding(.vertical, Theme.Space.s24)
    }

    // MARK: 勾选

    private var selectingStage: some View {
        let selectable = model.candidates.filter { !$0.conflict }
        let selectedCount = model.candidates.filter { $0.selected && !$0.conflict }.count
        return VStack(alignment: .leading, spacing: Theme.Space.s12) {
            HStack {
                Text(model.candidates.count == 1
                    ? L("检测到 1 个技能")
                    : LF("检测到 %d 个技能，勾选要安装的", model.candidates.count))
                    .font(Theme.Fonts.calloutEmphasis)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if selectable.count > 1 {
                    Button(selectedCount == selectable.count ? L("全不选") : L("全选")) {
                        let turnOn = selectedCount != selectable.count
                        for index in model.candidates.indices where !model.candidates[index].conflict {
                            model.candidates[index].selected = turnOn
                        }
                    }
                    .buttonStyle(.link)
                    .font(Theme.Fonts.secondaryEmphasis)
                }
            }
            // sheet 高度由内容决定，ScrollView 没有外部约束会塌成零高——按条数给定高
            ScrollView {
                VStack(spacing: 2) {
                    ForEach($model.candidates) { $candidate in
                        CandidateRow(candidate: $candidate)
                    }
                }
            }
            .frame(height: min(CGFloat(model.candidates.count) * 44 + 4, 260))
            .panelScroll()
            HStack(spacing: Theme.Space.s8) {
                ForEach(store.visiblePlatforms) { platform in
                    let on = model.selectedPlatforms.contains(platform.rawValue)
                    Button {
                        if on { model.selectedPlatforms.remove(platform.rawValue) }
                        else { model.selectedPlatforms.insert(platform.rawValue) }
                    } label: {
                        HStack(spacing: Theme.Space.s4 + 1) {
                            PlatformLogo(platform: platform, size: 18, lit: on)
                            Text(platform.displayName)
                                .font(on ? Theme.Fonts.calloutEmphasis : Theme.Fonts.callout)
                                .foregroundStyle(on ? Theme.textPrimary : Theme.textTertiary)
                        }
                        .padding(.horizontal, Theme.Space.s8)
                        .frame(height: 28)
                        .background {
                            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                                .fill(on ? Theme.accent.opacity(0.10) : Color.primary.opacity(0.04))
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                                .strokeBorder(on ? Theme.accent.opacity(0.35) : Color.primary.opacity(0.08), lineWidth: 0.5)
                        }
                    }
                    .buttonStyle(.plain)
                    .help(on ? LF("安装后挂到 %@", platform.displayName) : LF("不挂 %@", platform.displayName))
                }
            }
            HStack {
                Text("装入本库，再按勾选平台建软链")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                Button {
                    model.install(store: store)
                } label: {
                    Text("安装选中（\(selectedCount)）")
                        .font(Theme.Fonts.calloutEmphasis)
                        .foregroundStyle(.white)
                        .padding(.horizontal, Theme.Space.s16)
                        .frame(height: 28)
                        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                }
                .buttonStyle(PressableButtonStyle())
                .accentGlass(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                .opacity(selectedCount > 0 ? 1 : 0.4)
                .disabled(selectedCount == 0)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: 结果

    private var doneStage: some View {
        let ok = model.results.filter(\.installed).count
        let skipped = model.results.count - ok
        return VStack(alignment: .leading, spacing: Theme.Space.s12) {
            HStack(spacing: Theme.Space.s8) {
                Image(systemName: ok > 0 ? "checkmark.circle.fill" : "info.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(ok > 0 ? Theme.healthy : Theme.warning)
                Text("成功 \(ok) · 跳过 \(skipped)")
                    .font(Theme.Fonts.calloutEmphasis)
                    .foregroundStyle(Theme.textPrimary)
            }
            VStack(spacing: 2) {
                ForEach(model.results) { result in
                    HStack(spacing: Theme.Space.s8) {
                        Image(systemName: result.installed ? "checkmark" : "minus")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(result.installed ? Theme.healthy : Theme.textTertiary)
                            .frame(width: 14)
                        Text(result.directory)
                            .font(Theme.Fonts.rowTitle)
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Text(result.note)
                            .font(Theme.Fonts.secondary)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .padding(.horizontal, Theme.Space.s8)
                    .frame(height: 26)
                }
            }
            HStack {
                Button("再装一个") { model.reset() }
                    .buttonStyle(.link)
                    .font(Theme.Fonts.secondaryEmphasis)
                Spacer()
                Button {
                    model.reset()
                    dismiss()
                } label: {
                    Text("完成")
                        .font(Theme.Fonts.calloutEmphasis)
                        .foregroundStyle(.white)
                        .padding(.horizontal, Theme.Space.s16)
                        .frame(height: 28)
                        .background {
                            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                                .fill(Theme.accent)
                        }
                        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                }
                .buttonStyle(PressableButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}

private struct CandidateRow: View {
    @Binding var candidate: InstallCandidate

    var body: some View {
        Button {
            guard !candidate.conflict else { return }
            candidate.selected.toggle()
        } label: {
            HStack(spacing: Theme.Space.s8) {
                Image(systemName: candidate.conflict
                    ? "exclamationmark.triangle"
                    : candidate.selected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 13))
                    .foregroundStyle(candidate.conflict
                        ? Theme.warning
                        : candidate.selected ? Theme.accent : Theme.textTertiary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(candidate.directory)
                        .font(Theme.Fonts.rowTitle)
                        .foregroundStyle(candidate.conflict ? Theme.textTertiary : Theme.textPrimary)
                    Text(candidate.conflict
                        ? L("本地已有同名目录，将跳过（不覆盖）")
                        : candidate.description.isEmpty ? L("（SKILL.md 未写描述）") : candidate.description)
                        .font(Theme.Fonts.secondary)
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, Theme.Space.s8)
            .padding(.vertical, 5)
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
