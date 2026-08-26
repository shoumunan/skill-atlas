import SwiftUI
#if SWIFT_PACKAGE
import AtlasCore
#endif

// MARK: - 描述开药 sheet（三期 G2）
//
// 原先住在检查页里。检查页撤掉后，设置 → 维护仍会 `requestPrescription`，
// RootView 的 sheet 入口不能跟着消失。

struct PrescriptionSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var copiedPrompt = false
    @State private var probe = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 1)
            if let rx = store.prescription {
                ScrollView {
                    content(rx)
                        .padding(Theme.Space.s20)
                }
                .frame(maxHeight: 560)
                .panelScroll()
            }
        }
        .frame(width: 560)
        .background(.regularMaterial)
    }

    private var header: some View {
        HStack(spacing: Theme.Space.s12) {
            Image(systemName: "text.badge.checkmark")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 28, height: 28)
                .background {
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .fill(Theme.accent.opacity(0.12))
                }
            VStack(alignment: .leading, spacing: 1) {
                Text(L("调整介绍"))
                    .font(Theme.Fonts.panelTitle)
                    .foregroundStyle(Theme.textPrimary)
                Text(store.prescription.map { LF("针对 %@", $0.skill.name) } ?? "")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                store.prescription = nil
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
    private func content(_ rx: DescriptionPrescription) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s16) {
            VStack(alignment: .leading, spacing: Theme.Space.s8) {
                ForEach(rx.moves, id: \.self) { move in
                    Text(move)
                        .font(Theme.Fonts.callout)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if rx.noop {
                Text(L("机器没有改字。把下面的指令贴给 AI，再把结果写回 SKILL.md。"))
                    .font(Theme.Fonts.secondary)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                comparison(rx)
            }

            if !rx.beforeBuried.isEmpty || !rx.afterBuried.isEmpty {
                Text(LF("前 250 字里看不见的触发词：%d → %d", rx.beforeBuried.count, rx.afterBuried.count))
                    .font(Theme.Fonts.secondary)
                    .foregroundStyle(Theme.textTertiary)
            }

            probeRow(rx)

            HStack(spacing: Theme.Space.s12) {
                copyPromptButton(rx)
                if !rx.noop, rx.skill.origin != .ccSwitch {
                    Button {
                        store.adoptPrescription()
                    } label: {
                        HStack(spacing: Theme.Space.s4) {
                            Image(systemName: "square.and.pencil")
                                .font(.system(size: 11, weight: .semibold))
                            Text(L("写回 SKILL.md"))
                                .font(Theme.Fonts.calloutEmphasis)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, Theme.Space.s16)
                        .frame(height: 32)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(PressableButtonStyle())
                    .accentGlass(Capsule(style: .continuous))
                    .help(L("只改 description 这一键，不增删其他内容"))
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func comparison(_ rx: DescriptionPrescription) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s12) {
            block(title: L("现在"), text: rx.original)
            block(title: L("建议"), text: rx.rewritten)
        }
    }

    private func block(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s8) {
            HStack {
                Text(title)
                    .font(Theme.Fonts.secondaryEmphasis)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                CopyIconButton(text: text, help: L("复制"))
            }
            Text(text)
                .font(Theme.Fonts.callout)
                .foregroundStyle(Theme.textPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(Theme.Space.s12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .quietControl(cornerRadius: Theme.Radius.tile)
        }
    }

    private func probeRow(_ rx: DescriptionPrescription) -> some View {
        let ranks = probe.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil
            : store.rxRankComparison(phrase: probe)
        return VStack(alignment: .leading, spacing: Theme.Space.s8) {
            Text(L("用一句话看看名次变没有"))
                .font(Theme.Fonts.secondaryEmphasis)
                .foregroundStyle(Theme.textSecondary)
            HStack(spacing: Theme.Space.s8) {
                TextField(L("例如：整理这周的会议记录"), text: $probe)
                    .textFieldStyle(.plain)
                    .font(Theme.Fonts.callout)
            }
            .padding(.horizontal, Theme.Space.s12)
            .frame(height: 32)
            .quietControl(cornerRadius: Theme.Radius.control)
            if let ranks {
                Text(rankLine(rx.skill.name, before: ranks.before, after: ranks.after))
                    .font(Theme.Fonts.secondary)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func rankLine(_ name: String, before: Int?, after: Int?) -> String {
        let left = before.map { LF("现在第 %d", $0) } ?? L("现在未进前 8")
        let right = after.map { LF("改后第 %d", $0) } ?? L("改后未进前 8")
        return LF("%@：%@ → %@", name, left, right)
    }

    private func copyPromptButton(_ rx: DescriptionPrescription) -> some View {
        Button {
            store.copyToPasteboard(DescriptionRx.rewritePrompt(skill: rx.skill))
            withAnimation(reduceMotion ? nil : Motion.control) { copiedPrompt = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                withAnimation(reduceMotion ? nil : Motion.control) { copiedPrompt = false }
            }
        } label: {
            HStack(spacing: Theme.Space.s4) {
                Image(systemName: copiedPrompt ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                Text(copiedPrompt ? L("已复制改写指令") : L("复制改写指令"))
                    .font(Theme.Fonts.calloutEmphasis)
            }
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, Theme.Space.s16)
            .frame(height: 32)
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .quietControl()
        .help(L("贴进任意 AI，把重写后的介绍再写回文件"))
    }
}
