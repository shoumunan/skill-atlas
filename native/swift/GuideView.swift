import SwiftUI

// MARK: - 指南页（v7 重排：一条主线三步走，右列放概念和体检入口）
//
// 左（弹性）：三步把技能用起来——挑技能 → 复制调用语（活例子）→ 贴进 Agent
// 右（400）：三个名词速览 / 装多了会怎样（数字 + 去体检）

struct GuidePage: View {
    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.s12) {
            StepsPanel()
            VStack(spacing: Theme.Space.s12) {
                GlossaryPanel()
                CapacityPanel()
            }
            .frame(width: 400)
            .frame(maxHeight: .infinity)
        }
        .frame(maxHeight: .infinity)
    }
}

// MARK: - 左：三步主线

private struct StepsPanel: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s16) {
            PanelHead(
                title: "三步把技能用起来",
                subtitle: "技能不是独立 App，是给 Agent 看的说明书。整个流程只是一句话的事。"
            )
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    StepBlock(
                        index: 1,
                        title: "挑一个技能",
                        detail: "在技能库选中想用的；不确定用哪个就 ⌘K 搜任务本身——搜「做个PPT」能命中 pptx。"
                    ) {
                        AnyView(EmptyView())
                    }
                    StepBlock(
                        index: 2,
                        title: "复制调用语",
                        detail: "列表行悬停、详情页、菜单栏 ⌥⌘K 回车，都能一键复制。下面就是你库里的活例子："
                    ) {
                        AnyView(FeaturedExample())
                    }
                    StepBlock(
                        index: 3,
                        title: "贴进 Agent 对话框",
                        detail: "Claude Code、Codex、Grok 任一都行（技能挂到哪个 Harness，哪个就能用）。也可以不点名、直接描述任务让它自动匹配——但技能一多自动匹配会失灵，点名最稳。",
                        last: true
                    ) {
                        AnyView(platformRow)
                    }
                }
                .padding(.top, Theme.Space.s4)
            }
            .panelScroll()
        }
        .padding(Theme.Space.s20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentSurface()
    }

    private var platformRow: some View {
        HStack(spacing: Theme.Space.s8) {
            ForEach(store.visiblePlatforms) { platform in
                HStack(spacing: Theme.Space.s4 + 1) {
                    PlatformLogo(platform: platform, size: 18)
                    Text(platform.displayName)
                        .font(Theme.Fonts.secondary)
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.horizontal, Theme.Space.s8)
                .frame(height: 28)
                .quietControl()
            }
            Spacer(minLength: 0)
        }
    }
}

/// 步骤块：序号圆章 + 连接线 + 标题 + 说明 + 可选内容
private struct StepBlock: View {
    var index: Int
    var title: String
    var detail: String
    var last = false
    var content: () -> AnyView

    init(index: Int, title: String, detail: String, last: Bool = false, content: @escaping () -> AnyView) {
        self.index = index
        self.title = title
        self.detail = detail
        self.last = last
        self.content = content
    }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.s12) {
            VStack(spacing: 0) {
                Text("\(index)")
                    .font(Theme.Fonts.calloutEmphasis)
                    .monospacedDigit()
                    .foregroundStyle(Theme.accent)
                    .frame(width: 24, height: 24)
                    .background {
                        Circle().fill(Theme.accent.opacity(0.12))
                    }
                    .overlay {
                        Circle().strokeBorder(Theme.accent.opacity(0.25), lineWidth: 0.5)
                    }
                if !last {
                    // 步骤连接线：2pt 渐隐，确保在玻璃底上可见
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [Color.primary.opacity(0.14), Color.primary.opacity(0.05)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                        .padding(.vertical, Theme.Space.s4)
                }
            }
            VStack(alignment: .leading, spacing: Theme.Space.s8) {
                Text(L(title))
                    .font(Theme.Fonts.rowTitle)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.top, 3)
                Text(L(detail))
                    .font(Theme.Fonts.body)
                    .lineSpacing(2)
                    .foregroundStyle(Theme.textSecondary)
                content()
            }
            .padding(.bottom, last ? 0 : Theme.Space.s20)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// 第 2 步的活例子：当前选中（否则最常用）技能的完整调用语 + 复制
private struct FeaturedExample: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var copied = false

    var body: some View {
        if let skill = store.featuredSkill {
            VStack(alignment: .leading, spacing: Theme.Space.s8 + 2) {
                HStack(spacing: Theme.Space.s8 + 2) {
                    CategoryIcon(category: skill.category, size: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(skill.name)
                            .font(Theme.Fonts.rowTitle)
                            .foregroundStyle(Theme.textPrimary)
                        Text(store.selectedSkill == nil ? L("你最常用的技能") : L("当前选中的技能"))
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    Spacer()
                    PlatformStrip(skill: skill, platforms: store.visiblePlatforms, size: 16, interactive: false)
                }
                Text(AppStore.callPhrase(for: skill))
                    .font(Theme.Fonts.body)
                    .lineSpacing(2)
                    .foregroundStyle(Theme.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.Space.s12)
                    .quietControl(cornerRadius: Theme.Radius.row)
                Button {
                    store.copyToPasteboard(AppStore.callPhrase(for: skill))
                    withAnimation(reduceMotion ? nil : Motion.control) { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        withAnimation(reduceMotion ? nil : Motion.control) { copied = false }
                    }
                } label: {
                    HStack(spacing: Theme.Space.s4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11, weight: .semibold))
                            .contentTransition(.symbolEffect(.replace))
                        Text(copied ? L("已复制") : L("复制调用语"))
                            .font(Theme.Fonts.calloutEmphasis)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, Theme.Space.s12 + 2)
                    .frame(height: 28)
                    .contentShape(Capsule())
                }
                .buttonStyle(PressableButtonStyle())
                .accentGlass(Capsule(style: .continuous), tint: copied ? Theme.healthy : Theme.accent)
            }
            .padding(Theme.Space.s12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .quietControl(cornerRadius: Theme.Radius.tile)
        } else {
            Text(L("库里还没有技能，先去安装一个。"))
                .font(Theme.Fonts.secondary)
                .foregroundStyle(Theme.textTertiary)
        }
    }
}

