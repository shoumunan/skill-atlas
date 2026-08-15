import SwiftUI
import AppKit

// MARK: - 注册表发现（三期 G6-lite）
//
// 只把仓库地址填进上面的输入框，装的动作仍走既有管线（含装前安全扫描与
// critical 强制审阅）。搜索词会发往第三方服务 skills.sh，所以默认折叠、可关。

private struct RegistryFinder: View {
    @Binding var urlText: String
    @State private var query = ""
    @State private var results: [RegistrySkill] = []
    @State private var searching = false
    @State private var expanded = false
    @State private var errorText: String?
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s8) {
            Button {
                expanded.toggle()
            } label: {
                HStack(spacing: Theme.Space.s4) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                    Text(L("不知道装什么？搜公开注册表"))
                        .font(Theme.Fonts.secondary)
                }
                .foregroundStyle(Theme.accent)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                HStack(spacing: Theme.Space.s8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                    TextField(L("按用途搜，如 pdf、excel、changelog"), text: $query)
                        .textFieldStyle(.plain)
                        .font(Theme.Fonts.secondary)
                        .onChange(of: query) { _, _ in scheduleSearch() }
                    if searching { ProgressView().controlSize(.mini) }
                }
                .padding(.horizontal, Theme.Space.s8)
                .frame(height: 28)
                .quietControl(cornerRadius: Theme.Radius.control)

                Text(L("搜索词会发往第三方服务 skills.sh。选中只是把仓库地址填进上面的输入框，装不装、装之前扫不扫，仍由你决定。"))
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                if let errorText {
                    Text(errorText)
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.warning)
                }

                if !results.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 1) {
                            ForEach(results) { skill in
                                resultRow(skill)
                            }
                        }
                    }
                    .frame(height: 150)
                    .quietControl(cornerRadius: Theme.Radius.control)
                }
            }
        }
    }

    private func resultRow(_ skill: RegistrySkill) -> some View {
        Button {
            guard skill.isGitHubBacked else { return }
            urlText = skill.repoURL
        } label: {
            HStack(spacing: Theme.Space.s8) {
                Text(skill.name)
                    .font(Theme.Fonts.secondaryEmphasis)
                    .foregroundStyle(skill.isGitHubBacked ? Theme.textPrimary : Theme.textTertiary)
                Text(skill.source)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if skill.isGitHubBacked {
                    Text(LF("%d 次安装", skill.installs))
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.textTertiary)
                        .monospacedDigit()
                } else {
                    Text(L("外部来源，装不了"))
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.warning)
                }
            }
            .padding(.horizontal, Theme.Space.s8)
            .frame(height: 26)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!skill.isGitHubBacked)
        .help(skill.isGitHubBacked
              ? LF("填入 %@，再按「安装」走正常流程（含装前安全扫描）", skill.repoURL)
              : L("这条来自 GitHub 之外的来源，本应用只装 GitHub 仓库"))
    }

    /// 400ms 防抖：每敲一个字都发请求既慢又不礼貌
    private func scheduleSearch() {
        searchTask?.cancel()
        let current = query
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            guard current.trimmingCharacters(in: .whitespaces).count >= 2 else {
                results = []
                return
            }
            searching = true
            errorText = nil
            do {
                let found = try await SkillRegistry.search(current)
                guard !Task.isCancelled else { return }
                results = Array(found.prefix(20))
                if results.isEmpty { errorText = L("没搜到，换个词试试。") }
            } catch {
                guard !Task.isCancelled else { return }
                results = []
                errorText = error.localizedDescription
            }
            searching = false
        }
    }
}

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
        // ESC 关窗只 dismiss，走不到右上角 ✕ 的 reset()——临时克隆目录会留在 /var/folders。
        // 被审阅页的 critical 吓退而按 ESC 的用户，正是最不该在盘上留一份完整仓库副本的人。
        .onDisappear { model.reset() }
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
                Text(L("安装技能"))
                    .font(Theme.Fonts.panelTitle)
                    .foregroundStyle(Theme.textPrimary)
                Text(L("粘贴 GitHub 仓库链接，或选择本地文件夹，装入 Skill Atlas 技能库"))
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
            .help(L("关闭（⌘W / Esc）"))
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
        case .reviewing:
            reviewingStage
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
            Text(L("支持 GitHub 仓库、/tree/<分支>/<子目录>，以及本机已有 SKILL.md 的文件夹。"))
                .font(Theme.Fonts.secondary)
                .foregroundStyle(Theme.textTertiary)
            if SkillRegistry.enabled {
                RegistryFinder(urlText: $model.urlText)
            }
            Text(L("已经装在 ~/.claude/skills 等平台目录里的技能不用重装：它们会出现在技能库列表，选中后在「管理」区一键收进本库接管。"))
                .font(Theme.Fonts.secondary)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(L("选择本地文件夹…")) {
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
                    Text(L("安装"))
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
                Text(L("装入本库，再按勾选平台建软链"))
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                Button {
                    model.install(store: store)
                } label: {
                    Text(LF("安装选中（%lld）", selectedCount))
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

    // MARK: 安全审阅（关键级发现强制过闸）

    private var reviewingStage: some View {
        let flagged = model.candidates.filter { $0.selected && !$0.conflict && !$0.findings.isEmpty }
        return VStack(alignment: .leading, spacing: Theme.Space.s12) {
            HStack(spacing: Theme.Space.s8) {
                Image(systemName: "exclamationmark.octagon.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.error)
                Text("静态扫描发现可疑内容，请逐条核对原文")
                    .font(Theme.Fonts.calloutEmphasis)
                    .foregroundStyle(Theme.textPrimary)
            }
            Text("公开市场约 1/4 技能有安全缺陷。以下是命中行原文：确认来源可信再放行，或返回取消勾选。")
                .font(Theme.Fonts.secondary)
                .lineSpacing(2)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.s12) {
                    ForEach(flagged) { candidate in
                        VStack(alignment: .leading, spacing: Theme.Space.s4 + 2) {
                            Text(candidate.directory)
                                .font(Theme.Fonts.rowTitle)
                                .foregroundStyle(Theme.textPrimary)
                            ForEach(candidate.findings.filter { $0.severity != .info }) { finding in
                                FindingRow(finding: finding)
                            }
                        }
                        .padding(Theme.Space.s12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .quietControl(cornerRadius: Theme.Radius.tile)
                    }
                }
            }
            .frame(maxHeight: 320)
            .panelScroll()
            HStack {
                Button {
                    model.backToSelection()
                } label: {
                    Text("返回选择")
                        .font(Theme.Fonts.calloutEmphasis)
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, Theme.Space.s12)
                        .frame(height: 28)
                        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                }
                .buttonStyle(PressableButtonStyle())
                .quietControl()
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button(role: .destructive) {
                    model.confirmReviewAndInstall(store: store)
                } label: {
                    Text("已核对来源，仍要安装")
                        .font(Theme.Fonts.calloutEmphasis)
                }
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
                Text(LF("成功 %lld · 跳过 %lld", ok, skipped))
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
                Button(L("再装一个")) { model.reset() }
                    .buttonStyle(.link)
                    .font(Theme.Fonts.secondaryEmphasis)
                Spacer()
                Button {
                    model.reset()
                    dismiss()
                } label: {
                    Text(L("完成"))
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
                // 装前安全扫描徽标（红=关键级会拦截，橙=警告）
                if candidate.criticalCount > 0 {
                    Text(LF("%lld 处可疑", candidate.criticalCount))
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.error)
                        .padding(.horizontal, Theme.Space.s8)
                        .frame(height: 18)
                        .quietControl(tint: Theme.error)
                        .help(L("含关键级安全发现，安装前会强制进入审阅页"))
                } else if candidate.warningCount > 0 {
                    Text(LF("%lld 处提示", candidate.warningCount))
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.warning)
                        .padding(.horizontal, Theme.Space.s8)
                        .frame(height: 18)
                        .quietControl(tint: Theme.warning)
                        .help(L("含警告级安全发现，详见审阅页"))
                }
            }
            .padding(.horizontal, Theme.Space.s8)
            .padding(.vertical, 5)
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}


/// 安全发现行：严重度图标 + 规则 + 位置 + 命中行原文（mono）
struct FindingRow: View {
    var finding: SecurityFinding

    private var tint: Color {
        switch finding.severity {
        case .critical: return Theme.error
        case .warning: return Theme.warning
        case .info: return Theme.accent
        }
    }

    private var symbol: String {
        switch finding.severity {
        case .critical: return "exclamationmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: Theme.Space.s4 + 2) {
                Image(systemName: symbol)
                    .font(.system(size: 10))
                    .foregroundStyle(tint)
                Text(L(finding.rule))
                    .font(Theme.Fonts.secondaryEmphasis)
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: Theme.Space.s4)
                Text(finding.line > 0 ? "\(finding.file):\(finding.line)" : finding.file)
                    .font(Theme.Fonts.mono)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if !finding.excerpt.isEmpty {
                Text(finding.excerpt)
                    .font(Theme.Fonts.mono)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
                    .padding(Theme.Space.s4 + 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(tint.opacity(0.06))
                    }
            }
        }
    }
}
