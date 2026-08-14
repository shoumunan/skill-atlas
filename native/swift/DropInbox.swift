import SwiftUI
import UniformTypeIdentifiers

// MARK: - 素材投递箱（二期 F5）
//
// 「吃文件」型生产技能的文件→技能映射规则化：拖文件进主窗口 →
// 按文件名模式 + 扩展名匹配技能 → 确认弹层一键发起（带路径）。

struct DropMatch {
    var skillDirectory: String
    var reason: String
}

@MainActor
enum DropRules {
    struct Rule {
        var nameContains: [String]
        var extensions: [String]
        var skillDirectory: String
        var reason: String
    }

    /// 顺序即优先级；第一条命中为首选，其余命中做备选
    static let rules: [Rule] = [
        Rule(nameContains: ["自运营会议数据", "自运营"], extensions: ["xlsx", "xls"],
             skillDirectory: "somd", reason: "自运营会议数据 → 更新大盘底稿"),
        Rule(nameContains: ["视频数据", "周报"], extensions: ["xlsx", "xls"],
             skillDirectory: "weekly-video-data", reason: "周报视频数据"),
        Rule(nameContains: ["研报", "证券", "深度报告", "首次覆盖", "点评"], extensions: ["pdf"],
             skillDirectory: "research-index", reason: "研报归档进投研问答库"),
        Rule(nameContains: [], extensions: ["pdf"],
             skillDirectory: "research-index", reason: "PDF 默认走投研归档"),
        Rule(nameContains: ["热点解读", "热点视频"], extensions: ["docx"],
             skillDirectory: "to-xhs", reason: "成稿改编小红书"),
        Rule(nameContains: ["会议", "纪要"], extensions: ["docx", "md", "txt"],
             skillDirectory: "research-index", reason: "会议纪要归档"),
    ]

    /// 匹配：首选 + 备选（按规则顺序）
    static func match(fileURL: URL, skills: [Skill]) -> [DropMatch] {
        let name = fileURL.deletingPathExtension().lastPathComponent
        let ext = fileURL.pathExtension.lowercased()
        let installed = Set(skills.filter { !$0.disabled }.map(\.directory))
        var matches: [DropMatch] = []
        var seen = Set<String>()
        for rule in rules {
            guard rule.extensions.contains(ext) else { continue }
            let nameHit = rule.nameContains.isEmpty
                || rule.nameContains.contains { name.contains($0) }
            guard nameHit, installed.contains(rule.skillDirectory),
                  seen.insert(rule.skillDirectory).inserted else { continue }
            matches.append(DropMatch(skillDirectory: rule.skillDirectory, reason: rule.reason))
        }
        return matches
    }
}

// MARK: - 投递确认弹层

struct DropSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var chosenDirectory: String
    @State private var topic: String
    @State private var errorText: String?
    let fileURL: URL
    let matches: [DropMatch]

    init(fileURL: URL, matches: [DropMatch]) {
        self.fileURL = fileURL
        self.matches = matches
        _chosenDirectory = State(initialValue: matches.first?.skillDirectory ?? "")
        _topic = State(initialValue: fileURL.deletingPathExtension().lastPathComponent)
    }

    private var chosenSkill: Skill? {
        store.skills.first { $0.directory == chosenDirectory }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1)
            content.padding(Theme.Space.s20)
        }
        .frame(width: 480)
        .background(.regularMaterial)
    }

    private var header: some View {
        HStack(spacing: Theme.Space.s12) {
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 28, height: 28)
                .background {
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .fill(Theme.accent.opacity(0.12))
                }
            VStack(alignment: .leading, spacing: 1) {
                Text("素材投递")
                    .font(Theme.Fonts.panelTitle)
                    .foregroundStyle(Theme.textPrimary)
                Text(fileURL.lastPathComponent)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
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
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, Theme.Space.s20)
        .padding(.vertical, Theme.Space.s16)
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s12) {
            if matches.isEmpty {
                Text("没有匹配的投递规则。挑一个技能，素材路径会附在调用语里：")
                    .font(Theme.Fonts.secondary)
                    .foregroundStyle(Theme.textSecondary)
            }
            skillPicker
            TextField(L("主题（用于目录名，可改）"), text: $topic)
                .textFieldStyle(.plain)
                .font(Theme.Fonts.body)
                .padding(.horizontal, Theme.Space.s8 + 2)
                .frame(height: 30)
                .quietControl()
            if let skill = chosenSkill {
                Text(SkillLauncher.sessionDirectory(for: skill, topic: topic).path
                    .replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(Theme.Fonts.mono)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let errorText {
                Text(errorText)
                    .font(Theme.Fonts.secondary)
                    .foregroundStyle(Theme.error)
            }
            HStack {
                Spacer()
                Button {
                    launch()
                } label: {
                    HStack(spacing: Theme.Space.s4) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10, weight: .semibold))
                        Text("带素材发起")
                            .font(Theme.Fonts.calloutEmphasis)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, Theme.Space.s16)
                    .frame(height: 28)
                    .contentShape(Capsule())
                }
                .buttonStyle(PressableButtonStyle())
                .accentGlass(Capsule(style: .continuous))
                .disabled(chosenSkill == nil)
                .opacity(chosenSkill == nil ? 0.4 : 1)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var skillPicker: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s4) {
            ForEach(pickerOptions, id: \.0) { directory, reason in
                let skill = store.skills.first { $0.directory == directory }
                Button {
                    chosenDirectory = directory
                } label: {
                    HStack(spacing: Theme.Space.s8) {
                        Image(systemName: chosenDirectory == directory ? "largecircle.fill.circle" : "circle")
                            .font(.system(size: 12))
                            .foregroundStyle(chosenDirectory == directory ? Theme.accent : Theme.textTertiary)
                        if let skill {
                            CategoryIcon(category: skill.category, size: 22, style: .quiet)
                            Text(skill.name)
                                .font(Theme.Fonts.rowTitle)
                                .foregroundStyle(Theme.textPrimary)
                        } else {
                            Text(directory)
                                .font(Theme.Fonts.rowTitle)
                                .foregroundStyle(Theme.textTertiary)
                        }
                        Text(L(reason))
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, Theme.Space.s8)
                    .frame(height: 32)
                    .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                    .background {
                        RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                            .fill(chosenDirectory == directory ? Theme.accent.opacity(0.08) : Color.clear)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// 命中的规则 + 兜底常用技能（保证空匹配时也能选）
    private var pickerOptions: [(String, String)] {
        var options = matches.map { ($0.skillDirectory, $0.reason) }
        if options.isEmpty {
            let fallbacks = ["research-index", "somd", "to-xhs", "hotspot"]
            for directory in fallbacks
            where store.skills.contains(where: { $0.directory == directory && !$0.disabled }) {
                options.append((directory, "手动指定"))
            }
        }
        return options
    }

    private func launch() {
        guard let skill = chosenSkill else { return }
        do {
            _ = try SkillLauncher.launch(
                skill: skill,
                topic: topic,
                materialPath: fileURL.path
            )
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}
