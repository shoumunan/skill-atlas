import AppKit
import SwiftUI

// MARK: - 我在用的软件
//
// 空库勾一次，之后新装默认点亮这些。没勾过就看本机有没有
// ~/.claude / ~/.cursor / ~/.codex 这类目录，都没有则只预勾 Claude。

enum PreferredPlatforms {
    static let storageKey = "atlasPreferredPlatforms"
    static let chosenKey = "atlasPreferredPlatformsChosen"

    static var current: Set<String> {
        if UserDefaults.standard.bool(forKey: chosenKey),
           let stored = UserDefaults.standard.stringArray(forKey: storageKey) {
            let cleaned = Set(stored).intersection(allowed)
            if !cleaned.isEmpty { return cleaned }
        }
        return inferred
    }

    static var inferred: Set<String> {
        var found = Set<String>()
        let home = AtlasPaths.home
        for raw in allowed {
            guard let platform = AgentPlatform(rawValue: raw) else { continue }
            let folder = platform.root(home: home).deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: folder.path) {
                found.insert(raw)
            }
        }
        if found.isEmpty { found.insert(AgentPlatform.claude.rawValue) }
        return found
    }

    static func save(_ raw: Set<String>) {
        let cleaned = raw.intersection(allowed)
        let value = cleaned.isEmpty ? inferred : cleaned
        UserDefaults.standard.set(Array(value), forKey: storageKey)
        UserDefaults.standard.set(true, forKey: chosenKey)
    }

    private static let allowed: Set<String> = [
        AgentPlatform.claude.rawValue,
        AgentPlatform.codex.rawValue,
        AgentPlatform.gemini.rawValue,
        AgentPlatform.grokbuild.rawValue,
        AgentPlatform.cursor.rawValue,
        AgentPlatform.workbuddy.rawValue,
    ]
}

// MARK: - 打开宿主软件

enum HostLauncher {
    static func canOpen(_ platform: AgentPlatform) -> Bool {
        locate(platform) != nil
    }

    static func open(_ platform: AgentPlatform) {
        guard let url = locate(platform) else { return }
        NSWorkspace.shared.open(url)
    }

    static func locate(_ platform: AgentPlatform) -> URL? {
        let workspace = NSWorkspace.shared
        for id in bundleIDs(for: platform) {
            if let url = workspace.urlForApplication(withBundleIdentifier: id) { return url }
        }
        for name in appNames(for: platform) {
            let path = "/Applications/\(name).app"
            if FileManager.default.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    private static func bundleIDs(for platform: AgentPlatform) -> [String] {
        switch platform {
        case .claude: return ["com.anthropic.claudefordesktop", "com.anthropic.claude"]
        case .cursor: return ["com.todesktop.230313mzl4w4u92"]
        case .codex: return ["com.openai.chat"]
        case .gemini: return []
        case .grokbuild: return ["ai.x.grok"]
        case .workbuddy: return []
        default: return []
        }
    }

    private static func appNames(for platform: AgentPlatform) -> [String] {
        switch platform {
        case .claude: return ["Claude"]
        case .cursor: return ["Cursor"]
        case .codex: return ["ChatGPT", "Codex"]
        case .gemini: return ["Gemini"]
        case .grokbuild: return ["Grok"]
        case .workbuddy: return ["WorkBuddy"]
        default: return []
        }
    }
}

// MARK: - 空库可一键装的例子
//
// 只给两个。三张一样的卡是空状态里最容易堆出来的噪音。
// 链到 anthropics/skills 的安装版：Claude Code 不自带这几个文档技能，装进去才能用。

enum StarterSkill: String, CaseIterable, Identifiable {
    case docx, pdf

    var id: String { rawValue }

    var title: String {
        switch self {
        case .docx: return "写 Word"
        case .pdf: return "处理 PDF"
        }
    }

    var blurb: String {
        switch self {
        case .docx: return "写和改文档"
        case .pdf: return "读和整理文件"
        }
    }

    var symbol: String {
        switch self {
        case .docx: return "doc.richtext"
        case .pdf: return "doc.text"
        }
    }

    var url: String {
        "https://github.com/anthropics/skills/tree/main/skills/\(rawValue)"
    }
}

// MARK: - 平台勾选条（空库 / 设置 / 安装共用）

struct PlatformPrefStrip: View {
    @Environment(AppStore.self) private var store
    var selection: Binding<Set<String>>?
    var installSession = false

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 108), spacing: Theme.Space.s8)],
            alignment: .leading,
            spacing: Theme.Space.s8
        ) {
            ForEach(store.visiblePlatforms) { platform in
                let on = current.contains(platform.rawValue)
                Button {
                    toggle(platform)
                } label: {
                    HStack(spacing: Theme.Space.s4 + 1) {
                        PlatformLogo(platform: platform, size: 18, lit: on)
                        Text(platform.displayName)
                            .font(on ? Theme.Fonts.calloutEmphasis : Theme.Fonts.callout)
                            .foregroundStyle(on ? Theme.textPrimary : Theme.textTertiary)
                    }
                    .padding(.horizontal, Theme.Space.s8)
                    .frame(height: 28)
                    .frame(maxWidth: .infinity)
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
                .help(help(on: on, platform: platform))
            }
        }
    }

    private var current: Set<String> {
        selection?.wrappedValue ?? store.preferredPlatforms
    }

    private func toggle(_ platform: AgentPlatform) {
        if let selection {
            if selection.wrappedValue.contains(platform.rawValue) {
                guard selection.wrappedValue.count > 1 else { return }
                selection.wrappedValue.remove(platform.rawValue)
            } else {
                selection.wrappedValue.insert(platform.rawValue)
            }
        } else {
            store.togglePreferred(platform)
        }
    }

    private func help(on: Bool, platform: AgentPlatform) -> String {
        if installSession {
            return on
                ? LF("装好后会在 %@ 里出现", platform.displayName)
                : LF("这次不装到 %@", platform.displayName)
        }
        return on
            ? LF("以后新装的会先开 %@", platform.displayName)
            : LF("先不开 %@", platform.displayName)
    }
}

// MARK: - 打开宿主（复制后贴进去）
//
// 复制调用语已经是主按钮。这里只补「打开软件」这一个意图：
// 能开的只有一个就直接写名字，多个就收进菜单，避免一排同款按钮。

struct OpenHostButtons: View {
    @Environment(AppStore.self) private var store
    var platforms: [AgentPlatform]
    var phrase: String?
    var onCopied: () -> Void = {}

    var body: some View {
        let openable = platforms.filter { HostLauncher.canOpen($0) }
        if openable.count == 1, let platform = openable.first {
            hostButton(LF("打开 %@", platform.displayName)) {
                open(platform)
            }
        } else if openable.count > 1 {
            Menu {
                ForEach(openable) { platform in
                    Button(platform.displayName) { open(platform) }
                }
            } label: {
                Text(L("打开软件"))
                    .font(Theme.Fonts.calloutEmphasis)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, Theme.Space.s12)
                    .frame(height: 28)
                    .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            }
            .menuStyle(.borderlessButton)
            .buttonStyle(PressableButtonStyle())
            .quietControl()
            .help(phrase == nil ? L("打开已点亮的软件") : L("复制这句，并打开软件"))
        }
    }

    private func open(_ platform: AgentPlatform) {
        if let phrase {
            store.copyToPasteboard(phrase)
            onCopied()
        }
        HostLauncher.open(platform)
    }

    private func hostButton(_ title: String, action: @escaping () -> Void) -> some View {
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
        .help(phrase == nil ? title : L("复制这句，并打开软件"))
    }
}
