import SwiftUI
#if SWIFT_PACKAGE
import AtlasCore
#endif

/// CLI 关键级命中后由 skillatlas://review/<token> 唤起。批准只写 approvals.json，
/// 真正安装仍由 agent 重跑 atlas install（内容寻址，commit 变了旧批准失效）。
struct PendingReviewSheet: View {
    var token: String
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private var review: PendingReview? { PendingReviews.load(token) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s12) {
            HStack(spacing: Theme.Space.s8) {
                Image(systemName: "exclamationmark.octagon.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.error)
                Text(L("来自会话的安装审阅"))
                    .font(Theme.Fonts.calloutEmphasis)
                    .foregroundStyle(Theme.textPrimary)
            }
            if let review {
                Text(review.source.url)
                    .font(Theme.Fonts.secondary)
                    .foregroundStyle(Theme.textSecondary)
                    .textSelection(.enabled)
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.s12) {
                        ForEach(review.findings, id: \.file) { finding in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(finding.directory)
                                    .font(Theme.Fonts.rowTitle)
                                Text(finding.rule)
                                    .font(Theme.Fonts.secondary)
                                    .foregroundStyle(Theme.error)
                                Text(finding.excerpt)
                                    .font(Theme.Fonts.caption)
                                    .foregroundStyle(Theme.textTertiary)
                            }
                            .padding(Theme.Space.s12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .quietControl(cornerRadius: Theme.Radius.tile)
                        }
                    }
                }
                .frame(maxHeight: 320)
                .panelScroll()
            } else {
                Text(L("这条审阅已经不在了，可能批准过或来源失效。"))
                    .font(Theme.Fonts.secondary)
                    .foregroundStyle(Theme.textSecondary)
            }
            HStack {
                Button(L("拒绝")) {
                    PendingReviews.remove(token)
                    dismiss()
                }
                .buttonStyle(PressableButtonStyle())
                .quietControl()
                Spacer()
                if let review {
                    Button(L("批准安装")) {
                        try? PendingReviews.approve(
                            repo: review.source.url,
                            commit: review.source.commit,
                            dirs: review.candidates.map(\.dir)
                        )
                        PendingReviews.remove(token)
                        dismiss()
                    }
                    .buttonStyle(PressableButtonStyle())
                    .accentGlass(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(Theme.Space.s16)
        .frame(width: 480)
    }
}
