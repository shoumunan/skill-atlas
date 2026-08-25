import AppKit
import SwiftUI

// MARK: - 应用自更新 sheet
//
// 替换系统 NSAlert / 浮动进度条：和安装、清理同一套骨架
// （图标章头部 + 发丝 + quiet / accentGlass 按钮 + regularMaterial）。
// 更新说明按「含 v…」切开，当前版用正文，更早版本降为次级，避免一整块说明书。

struct AppUpdateSession: Identifiable, Equatable {
    let id: UUID
    var stage: Stage
    var feed: Appcast?
    var current: String
    var message: String

    enum Stage: Equatable {
        case available, upToDate, failed, unconfigured, installing, installFailed
    }
}

struct AppUpdateSheet: View {
    @ObservedObject private var updates = UpdateChecker.shared
    @ObservedObject private var updater = SelfUpdater.shared
    @Environment(\.dismiss) private var dismiss

    private var session: AppUpdateSession? { updates.session }
    private var installing: Bool { session?.stage == .installing }

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
        .interactiveDismissDisabled(installing)
    }

    private var header: some View {
        HStack(spacing: Theme.Space.s12) {
            Image(systemName: headerSymbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(headerTint)
                .frame(width: 28, height: 28)
                .background {
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .fill(headerTint.opacity(0.12))
                }
            VStack(alignment: .leading, spacing: 1) {
                Text(headerTitle)
                    .font(Theme.Fonts.panelTitle)
                    .foregroundStyle(Theme.textPrimary)
                Text(headerSubtitle)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            if !installing {
                Button {
                    updates.dismissSession()
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
        }
        .padding(.horizontal, Theme.Space.s20)
        .padding(.vertical, Theme.Space.s16)
    }

    @ViewBuilder
    private var content: some View {
        switch session?.stage {
        case .available:
            availableStage
        case .upToDate:
            messageStage(body: LF("当前版本 %@。", session?.current ?? UpdateChecker.currentVersion))
        case .failed:
            messageStage(body: failedBody)
        case .unconfigured:
            messageStage(body: LF("当前版本 %@。用「构建原生应用.command」重新构建即为最新。\n如需自动更新：把 appcast.json 托管到任意可访问地址后，在终端执行\ndefaults write local.skill-atlas.dashboard atlasAppcastURL \"<地址>\"", session?.current ?? UpdateChecker.currentVersion))
        case .installing:
            installingStage
        case .installFailed:
            failedInstallStage
        case nil:
            EmptyView()
        }
    }

    private var availableStage: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s16) {
            let sections = AppcastNotes.sections(from: session?.feed?.notes ?? "", current: session?.feed?.version ?? "")
            if sections.isEmpty {
                Text(LF("当前版本 %@。", UpdateChecker.currentVersion))
                    .font(Theme.Fonts.callout)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                VStack(alignment: .leading, spacing: Theme.Space.s12) {
                    if let current = sections.first {
                        Text(current.body)
                            .font(Theme.Fonts.callout)
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if sections.count > 1 {
                        VStack(alignment: .leading, spacing: Theme.Space.s8) {
                            ForEach(sections.dropFirst()) { section in
                                VStack(alignment: .leading, spacing: 2) {
                                    if !section.title.isEmpty {
                                        Text(section.title)
                                            .font(Theme.Fonts.caption)
                                            .foregroundStyle(Theme.textTertiary)
                                    }
                                    Text(section.body)
                                        .font(Theme.Fonts.secondary)
                                        .foregroundStyle(Theme.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 280, alignment: .top)
            }
            Text(L("「自动更新」会下载、校验并原地换装，然后自动重启。"))
                .font(Theme.Fonts.secondary)
                .foregroundStyle(Theme.textTertiary)
            HStack(spacing: Theme.Space.s8) {
                if let feed = session?.feed {
                    Button(L("打开下载页")) { UpdateChecker.openDownload(feed) }
                        .buttonStyle(.plain)
                        .font(Theme.Fonts.callout)
                        .foregroundStyle(Theme.accent)
                }
                Spacer()
                quietButton(L("稍后")) {
                    updates.dismissSession()
                    dismiss()
                }
                Button {
                    if let feed = session?.feed {
                        SelfUpdater.shared.install(feed)
                    }
                } label: {
                    Text(L("自动更新"))
                        .font(Theme.Fonts.calloutEmphasis)
                        .foregroundStyle(.white)
                        .padding(.horizontal, Theme.Space.s16)
                        .frame(height: 28)
                        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                }
                .buttonStyle(PressableButtonStyle())
                .accentGlass(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var installingStage: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s12) {
            Text(updater.statusText.isEmpty ? L("准备中…") : updater.statusText)
                .font(Theme.Fonts.callout)
                .foregroundStyle(Theme.textPrimary)
            ProgressView(value: updater.progress)
                .progressViewStyle(.linear)
            Text(L("「自动更新」会下载、校验并原地换装，然后自动重启。"))
                .font(Theme.Fonts.secondary)
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private var failedInstallStage: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s16) {
            Text(session?.message ?? "")
                .font(Theme.Fonts.callout)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(L("可以改用手动方式：打开下载页下载 DMG 覆盖安装。"))
                .font(Theme.Fonts.secondary)
                .foregroundStyle(Theme.textTertiary)
            HStack(spacing: Theme.Space.s8) {
                Spacer()
                quietButton(L("稍后")) {
                    updates.dismissSession()
                    dismiss()
                }
                if let feed = session?.feed {
                    Button {
                        UpdateChecker.openDownload(feed)
                    } label: {
                        Text(L("打开下载页"))
                            .font(Theme.Fonts.calloutEmphasis)
                            .foregroundStyle(.white)
                            .padding(.horizontal, Theme.Space.s16)
                            .frame(height: 28)
                            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                    }
                    .buttonStyle(PressableButtonStyle())
                    .accentGlass(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    private func messageStage(body: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s16) {
            Text(body)
                .font(Theme.Fonts.callout)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button {
                    updates.dismissSession()
                    dismiss()
                } label: {
                    Text(L("好"))
                        .font(Theme.Fonts.calloutEmphasis)
                        .foregroundStyle(.white)
                        .padding(.horizontal, Theme.Space.s16)
                        .frame(height: 28)
                        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                }
                .buttonStyle(PressableButtonStyle())
                .accentGlass(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func quietButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Fonts.calloutEmphasis)
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, Theme.Space.s12)
                .frame(height: 28)
                .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .quietControl()
    }

    private var headerSymbol: String {
        switch session?.stage {
        case .available, .installing: return "arrow.down.app"
        case .upToDate: return "checkmark.circle"
        case .failed, .installFailed: return "exclamationmark.triangle"
        case .unconfigured: return "wrench.and.screwdriver"
        case nil: return "arrow.down.app"
        }
    }

    private var headerTint: Color {
        switch session?.stage {
        case .failed, .installFailed: return Theme.warning
        case .upToDate: return Theme.healthy
        default: return Theme.accent
        }
    }

    private var headerTitle: String {
        switch session?.stage {
        case .available: return LF("发现新版本 %@", session?.feed?.version ?? "")
        case .upToDate: return L("已是最新版本")
        case .failed: return L("暂时无法检查更新")
        case .unconfigured: return L("本地构建版本，未配置更新源")
        case .installing: return LF("更新到 %@", session?.feed?.version ?? "")
        case .installFailed: return L("自动更新未完成")
        case nil: return L("检查更新…")
        }
    }

    private var headerSubtitle: String {
        switch session?.stage {
        case .available: return LF("当前版本 %@", UpdateChecker.currentVersion)
        case .installing: return L("「自动更新」会下载、校验并原地换装，然后自动重启。")
        case .installFailed: return L("可以改用手动方式：打开下载页下载 DMG 覆盖安装。")
        default: return LF("当前版本 %@", session?.current ?? UpdateChecker.currentVersion)
        }
    }

    private var failedBody: String {
        let reason = session?.message ?? ""
        if reason.contains("404") {
            return L("更新源仓库还没有 appcast.json：把项目根目录的 appcast.json 推到 github.com/shoumunan/skill-atlas 主分支即可生效。")
        }
        return LF("请检查网络后重试。（%@）", reason)
    }
}

enum AppcastNotes {
    struct Section: Identifiable {
        var id: String { title + body }
        var title: String
        var body: String
    }

    static func sections(from notes: String, current: String) -> [Section] {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let parts = trimmed
            .replacingOccurrences(of: "。含 ", with: "\u{1e}")
            .replacingOccurrences(of: "含 ", with: "\u{1e}")
            .split(separator: "\u{1e}", omittingEmptySubsequences: true)
            .map(String.init)
        return parts.enumerated().map { index, part in
            let pieces = part.split(separator: "：", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            if pieces.count == 2, !pieces[0].isEmpty, pieces[0].count < 24 {
                return Section(title: pieces[0], body: pieces[1])
            }
            return Section(title: index == 0 ? "v\(current)" : "", body: part)
        }
    }
}
