import SwiftUI

// MARK: - ② 四个词，一条链（概念关系图）
//
// 这四个概念不是一条并列的链，是「一条穿越 + 一层包裹 + 两条供给」：
//
//   ┌──────┐         ┌╌ Agent 应用 ╌╌╌╌╌╌╌╌╌╌╌╌╌╌┐
//   │  你  │──说要做──╎────▶┌──────────┐          ╎
//   └──────┘   什么   ╎     │  Agent   │          ╎   ← 线穿过左边界，
//                    ╎     └──▲────▲──┘          ╎     边界在穿越处断开
//                    ╎    ┌───┘    └───┐         ╎
//                    ╎ ┌──┴───┐   ┌────┴──┐      ╎
//                    ╎ │Skill │   │  MCP  │      ╎
//                    ╎ └──────┘   └───────┘      ╎
//                    └╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┘
//
// 三个刻意的设计决定：
// 1. 客户端画成「容器」不是链上一环——Agent 住在里面，技能和外部连接也得装进
//    这栋房子才算数。画成嵌套之后，「同一个技能要分别挂到每个客户端」不用解释就成立。
// 2. 所有箭头都指向 Agent：一眼看出干活的只有一个，其余都在喂它。
// 3. 单色系统（accent + 中性灰阶），绝不给四个概念各配一个颜色——那既违反色彩收敛，
//    也会立刻退化成 DESIGN.md 禁止的「重复分类网格」。
//
// 节点副句（每个节点第二行）不点也读得到，它承担名词速查的职责。
// 删掉副句 = 这页对新手的价值归零，改这里前先读 GuideView.swift 文件头。

enum ConceptLayer: String, CaseIterable, Identifiable, Hashable {
    case you, harness, agent, skill, mcp

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .you: return "person.fill"
        case .harness: return "macwindow"
        case .agent: return "cpu"
        case .skill: return "text.book.closed.fill"
        case .mcp: return "powerplug.fill"
        }
    }

    var title: String {
        switch self {
        case .you: return "你"
        case .harness: return "Agent 应用"
        case .agent: return "Agent"
        case .skill: return "Skill"
        case .mcp: return "MCP"
        }
    }

    /// 节点第二行：这一层的定义句。不交互也读得到，是名词速查的唯一落点。
    var caption: String {
        switch self {
        case .you: return "用大白话说要做什么"
        case .harness: return "Claude Code、Codex 这类客户端"
        case .agent: return "自己决定下一步、调工具把活干完"
        case .skill: return "一个带 SKILL.md 的文件夹：这件事怎么做"
        case .mcp: return "连接外部系统的开放协议"
        }
    }

    /// 解释卡正文（展开版）
    var detail: String {
        switch self {
        case .you:
            return "你只需要说人话，不用记命令，也不用指定文件。点名技能是为了技能多了之后更稳。"
        case .harness:
            return "承载 Agent 的客户端，Claude Code、Codex 这一类。工程圈通称 Harness，Anthropic 官方文档里叫 AI application 或 MCP Host。可以把它想成一栋房子：Agent 住在里面，技能和外部连接也得装进这栋房子才算数。它提供工具、权限和上下文管理，也决定 Agent 开会话时能看到哪些技能。所以同一个技能，换一个客户端要重新挂一遍。"
        case .agent:
            return "会自己决定下一步做什么、调哪个工具，直到任务完成的那一层。步骤被代码写死的那叫 workflow，不叫 Agent。它不会主动跑，是你的话唤醒它。"
        case .skill:
            return "一个带 SKILL.md 的文件夹，可以再附脚本和参考文件。它给的是做法，不给新能力。Agent 能做什么，仍由客户端提供的工具决定。平时只有它的名字和描述在 Agent 眼前，被点中才把正文读进来。"
        case .mcp:
            return "连接外部系统的开放协议，官方比喻是 AI 应用的 USB-C 口。你装的东西叫 MCP server，它对外提供三样：可执行的工具、数据源、可复用的提示模板。Skill 教 Agent 怎么做，MCP 决定 Agent 能碰到什么。二者正交，不是二选一。"
        }
    }

    /// 解释卡尾段：在这个应用里对应什么
    var inApp: String {
        switch self {
        case .you: return "列表行悬停就能复制调用语。"
        case .harness: return "列表行那排平台标就是「挂进了哪几栋房子」，单击即挂 / 摘。"
        case .agent: return "不出现。本应用只负责给它准备材料。"
        case .skill: return "库里的每一行。"
        case .mcp: return "不管。它配在各 Agent 应用自己的设置里。"
        }
    }
}

