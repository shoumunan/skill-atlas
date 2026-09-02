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
            store.nav = .updates
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
        .help(L("每次跟 Claude 说话，它先读一遍所有技能的简介。这是那份简介的长度，点击去「更新」调。"))
    }
}

struct SlimDraftSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var rows: [SlimRow] = []

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s12) {
            Text(L("挑出不用的技能"))
                .font(Theme.Fonts.calloutEmphasis)
            Text(L("按你用过多少次排的。「自动」是 Claude 会自己想到用；「点名才用」是你打 /名字 才用，不占开场篇幅；「关掉」是完全不用。只对 Claude Code 生效——只有它有「装着、但不进开场清单」这个开关。"))
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
