import SwiftUI

// MARK: - 应用内 SKILL.md 阅读器
//
// 轻量 Markdown 渲染：块级结构（h1–h3、列表、代码块、分隔线、段落）自己拆，
// 行内样式（粗体/行内代码/链接）交给系统 AttributedString(markdown:)。
// frontmatter 折叠为键值表；>200 KB 截断并提示打开目录。

// MARK: 解析

enum SkillDocBlock {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bullet([String])
    case ordered([String])
    case code(String)
    case divider
}

struct SkillDoc {
    var frontmatter: [(key: String, value: String)] = []
    var blocks: [SkillDocBlock] = []
    var truncated = false

    static let sizeLimit = 200 * 1024

    static func load(from path: String) -> SkillDoc? {
        let url = URL(fileURLWithPath: path).appendingPathComponent("SKILL.md")
        guard var data = try? Data(contentsOf: url) else { return nil }
        var truncated = false
        if data.count > sizeLimit {
            data = data.prefix(sizeLimit)
            truncated = true
        }
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        var doc = parse(text)
        doc.truncated = truncated
        return doc
    }

    static func parse(_ text: String) -> SkillDoc {
        var doc = SkillDoc()
        var lines = text.components(separatedBy: "\n")[...]

        // frontmatter
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---" {
            lines = lines.dropFirst()
            var front: [(String, String)] = []
            while let line = lines.first {
                lines = lines.dropFirst()
                if line.trimmingCharacters(in: .whitespaces) == "---" { break }
                if let colon = line.firstIndex(of: ":"), !line.hasPrefix(" ") {
                    let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
                    let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                    front.append((key, value))
                } else if var last = front.popLast() {
                    // 折行的值并回上一键
                    last.1 += " " + line.trimmingCharacters(in: .whitespaces)
                    front.append(last)
                }
            }
            doc.frontmatter = front
        }

        var paragraph: [String] = []
        var bullets: [String] = []
        var ordered: [String] = []
        func flush() {
            if !paragraph.isEmpty {
                doc.blocks.append(.paragraph(paragraph.joined(separator: " ")))
                paragraph = []
            }
            if !bullets.isEmpty { doc.blocks.append(.bullet(bullets)); bullets = [] }
            if !ordered.isEmpty { doc.blocks.append(.ordered(ordered)); ordered = [] }
        }

        var index = lines.startIndex
        while index < lines.endIndex {
            let raw = lines[index]
            let line = raw.trimmingCharacters(in: .whitespaces)
            index += 1

            if line.hasPrefix("```") {
                flush()
                var code: [String] = []
                while index < lines.endIndex {
                    let codeLine = lines[index]
                    index += 1
                    if codeLine.trimmingCharacters(in: .whitespaces).hasPrefix("```") { break }
                    code.append(codeLine)
                }
                doc.blocks.append(.code(code.joined(separator: "\n")))
                continue
            }
            if line.isEmpty { flush(); continue }
            if line == "---" || line == "***" { flush(); doc.blocks.append(.divider); continue }
            if line.hasPrefix("#") {
                flush()
                let level = min(3, line.prefix(while: { $0 == "#" }).count)
                let text = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                doc.blocks.append(.heading(level: level, text: text))
                continue
            }
            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                if !paragraph.isEmpty || !ordered.isEmpty { flush() }
                bullets.append(String(line.dropFirst(2)))
                continue
            }
            if let dot = line.firstIndex(of: "."),
               line.distance(from: line.startIndex, to: dot) <= 2,
               line[..<dot].allSatisfy(\.isNumber),
               line.index(after: dot) < line.endIndex, line[line.index(after: dot)] == " " {
                if !paragraph.isEmpty || !bullets.isEmpty { flush() }
                ordered.append(line[line.index(dot, offsetBy: 2)...].trimmingCharacters(in: .whitespaces))
                continue
            }
            if !bullets.isEmpty {
                // 列表项的续行
                bullets[bullets.count - 1] += " " + line
                continue
            }
            if !ordered.isEmpty {
                ordered[ordered.count - 1] += " " + line
                continue
            }
            paragraph.append(line)
        }
        flush()
        return doc
    }
}

// MARK: 阅读器 sheet