// MARK: - 右上：三个名词

private struct GlossaryPanel: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s12) {
            PanelHead(title: "四个名词，30 秒", subtitle: "分清这四个，就不会装错地方。")
            term(
                symbol: "text.book.closed.fill",
                title: "Skill",
                body: skillExample
            )
            term(
                symbol: "cpu.fill",
                title: "Agent",
                body: "会自己规划步骤、调用工具把任务跑完的 AI。Skill 是给它看的说明书。"
            )
            term(
                symbol: "steeringwheel",
                title: "Harness",
                body: "承载 Agent 的驾驶舱程序：Claude Code、Codex、Grok 这些「壳」。它决定 Agent 能读到哪些技能、动用哪些工具——所以同一个技能要分别挂到各个 Harness。"
            )
            term(
                symbol: "powerplug.fill",
                title: "MCP",
                body: "给 Agent 插的外部工具（查库、调 API）。不归本应用管，开关在 CC Switch。"
            )
            Spacer(minLength: 0)
        }
        .padding(Theme.Space.s20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentSurface()
    }

    private var skillExample: String {
        if store.skills.contains(where: { $0.directory == "hotspot" || $0.name == "hotspot" }) {
            return "一个带 SKILL.md 的文件夹。比如你库里的 hotspot = 按模板写热点解读。"
        }
        if let skill = store.featuredSkill {
            return "一个带 SKILL.md 的文件夹。比如你库里的 \(skill.name)。"
        }
        return "一个带 SKILL.md 的文件夹，写着「这件事按这套流程做」。"
    }

    private func term(symbol: String, title: String, body text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.s8 + 2) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 20, height: 20)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Theme.accent.opacity(0.10))
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Fonts.calloutEmphasis)
                    .foregroundStyle(Theme.textPrimary)
                Text(L(text))
                    .font(Theme.Fonts.secondary)
                    .lineSpacing(2)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }
}

// MARK: - 右下：装多了会怎样

private struct CapacityPanel: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        let total = store.skills.filter { !$0.disabled }.count
        let used = store.usedSkillCount
        let report = store.doctorReport
        VStack(alignment: .leading, spacing: Theme.Space.s12) {
            PanelHead(
                title: "装多了会怎样",
                subtitle: LF("Claude 启动时大约只能看完 %d 个描述，多出来的会静默失踪。", ContextDoctor.listingSoftCap)
            )
            HStack(spacing: Theme.Space.s16) {
                mini(value: "\(total)", label: "上架")
                mini(value: "\(used)", label: "用过")
                mini(value: "\(max(0, total - ContextDoctor.listingSoftCap))", label: "可能失踪")
            }
            Text(report.overBudget
                ? LF("当前清单已超预算，%d 个技能的描述有被丢掉的风险。", report.atRisk.count)
                : L("预算还够。继续往上堆之前，先处理长期未用的。"))
                .font(Theme.Fonts.secondary)
                .lineSpacing(2)
                .foregroundStyle(report.overBudget ? Theme.warning : Theme.textSecondary)
            Button {
                store.nav = .doctor
            } label: {
                HStack(spacing: Theme.Space.s4) {
                    Image(systemName: "heart.text.square")
                        .font(.system(size: 11, weight: .semibold))
                    Text(L("去体检页处理"))
                        .font(Theme.Fonts.calloutEmphasis)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, Theme.Space.s12 + 2)
                .frame(height: 28)
                .contentShape(Capsule())
            }
            .buttonStyle(PressableButtonStyle())
            .accentGlass(Capsule(style: .continuous))
            .help(L("打开体检：预算、重叠、长期未用"))
            Spacer(minLength: 0)
        }
        .padding(Theme.Space.s20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentSurface()
    }

    private func mini(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(Theme.Fonts.metric)
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .contentTransition(.numericText())
            Text(L(label))
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
