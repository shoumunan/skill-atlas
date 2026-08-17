import SwiftUI

// MARK: - 首次启动 · CC Switch 迁移引导（sheet，宽 560）
//
// 与 InstallSheet / CleanupSheet 同一套骨架：图标章头部 + 发丝分隔 + 正文 + 底部动作。
// 讲清三件事：迁什么（N 个技能）、怎么迁（复制进库 + 软链出去）、能不能反悔（随时撤销）。

struct MigrationSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    private var plan: SkillMigrator.Plan { SkillMigrator.plan() }

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
        .interactiveDismissDisabled(true)
    }

    private var header: some View {
        HStack(spacing: Theme.Space.s12) {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 28, height: 28)
                .background {
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .fill(Theme.accent.opacity(0.12))
                }
            VStack(alignment: .leading, spacing: 1) {
                Text(L("把技能收到一起"))
                    .font(Theme.Fonts.panelTitle)
                    .foregroundStyle(Theme.textPrimary)
                Text(L("首次设置 · 原文件保留，随时可撤销"))
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer()
        }
        .padding(.horizontal, Theme.Space.s20)
        .padding(.vertical, Theme.Space.s16)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s16) {
            Text(LF("发现 CC Switch 里有 %lld 个技能。收进本库后，开关平台、更新、体检、瘦身都在这一个应用里完成。", plan.total))
                .font(Theme.Fonts.body)
                .lineSpacing(2)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            // 机制一张图：和设置页同一个组件，语言一致
            MigrationFlow()

            VStack(alignment: .leading, spacing: Theme.Space.s8 + 2) {
                promise(symbol: "doc.on.doc", text: "复制不搬家：CC Switch 的原文件一个不动，数据库只读。")
                promise(symbol: "link", text: "软链接管：各平台技能目录改指本库，Agent 立即可用。")
                promise(symbol: "arrow.uturn.backward", text: "随时可撤销：设置页一键把软链指回去，本库副本保留。")
            }
            .padding(Theme.Space.s12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .quietControl(cornerRadius: Theme.Radius.tile)

            if store.migrating {
                HStack(spacing: Theme.Space.s8) {
                    ProgressView().controlSize(.small)
                    Text(store.migrationStatus.isEmpty ? L("正在迁移…") : store.migrationStatus)
                        .font(Theme.Fonts.secondary)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }

            HStack {
                Button {
                    store.skipMigration()
                    dismiss()
                } label: {
                    Text(L("暂时跳过"))
                        .font(Theme.Fonts.calloutEmphasis)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, Theme.Space.s12)
                        .frame(height: 28)
                        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                }
                .buttonStyle(PressableButtonStyle())
                .quietControl()
                .keyboardShortcut(.cancelAction)
                .disabled(store.migrating)
                .help(L("以后可在设置页随时迁入"))
                Spacer()
                Button {
                    store.performMigration()
                } label: {
                    HStack(spacing: Theme.Space.s4) {
                        if store.migrating {
                            ProgressView().controlSize(.mini).tint(.white)
                        } else {
                            Image(systemName: "arrow.down.to.line")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        Text(store.migrating ? L("迁移中…") : LF("开始迁移（%d）", plan.total))
                            .font(Theme.Fonts.calloutEmphasis)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, Theme.Space.s16)
                    .frame(height: 28)
                    .contentShape(Capsule())
                }
                .buttonStyle(PressableButtonStyle())
                .accentGlass(Capsule(style: .continuous))
                .opacity(store.migrating ? 0.6 : 1)
                .disabled(store.migrating)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func promise(symbol: String, text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.s8 + 2) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 18, height: 18)
                .background {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Theme.accent.opacity(0.10))
                }
            Text(L(text))
                .font(Theme.Fonts.secondary)
                .lineSpacing(2)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