struct ReaderSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    var skill: Skill
    @State private var doc: SkillDoc?
    @State private var frontmatterExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 1)
            if let doc {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.s16) {
                        if !doc.frontmatter.isEmpty { frontmatterPanel(doc.frontmatter) }
                        ForEach(Array(doc.blocks.enumerated()), id: \.offset) { _, block in
                            blockView(block)
                        }
                        if doc.truncated { truncatedNotice }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.Space.s24)
                }
                .panelScroll()
            } else {
                VStack(spacing: Theme.Space.s8) {
                    Image(systemName: "doc.questionmark")
                        .font(.system(size: 28))
                        .foregroundStyle(Theme.textTertiary)
                    Text(L("读不到 SKILL.md"))
                        .font(Theme.Fonts.rowTitle)
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 680, height: 640)
        .background(.regularMaterial)
        .onAppear { doc = SkillDoc.load(from: skill.sourcePath) }
    }

    private var header: some View {
        HStack(spacing: Theme.Space.s12) {
            CategoryIcon(category: skill.category, size: 28, style: .quiet)
            VStack(alignment: .leading, spacing: 1) {
                Text(skill.name)
                    .font(Theme.Fonts.panelTitle)
                    .foregroundStyle(Theme.textPrimary)
                Text(L("SKILL.md 完整说明"))
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            Button {
                store.openFolder(skill.sourcePath)
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 28, height: 28)
                    .quietControl()
            }
            .buttonStyle(.plain)
            .help(L("在访达中打开技能目录"))
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

    private func frontmatterPanel(_ entries: [(key: String, value: String)]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(Motion.control) { frontmatterExpanded.toggle() }
            } label: {
                HStack(spacing: Theme.Space.s8) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                        .rotationEffect(.degrees(frontmatterExpanded ? 90 : 0))
                    Text(LF("Frontmatter · %lld 项", entries.count))
                        .font(Theme.Fonts.secondaryEmphasis)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                }
                .padding(.horizontal, Theme.Space.s12)
                .padding(.vertical, Theme.Space.s8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if frontmatterExpanded {
                VStack(alignment: .leading, spacing: Theme.Space.s4) {
                    ForEach(entries, id: \.key) { entry in
                        HStack(alignment: .top, spacing: Theme.Space.s8) {
                            Text(entry.key)
                                .font(Theme.Fonts.mono)
                                .foregroundStyle(Theme.textTertiary)
                                .frame(width: 110, alignment: .trailing)
                            Text(entry.value)
                                .font(Theme.Fonts.secondary)
                                .foregroundStyle(Theme.textSecondary)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(.horizontal, Theme.Space.s12)
                .padding(.bottom, Theme.Space.s12)
            }
        }
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        }
    }

    @ViewBuilder
    private func blockView(_ block: SkillDocBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(inline(text))
                .font(level == 1
                    ? .system(size: 18, weight: .bold)
                    : level == 2 ? .system(size: 15, weight: .semibold) : .system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, level == 1 ? Theme.Space.s8 : Theme.Space.s4)
                .textSelection(.enabled)
        case .paragraph(let text):
            Text(inline(text))
                .font(Theme.Fonts.body)
                .lineSpacing(3)
                .foregroundStyle(Theme.textPrimary)
                .textSelection(.enabled)
        case .bullet(let items):
            listView(items, marker: { _ in "•" })
        case .ordered(let items):
            listView(items, marker: { "\($0 + 1)." })
        case .code(let code):
            ScrollView(.horizontal) {
                Text(code)
                    .font(Theme.Fonts.mono)
                    .foregroundStyle(Theme.textSecondary)
                    .textSelection(.enabled)
                    .padding(Theme.Space.s12)
            }
            .scrollIndicators(.never)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            }
        case .divider:
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 1)
                .padding(.vertical, Theme.Space.s4)
        }
    }

    private func listView(_ items: [String], marker: @escaping (Int) -> String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s4) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: Theme.Space.s8) {
                    Text(marker(index))
                        .font(Theme.Fonts.body)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textTertiary)
                        .frame(minWidth: 14, alignment: .trailing)
                    Text(inline(item))
                        .font(Theme.Fonts.body)
                        .lineSpacing(2)
                        .foregroundStyle(Theme.textPrimary)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var truncatedNotice: some View {
        HStack(spacing: Theme.Space.s8) {
            Image(systemName: "scissors")
                .font(.system(size: 11))
                .foregroundStyle(Theme.warning)
            Text(L("文件超过 200 KB，仅显示开头部分。"))
                .font(Theme.Fonts.secondary)
                .foregroundStyle(Theme.textSecondary)
            Button(L("打开目录查看原文")) {
                store.openFolder(skill.sourcePath)
            }
            .buttonStyle(.link)
            .font(Theme.Fonts.secondaryEmphasis)
        }
        .padding(Theme.Space.s12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .fill(Theme.warning.opacity(0.08))
        }
    }

    /// 行内样式交给系统解析（粗体/行内代码/链接）；解析失败原样显示
    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }
}
