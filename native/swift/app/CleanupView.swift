import SwiftUI
#if SWIFT_PACKAGE
import AtlasCore
#endif

// MARK: - 清理 CC Switch 副本向导（sheet，宽 560）
//
// 三段式：检查（后台校验每个副本）→ 报告 + 不可逆警告 → 结果。
// 只动 ~/.cc-switch/skills 里校验通过的目录（移入废纸篓）；数据库永远不碰。

struct CleanupSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private enum Stage {
        case checking
        case report
        case working
        case done(Int)
    }

    @State private var stage = Stage.checking
    @State private var items: [SkillMigrator.CleanupItem] = []
    @State private var failuresExpanded = false
    @State private var errorText: String?

    private var passed: [SkillMigrator.CleanupItem] { items.filter(\.ok) }
    private var failed: [SkillMigrator.CleanupItem] { items.filter { !$0.ok } }

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
        .task { await runCheck() }
    }

    private var header: some View {
        HStack(spacing: Theme.Space.s12) {
            Image(systemName: "trash")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.warning)
                .frame(width: 28, height: 28)
                .background {
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .fill(Theme.warning.opacity(0.12))
                }
            VStack(alignment: .leading, spacing: 1) {
                Text(L("清理 CC Switch 副本"))
                    .font(Theme.Fonts.panelTitle)
                    .foregroundStyle(Theme.textPrimary)
                Text(L("先逐个校验迁移结果，再把原目录移入废纸篓；cc-switch.db 不动"))
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
            .keyboardShortcut("w", modifiers: .command)
            .help(L("关闭（⌘W / Esc）"))
        }
        .padding(.horizontal, Theme.Space.s20)
        .padding(.vertical, Theme.Space.s16)
    }

    @ViewBuilder
    private var content: some View {
        switch stage {
        case .checking:
            HStack(spacing: Theme.Space.s12) {
                ProgressView().controlSize(.small)
                Text(L("正在校验每个已迁入技能：库内文件、平台挂载指向…"))
                    .font(Theme.Fonts.body)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
            }
            .padding(.vertical, Theme.Space.s24)
        case .report:
            reportStage
        case .working:
            HStack(spacing: Theme.Space.s12) {
                ProgressView().controlSize(.small)
                Text(L("正在移入废纸篓…"))
                    .font(Theme.Fonts.body)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
            }
            .padding(.vertical, Theme.Space.s24)
        case .done(let count):
            doneStage(count: count)
        }
    }

    // MARK: 报告 + 警告

    private var reportStage: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s12) {
            if passed.isEmpty {
                HStack(spacing: Theme.Space.s8) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.accent)
                    Text(items.isEmpty
                        ? L("CC Switch 源目录里没有发现技能副本，不需要清理。")
                        : L("没有校验通过的副本可清理。"))
                        .font(Theme.Fonts.body)
                        .foregroundStyle(Theme.textPrimary)
                }
            } else {
                HStack(spacing: Theme.Space.s8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.healthy)
                    Text(LF("%lld 个技能校验通过：已在本库、SKILL.md 可读、挂载全部指向本库。", passed.count))
                        .font(Theme.Fonts.body)
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text(LF("可回收 %@", Format.bytes(passed.reduce(0) { $0 + $1.sizeBytes })))
                        .font(Theme.Fonts.calloutEmphasis)
                        .monospacedDigit()
                        .foregroundStyle(Theme.healthy)
                }
            }

            if !failed.isEmpty {
                DisclosureGroup(isExpanded: $failuresExpanded) {
                    VStack(spacing: 2) {
                        ForEach(failed) { item in
                            HStack(spacing: Theme.Space.s8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Theme.warning)
                                    .frame(width: 14)
                                Text(item.directory)
                                    .font(Theme.Fonts.rowTitle)
                                    .foregroundStyle(Theme.textPrimary)
                                Spacer()
                                Text(item.reason)
                                    .font(Theme.Fonts.secondary)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            .padding(.horizontal, Theme.Space.s8)
                            .frame(height: 24)
                        }
                    }
                    .padding(.top, Theme.Space.s4)
                } label: {
                    Text(LF("%lld 个未通过校验，将原样保留（不会动它们）", failed.count))
                        .font(Theme.Fonts.secondaryEmphasis)
                        .foregroundStyle(Theme.textSecondary)
                }
                .tint(Theme.textTertiary)
            }

            if !passed.isEmpty {
                // 不可逆警告：把后果一条条说清，不含糊
                VStack(alignment: .leading, spacing: Theme.Space.s8) {
                    HStack(spacing: Theme.Space.s8) {
                        Image(systemName: "exclamationmark.octagon.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.error)
                        Text(L("这一步不可逆，请看清后果"))
                            .font(Theme.Fonts.calloutEmphasis)
                            .foregroundStyle(Theme.error)
                    }
                    Text(LF("· %lld 个原目录将从 ~/.cc-switch/skills 移入废纸篓，清空废纸篓后无法恢复\n· 清理后「撤销迁移」失效，回滚目标已不存在，技能从此只由本应用管理\n· CC Switch 应用里这些技能会显示为缺失（它的数据库不受影响）\n· 磁盘空间在清空废纸篓后才真正释放", passed.count))
                        .font(Theme.Fonts.secondary)
                        .lineSpacing(3)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Theme.Space.s12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                        .fill(Theme.error.opacity(0.07))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                        .strokeBorder(Theme.error.opacity(0.18), lineWidth: 0.5)
                }
            }

            if let errorText {
                Text(errorText)
                    .font(Theme.Fonts.secondary)
                    .foregroundStyle(Theme.error)
            }

            HStack {
                Button(L("取消")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if !passed.isEmpty {
                    Button(role: .destructive) {
                        runCleanup()
                    } label: {
                        Text(LF("移入废纸篓（%lld）", passed.count))
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    private func doneStage(count: Int) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s12) {
            HStack(spacing: Theme.Space.s8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.healthy)
                Text(LF("已把 %lld 个副本移入废纸篓", count))
                    .font(Theme.Fonts.calloutEmphasis)
                    .foregroundStyle(Theme.textPrimary)
            }
            Text(L("确认一切正常后，清空废纸篓即可释放空间。技能现在只由 Skill Atlas 库提供。"))
                .font(Theme.Fonts.secondary)
                .foregroundStyle(Theme.textSecondary)
            if let errorText {
                Text(errorText)
                    .font(Theme.Fonts.secondary)
                    .foregroundStyle(Theme.error)
            }
            HStack {
                Spacer()
                Button(L("完成")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: 动作

    private func runCheck() async {
        let result = await Task.detached(priority: .userInitiated) {
            SkillMigrator.cleanupCandidates()
        }.value
        items = result
        stage = .report
    }

    @MainActor
    private func runCleanup() {
        stage = .working
        store.pauseWatching()
        let targets = passed.map(\.directory)
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result { try SkillMigrator.cleanup(targets) }
            }.value
            store.resumeWatching()
            switch result {
            case .success(let count):
                stage = .done(count)
            case .failure(let error):
                errorText = error.localizedDescription
                // 部分成功也进入完成态（错误信息里已带成功数）
                stage = .done(0)
            }
            await store.rescan(keepSelection: true)
        }
    }
}

extension Format {
    /// 字节数 → 人话（MB/GB）
    static func bytes(_ value: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: value)
    }
}
