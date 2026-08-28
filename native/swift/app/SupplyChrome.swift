import SwiftUI
#if SWIFT_PACKAGE
import AtlasCore
#endif

/// v15：场景切换与账单的家在供给页（SupplyView）。库页只留只读账单数字，
/// 点击跳供给页；瘦身草案 sheet 与待审 chip 仍从这里提供。

/// 库页工具栏的只读账单入口（点击去供给页，不在库页展开任何供给操作）
struct LibraryBillLink: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let tokens = store.doctorReport.totalTokens
        let computing = !store.skills.isEmpty && store.doctorReport.entries.isEmpty
        let over = tokens > 10_000
        Button {
            store.nav = .supply
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "number")
                    .font(.system(size: 10, weight: .semibold))
                Text(computing ? L("计算中") : LF("%d tok", tokens))
                    .font(Theme.Fonts.caption)
                    .monospacedDigit()
            }
            .foregroundStyle(over ? Theme.warning : Theme.textSecondary)
            .padding(.horizontal, Theme.Space.s8)
            .frame(height: 22)
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(L("每个 Claude 会话开场读技能清单的估算 token。点击去供给页调整。"))
    }
}

struct SlimDraftSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var rows: [SlimRow] = []

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s12) {
            Text(L("瘦身草案"))
                .font(Theme.Fonts.calloutEmphasis)
            Text(L("按使用次数分档。完整挂载进自动清单；仅用户可调仍能 /名字 调用；不挂载会从清单拿掉。只对 Claude Code 生效。meta-skill 不会被排除。"))
                .font(Theme.Fonts.secondary)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.s8) {
                    ForEach($rows) { $row in
                        HStack(spacing: Theme.Space.s8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.name)
                                    .font(Theme.Fonts.rowTitle)
                                Text(LF("%d 次会话", row.sessions))
                                    .font(Theme.Fonts.caption)
                                    .foregroundStyle(Theme.textTertiary)
                            }
                            Spacer(minLength: 0)
                            Picker("", selection: $row.tier) {
                                ForEach(SlimTier.allCases, id: \.self) { tier in
                                    Text(tier.title).tag(tier)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 120)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .frame(maxHeight: 360)
            HStack {
                Button(L("取消")) { dismiss() }
                    .buttonStyle(PressableButtonStyle())
                    .quietControl()
                Spacer()
                Button(L("应用草案")) {
                    store.applySlimDraft(rows)
                    dismiss()
                }
                .buttonStyle(PressableButtonStyle())
                .accentGlass(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.Space.s16)
        .frame(width: 520, height: 520)
        .onAppear {
            rows = SlimPlanner.draft(
                skills: store.skills,
                usage: store.usage,
                favorites: store.favorites
            )
        }
    }
}