// MARK: 几何（视图层与连线层共用同一份，杜绝两处各写一遍导致对不齐）

struct ConceptMapGeometry {
    /// 画布可用宽（560…880）
    let w: CGFloat
    /// 画布高恒定，两种形态都不变
    static let height: CGFloat = 300

    var youRect: CGRect { CGRect(x: 0, y: 50, width: 96, height: 80) }
    var boxRect: CGRect { CGRect(x: 128, y: 0, width: max(320, w - 128), height: Self.height) }

    private var innerW: CGFloat { boxRect.width - 40 }
    /// 两个下层节点等宽平分，留 20 间隙
    var nodeW: CGFloat { max(140, (innerW - 20) / 2) }

    /// y = 50 不是 52：Agent 与「你」的垂直中心必须都落在 flowY(90)，
    /// 否则那条横穿箭头会偏离 Agent 中线 2pt——绝对定位下这种偏差肉眼可见
    var agentRect: CGRect {
        CGRect(x: boxRect.minX + 20 + (innerW - nodeW) / 2, y: 50, width: nodeW, height: 80)
    }
    var skillRect: CGRect {
        CGRect(x: boxRect.minX + 20, y: 200, width: nodeW, height: 72)
    }
    var mcpRect: CGRect {
        CGRect(x: boxRect.minX + 20 + nodeW + 20, y: 200, width: nodeW, height: 72)
    }

    /// 「你 → Agent」是纯水平线：两者垂直中心都在 y=90
    var flowY: CGFloat { 90 }
    /// 左边界让路给横穿的那条线
    var doorGap: ClosedRange<CGFloat> { (flowY - 8)...(flowY + 8) }
    /// 两条供给线的汇聚横线：Agent 底与 Skill 顶的中点
    var junctionY: CGFloat { (agentRect.maxY + skillRect.minY) / 2 }

    func rect(for layer: ConceptLayer) -> CGRect {
        switch layer {
        case .you: return youRect
        case .harness: return boxRect
        case .agent: return agentRect
        case .skill: return skillRect
        case .mcp: return mcpRect
        }
    }
}

// MARK: 形状

/// 客户端外框：左边界在横线穿过处断开——这个断口说明容器不是墙而是通道
private struct HarnessBoxOutline: Shape {
    var box: CGRect
    var gap: ClosedRange<CGFloat>

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = Theme.Radius.panel
        let minX = box.minX, maxX = box.maxX, minY = box.minY, maxY = box.maxY
        // 从断口下沿起笔，顺时针绕一圈回到断口上沿
        path.move(to: CGPoint(x: minX, y: gap.upperBound))
        path.addLine(to: CGPoint(x: minX, y: maxY - r))
        path.addQuadCurve(to: CGPoint(x: minX + r, y: maxY), control: CGPoint(x: minX, y: maxY))
        path.addLine(to: CGPoint(x: maxX - r, y: maxY))
        path.addQuadCurve(to: CGPoint(x: maxX, y: maxY - r), control: CGPoint(x: maxX, y: maxY))
        path.addLine(to: CGPoint(x: maxX, y: minY + r))
        path.addQuadCurve(to: CGPoint(x: maxX - r, y: minY), control: CGPoint(x: maxX, y: minY))
        path.addLine(to: CGPoint(x: minX + r, y: minY))
        path.addQuadCurve(to: CGPoint(x: minX, y: minY + r), control: CGPoint(x: minX, y: minY))
        path.addLine(to: CGPoint(x: minX, y: gap.lowerBound))
        return path
    }
}

/// 你 → Agent：一条水平线
private struct FlowLine: Shape {
    var from: CGPoint
    var to: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)
        return path
    }
}

/// Skill / MCP → Agent：正交折线（竖 → 横 → 竖），拐角圆角
private struct SupplyLine: Shape {
    var start: CGPoint      // 节点顶边中点
    var junctionY: CGFloat  // 汇聚横线
    var end: CGPoint        // Agent 底边上的落点（箭头尖）

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r: CGFloat = 8
        let goingRight = end.x > start.x
        path.move(to: start)
        path.addLine(to: CGPoint(x: start.x, y: junctionY + r))
        path.addQuadCurve(
            to: CGPoint(x: start.x + (goingRight ? r : -r), y: junctionY),
            control: CGPoint(x: start.x, y: junctionY)
        )
        path.addLine(to: CGPoint(x: end.x - (goingRight ? r : -r), y: junctionY))
        path.addQuadCurve(
            to: CGPoint(x: end.x, y: junctionY - r),
            control: CGPoint(x: end.x, y: junctionY)
        )
        path.addLine(to: end)
        return path
    }
}

