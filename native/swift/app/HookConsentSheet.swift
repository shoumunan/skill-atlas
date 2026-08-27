import SwiftUI
#if SWIFT_PACKAGE
import AtlasCore
#endif

/// 首跑一次性询问：hook 只采 {skill, ts, session} 本地三元组。
struct HookConsentSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s12) {
            Text(L("把技能调用记在本机"))
                .font(Theme.Fonts.calloutEmphasis)
            Text(L("接入后，每次真正调用技能会记一行：技能名、时间、会话号。三元组只留在这台电脑，不会上传。hook 脚本永远成功退出，不挡你的工具调用。"))
                .font(Theme.Fonts.secondary)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(L("暂不")) {
                    UserDefaults.standard.set(true, forKey: "atlasHookConsentAsked")
                    dismiss()
                }
                .buttonStyle(PressableButtonStyle())
                .quietControl()
                Spacer()
                Button(L("接入")) {
                    UserDefaults.standard.set(true, forKey: "atlasHookConsentAsked")
                    do {
                        try HookTelemetry.install()
                        store.mergeHookStats()
                    } catch {
                        store.actionError = error.localizedDescription
                    }
                    AtlasNotify.requestAuthorization()
                    dismiss()
                }
                .buttonStyle(PressableButtonStyle())
                .accentGlass(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.Space.s16)
        .frame(width: 440)
    }
}