/// 实心三角箭头
private struct ArrowHead: Shape {
    enum Direction { case right, up }
    var tip: CGPoint
    var direction: Direction

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let len: CGFloat = 7, half: CGFloat = 3.5
        switch direction {
        case .right:
            path.move(to: tip)
            path.addLine(to: CGPoint(x: tip.x - len, y: tip.y - half))
            path.addLine(to: CGPoint(x: tip.x - len, y: tip.y + half))
        case .up:
            path.move(to: tip)
            path.addLine(to: CGPoint(x: tip.x - half, y: tip.y + len))
            path.addLine(to: CGPoint(x: tip.x + half, y: tip.y + len))
        }
        path.closeSubpath()
        return path
    }
}

// MARK: 关系图

struct ConceptMap: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var locked: ConceptLayer?
    @State private var hovered: ConceptLayer?

    /// hover 预览、点击锁定：不点也能扫读，点了才定住
    private var active: ConceptLayer? { hovered ?? locked }
    private var dark: Bool { colorScheme == .dark }
    /// 暗色下 L1 面板本身是半透明深灰，18% 的线会糊掉，必须提亮
    private var lineColor: Color { Color.primary.opacity(dark ? 0.26 : 0.18) }
    private var boxColor: Color { Color.primary.opacity(dark ? 0.20 : 0.14) }

    var body: some View {
        GeometryReader { geo in
            let map = ConceptMapGeometry(w: geo.size.width)
            ZStack(alignment: .topLeading) {
                boxLayer(map)
                connectorLayer(map)
                    .accessibilityHidden(true)
                // 声明顺序 = 阅读顺序，保证 .position 之后 Tab 焦点顺序与视觉一致
                node(.you, in: map)
                boxLabel(map)
                node(.agent, in: map)
                node(.skill, in: map)
                node(.mcp, in: map)
            }
            .frame(width: geo.size.width, height: ConceptMapGeometry.height)
        }
        .frame(height: ConceptMapGeometry.height)
        .animation(reduceMotion ? nil : Motion.control, value: active)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("概念关系图：你、Agent 应用、Agent、Skill、MCP 的关系"))
    }

    // MARK: 层

    private func boxLayer(_ map: ConceptMapGeometry) -> some View {
        let on = active == .harness
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
                .fill(on ? Theme.accent.opacity(0.05) : Color.primary.opacity(0.03))
                .frame(width: map.boxRect.width, height: map.boxRect.height)
                .position(x: map.boxRect.midX, y: map.boxRect.midY)
            // 虚线保持虚线：虚线是「边界/容器」的语义，不能因为高亮就变实线
            HarnessBoxOutline(box: map.boxRect, gap: map.doorGap)
                .stroke(
                    on ? Theme.accent.opacity(0.40) : boxColor,
                    style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                )
        }
    }

    private func connectorLayer(_ map: ConceptMapGeometry) -> some View {
        let agent = map.agentRect
        let skillStart = CGPoint(x: map.skillRect.midX, y: map.skillRect.minY)
        let mcpStart = CGPoint(x: map.mcpRect.midX, y: map.mcpRect.minY)
        let leftLanding = CGPoint(x: agent.minX + agent.width / 3, y: agent.maxY)
        let rightLanding = CGPoint(x: agent.minX + agent.width * 2 / 3, y: agent.maxY)
        let flowEnd = CGPoint(x: agent.minX, y: map.flowY)

        return ZStack(alignment: .topLeading) {
            FlowLine(from: CGPoint(x: map.youRect.maxX, y: map.flowY),
                     to: CGPoint(x: flowEnd.x - 7, y: map.flowY))
                .stroke(lineColor, lineWidth: 1.5)
                .opacity(dimmed(.you) ? 0.35 : 1)
            ArrowHead(tip: flowEnd, direction: .right)
                .fill(lineColor)
                .opacity(dimmed(.you) ? 0.35 : 1)
            Text(L("说要做什么"))
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize()
                .position(x: (map.youRect.maxX + flowEnd.x) / 2, y: map.flowY - 12)

            SupplyLine(start: skillStart, junctionY: map.junctionY,
                       end: CGPoint(x: leftLanding.x, y: leftLanding.y + 7))
                .stroke(lineColor, lineWidth: 1.5)
                .opacity(dimmed(.skill) ? 0.35 : 1)
            ArrowHead(tip: leftLanding, direction: .up)
                .fill(lineColor)
                .opacity(dimmed(.skill) ? 0.35 : 1)

            SupplyLine(start: mcpStart, junctionY: map.junctionY,
                       end: CGPoint(x: rightLanding.x, y: rightLanding.y + 7))
                .stroke(lineColor, lineWidth: 1.5)
                .opacity(dimmed(.mcp) ? 0.35 : 1)
            ArrowHead(tip: rightLanding, direction: .up)
                .fill(lineColor)
                .opacity(dimmed(.mcp) ? 0.35 : 1)
        }
    }

    /// 框的把手只有左上角标签——框覆盖了另外三个节点的全部区域，
    /// 整框可 hover 会吞掉子节点的事件
    private func boxLabel(_ map: ConceptMapGeometry) -> some View {
        let on = active == .harness
        return Button {
            toggle(.harness)
        } label: {
            HStack(spacing: Theme.Space.s4 + 1) {
                Image(systemName: ConceptLayer.harness.symbol)
                    .font(.system(size: 10, weight: .semibold))
                Text(L(ConceptLayer.harness.title))
                    .font(Theme.Fonts.caption)
            }
            .foregroundStyle(on ? Theme.accent : Theme.textSecondary)
            .padding(.horizontal, Theme.Space.s8)
            .frame(height: 22)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .fill(on ? Theme.accent.opacity(dark ? 0.20 : 0.12) : Color.primary.opacity(0.05))
            }
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { hovered = .harness } else if hovered == .harness { hovered = nil }
        }
        // 用 offset 不用 position：position 要预知控件宽度，而标签宽度随语言变化
        // （英/日/韩译文长度不同），写死宽度会在非中文界面下错位
        .offset(x: map.boxRect.minX + 12, y: map.boxRect.minY + 12)
        .help(L("Agent 应用：承载 Agent 的客户端，工程圈叫 Harness"))
        .accessibilityLabel(L(ConceptLayer.harness.title))
        .accessibilityHint(L("查看这一层的解释"))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func node(_ layer: ConceptLayer, in map: ConceptMapGeometry) -> some View {
        let rect = map.rect(for: layer)
        let on = active == layer
        return Button {
            toggle(layer)
        } label: {
            VStack(alignment: .leading, spacing: Theme.Space.s4) {
                HStack(spacing: 6) {
                    Image(systemName: layer.symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(on ? Theme.accent : Theme.textSecondary)
                    Text(L(layer.title))
                        .font(Theme.Fonts.rowTitle)
                        .foregroundStyle(on ? Theme.accent : Theme.textPrimary)
                }
                Text(L(layer.caption))
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Space.s12)
            .padding(.vertical, Theme.Space.s8 + 2)
            .frame(width: rect.width, height: rect.height, alignment: .topLeading)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                    .fill(on ? Theme.accent.opacity(dark ? 0.20 : 0.12) : Color.primary.opacity(0.04))
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                    .strokeBorder(
                        on ? Theme.accent.opacity(dark ? 0.45 : 0.32) : Color.primary.opacity(0.08),
                        lineWidth: on ? 1 : 0.5
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { hovered = layer } else if hovered == layer { hovered = nil }
        }
        // 不做 scaleEffect：缩放会让节点与固定坐标的连线对不上
        .opacity(dimmed(layer) ? 0.5 : 1)
        .position(x: rect.midX, y: rect.midY)
        .accessibilityLabel(L(layer.title))
        .accessibilityHint(L("查看这一层的解释"))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// 有别的层激活时压暗。例外：客户端激活时框内三层不压暗——
    /// 它们正在被它框住，压暗等于否认嵌套关系。
    private func dimmed(_ layer: ConceptLayer) -> Bool {
        guard let active, active != layer else { return false }
        if active == .harness, layer != .you { return false }
        return true
    }

    private func toggle(_ layer: ConceptLayer) {
        locked = (locked == layer) ? nil : layer
    }
}

// MARK: 解释卡

struct ConceptExplainCard: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var layer: ConceptLayer?
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s8) {
            HStack(spacing: Theme.Space.s8) {
                Image(systemName: layer?.symbol ?? "hand.tap")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 20, height: 20)
                    .background {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Theme.accent.opacity(0.10))
                    }
                Text(L(layer?.title ?? "点一层看它是什么"))
                    .font(Theme.Fonts.rowTitle)
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
            }
            Text(L(layer?.detail ?? "你说话 → 客户端把话交给 Agent → Agent 按 Skill 的说明书做事，要够外部系统就走 MCP。"))
                .font(Theme.Fonts.callout)
                .lineSpacing(2)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let layer {
                Rectangle()
                    .fill(Color.primary.opacity(0.06))
                    .frame(height: 1)
                    .padding(.vertical, Theme.Space.s4)
                Text(L("在这个应用里"))
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textTertiary)
                Text(L(layer.inApp))
                    .font(Theme.Fonts.callout)
                    .lineSpacing(2)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                inAppAction(layer)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Space.s16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: compact ? nil : ConceptMapGeometry.height, alignment: .topLeading)
        .quietControl(cornerRadius: Theme.Radius.tile)
        .animation(reduceMotion ? nil : Motion.control, value: layer)
    }

    @ViewBuilder
    private func inAppAction(_ layer: ConceptLayer) -> some View {
        switch layer {
        case .you:
            Button {
                store.copyToPasteboard(GuideSample.namedPhrase)
            } label: {
                Text(L("复制调用语"))
                    .font(Theme.Fonts.calloutEmphasis)
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
            .help(L("复制教材示例，不是你库里的技能"))
        case .harness:
            Button {
                store.nav = .library
            } label: {
                Text(L("去技能库看挂载"))
                    .font(Theme.Fonts.calloutEmphasis)
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
            .help(L("列表行的平台标就是挂载开关（⌘1）"))
        case .skill:
            Button {
                store.nav = .doctor
            } label: {
                Text(L("去体检看描述"))
                    .font(Theme.Fonts.calloutEmphasis)
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
            .help(L("描述体检：丢弃风险、截断、触发词埋深（⌘2）"))
        case .agent, .mcp:
            EmptyView()
        }
    }
}

// MARK: 整节

struct GuideChainSection: View {
    @Environment(AppStore.self) private var store
    var wide: Bool
    @Binding var locked: ConceptLayer?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s16) {
            GuideSectionHead(section: .chain)
            if wide {
                HStack(alignment: .top, spacing: Theme.Space.s16) {
                    ConceptMap(locked: $locked)
                        .frame(maxWidth: 880)
                    ConceptExplainCard(layer: locked)
                        .frame(width: 280)
                }
            } else {
                VStack(alignment: .leading, spacing: Theme.Space.s12) {
                    ConceptMap(locked: $locked)
                    ConceptExplainCard(layer: locked, compact: true)
                }
            }
            landingLine
            SkillOrMCPBlock()
        }
    }

    /// 全节的落点句：读者读完图应该带走的一句话
    private var landingLine: some View {
        HStack(alignment: .top, spacing: Theme.Space.s12) {
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(Theme.accent.opacity(0.30))
                .frame(width: 2)
            Text(L("Skill 解决「不知道该怎么做」，MCP 解决「够不着」。装十个 Skill 也不会让 Agent 突然能读你的邮箱；接了邮箱 MCP 也不会让它知道你们的稿子该怎么写。"))
                .font(Theme.Fonts.rowTitle)
                .lineSpacing(2)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// 「下次该配哪个」——把抽象对照变成下次遇到任务能直接套的判断
private struct SkillOrMCPBlock: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s8) {
            Text(L("任务卡在「不知道该怎么做」→ Skill；卡在「够不着」→ MCP。"))
                .font(Theme.Fonts.rowTitle)
                .foregroundStyle(Theme.textPrimary)
            example(L("「提交信息按固定格式写，破坏性改动要单独标出来」，这是做法问题，写成 Skill。"))
            example(L("「要读我 Gmail 里那封邮件」，这是通路问题，Skill 帮不上，得配 MCP。"))
            example(L("「按模板出月报，数据从公司系统取」，两个都要：Skill 定流程和写法，MCP 负责取数。"))
            Text(L("MCP 不归本应用管，在各 Agent 应用自己的设置里配。另外，MCP server 的工具定义同样常驻上下文，和技能清单抢同一块预算。挂太多 MCP 和装太多技能，是同一类问题。"))
                .font(Theme.Fonts.caption)
                .lineSpacing(2)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Theme.Space.s4)
        }
        .padding(Theme.Space.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .quietControl(cornerRadius: Theme.Radius.tile)
    }

    // 教材举例走 GuideSample，不点名本机库里的技能。
    private func example(_ text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.s8) {
            Circle()
                .fill(Theme.accent.opacity(0.35))
                .frame(width: 4, height: 4)
                .padding(.top, 7)
            Text(text)
            .font(Theme.Fonts.callout)
            .lineSpacing(2)
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
