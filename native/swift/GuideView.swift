import SwiftUI

// MARK: - 指南页（v9 教学重做：单面板 · 六节纵向长滚动 + 顶部常驻锚点条）
//
// 目标读者：装了一堆技能、但说不清 Skill / Agent / Harness / MCP 谁是谁的人。
// 六节的顺序是教学顺序，不是功能罗列：
//   ① 上手      先跑通一次（成功体感换后面五节的注意力）
//   ② 关系      四个词一条链——嵌套关系图，不是四张并列卡
//   ③ 机制      两个时刻 + 三条推论，是后面两节的底座
//   ④ 排查      先判断「是不是真没用上」，再按顺序修；含页内实时试触发
//   ⑤ SKILL.md  把技能从黑盒变成可读可改的文本文件 + 快捷键 + 常见问题
//   ⑥ 本机数据  真实数字 + 去体检页
//
// 三条硬约束（改这个文件前先读）：
// 1. 名词定义唯一落点是关系图——每个节点自带一行副句，不点也读得到。
//    任何人为了让图「干净」删掉节点副句，这页对新手的价值当场归零。
// 2. 面板内不再叠第二块 contentSurface（L1 叠 L1），次级容器一律 quietControl。
// 3. 教材举例只用 GuideSample，不读库里的真实技能名 / 描述 / 调用语。
//    这页会进公开发布的截图；用「最常用技能」等于把作者或用户的身份写进说明书。

// MARK: - 本页排印契约（v10 重排，改这个文件前先读完这一段）
//
// 旧版塌了的地方：节标题用 secondaryEmphasis（11 次级灰），而节内条目标题用
// rowTitle（13 semibold 主色）——容器比它装的东西还轻，六节读下来没有父子感，
// 满屏等重的粗行。同时 caption（10pt，全系统最小号）在本页出现 25 次，成了
// 一个「用来读」的页面里的主力字号。
//
// 现在锁死五档，每档只有一个职责，不许串档：
//
//   节标题    panelTitle 15 semibold 主色    六个，全页最大，与其余页面的面板标题同档
//   组标题    secondaryEmphasis 11 medium 次级色   节内分组（四级证据／六步排查／常见问题）
//   节副句    secondary 11 常规 三级色       节标题下一行，一句话说这节干什么
//   条目标题  rowTitle 13 semibold 主色      组里的单条
//   正文      callout 12 常规 次级色         所有拿来读的散文，只此一档
//   注解      caption 10 medium 三级色       单位、计数、旁注，不承载句子
//
// 两条推论：
// 1. 正文以前一半 11、一半 13（同一种东西两个字号），现在统一 12。11 退回它本来的
//    身份（元数据），13 只留给「内容本身」——可复制的调用语、输入框、FAQ 问句。
// 2. DESIGN.md 第 311 行禁的是「孤立粗体页标题」，指内容面板顶上再放一个大标题去
//    重复工具条里的页名。它管的不是长滚动文档里的分节标题；把它套到这里，才是本页
//    没有任何 15pt 文字的原因。第 81 行写得很清楚：panelTitle = 面板标题。

/// 指南页唯一允许出现的技能身份。不从本机库取名。
enum GuideSample {
    static let name = "weekly-notes"
    static let directory = "weekly-notes"
    static let category = "演示与文档"
    static let description = "当用户说「写周报」「整理本周进展」时使用。按固定结构输出本周完成、风险和下周计划。"
    static let namedPhrase = "请使用 weekly-notes：把这周的会议记录整理成一页周报"
    static let autoPhrase = "把这周的会议记录整理成一页周报"
}

/// 试触发等活工具仍读本机库，但命中作者身份词的技能不进指南页。
enum GuidePrivacy {
    static let blocked = [
        "寿楠", "永赢", "永贏", "永赢基金",
        "shounan", "yongying", "jung8",
    ]

    static func isPersonal(_ skill: Skill) -> Bool {
        let hay = "\(skill.name) \(skill.directory) \(skill.description) \(skill.whenToUse)"
        return blocked.contains { hay.localizedCaseInsensitiveContains($0) }
    }

    static func publicSkills(from skills: [Skill]) -> [Skill] {
        skills.filter { !isPersonal($0) }
    }
}

enum GuideMetrics {
    /// 正文行宽上限。中文 12pt 约 12pt/字，640 ≈ 一行 50 字上下，落在舒适区间。
    /// 旧版 700／760／320／不限 四种口径混用，宽窗下 11pt 中文能跑到一行 130 字。
    static let measure: CGFloat = 640
    /// 节与节的间距，分隔线上下各留这么多，同一个常量同时喂给外层 VStack 与节头，
    /// 否则线会偏上或偏下。必须显著大于节内间距（12／16），否则六节糊成一片。
    static let sectionGap: CGFloat = Theme.Space.s24
}

enum GuideSection: String, CaseIterable, Identifiable, Hashable {
    case start, chain, mechanism, triage, skillmd, local

    var id: String { rawValue }

    /// 锚点条上的短标签
    var tab: String {
        switch self {
        case .start: return "上手"
        case .chain: return "关系"
        case .mechanism: return "机制"
        case .triage: return "排查"
        case .skillmd: return "SKILL.md"
        case .local: return "本机数据"
        }
    }

    var title: String {
        switch self {
        case .start: return "三步把技能用起来"
        case .chain: return "四个词，一条链"
        case .mechanism: return "它是怎么被看见、又怎么被读进去的"
        case .triage: return "用上了没有，没用上怎么办"
        case .skillmd: return "SKILL.md 长什么样"
        case .local: return "你现在的实况"
        }
    }

    var note: String {
        switch self {
        case .start: return "先跑通一次，再看后面的解释"
        case .chain: return "点一层看它是什么"
        case .mechanism: return "后面几节都是这两件事的推论"
        case .triage: return "先判断，再修"
        case .skillmd: return "一个文件夹，一个文本文件"
        case .local: return "数字与体检页同源"
        }
    }
}

/// 节头在滚动坐标系里的位置（锚点条反查当前节用）
private struct GuideOffsetKey: PreferenceKey {
    static var defaultValue: [GuideSection: CGFloat] { [:] }
    static func reduce(value: inout [GuideSection: CGFloat], nextValue: () -> [GuideSection: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// 面板可用宽（决定关系图/三步/数据带是否走宽窗布局）
private struct GuideWidthKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// 滚动体末尾哨兵的位置：最后一节只有约 130pt 高，滚到底时它的 minY 仍然
/// 大于「已滚过顶部」的阈值，单靠 minY 反查会导致最后一个锚点永远点不亮
private struct GuideSentinelKey: PreferenceKey {
    static var defaultValue: CGFloat { .infinity }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = min(value, nextValue())
    }
}

struct GuidePage: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var current: GuideSection = .start
    @State private var lockedLayer: ConceptLayer?
    @State private var contentWidth: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0
    @State private var sentinelY: CGFloat = .infinity

    /// 880 以下把「图 + 解释卡」「步骤 + 例子卡」「数据带」全部降级为竖排
    private var wide: Bool { contentWidth >= 880 }

    var body: some View {
        VStack(spacing: 0) {
            GuideAnchorBar(current: current) { section in
                jump(to: section)
            }
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 1)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: GuideMetrics.sectionGap) {
                        GuideStartSection(wide: wide) { jump(to: $0) }
                            .guideAnchor(.start)
                        GuideChainSection(wide: wide, locked: $lockedLayer)
                            .guideAnchor(.chain)
                        GuideMechanismSection { jump(to: $0) }
                            .guideAnchor(.mechanism)
                        GuideTriageSection { jump(to: $0) }
                            .guideAnchor(.triage)
                        GuideSkillFileSection(wide: wide)
                            .guideAnchor(.skillmd)
                        GuideLocalSection()
                            .guideAnchor(.local)
                        // sentinel：滚到底时强制点亮最后一节
                        Color.clear
                            .frame(height: Theme.Space.s24)
                            .background {
                                GeometryReader { geo in
                                    Color.clear.preference(
                                        key: GuideSentinelKey.self,
                                        value: geo.frame(in: .named("guideScroll")).minY
                                    )
                                }
                            }
                    }
                    // maxWidth: .infinity 必须有：否则 VStack 宽度取决于最宽的子视图，
                    // 而子视图布局又取决于测出来的宽度（wide 分支），会形成
                    // 测宽 → 换布局 → 宽度变 → 再换 的抖动
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.Space.s20)
                    .padding(.top, Theme.Space.s16)
                    .background {
                        GeometryReader { geo in
                            Color.clear.preference(key: GuideWidthKey.self, value: geo.size.width)
                        }
                    }
                }
                .coordinateSpace(name: "guideScroll")
                .panelScroll()
                .background {
                    GeometryReader { geo in
                        Color.clear
                            .onAppear { viewportHeight = geo.size.height }
                            .onChange(of: geo.size.height) { _, new in viewportHeight = new }
                    }
                }
                .onPreferenceChange(GuideWidthKey.self) { contentWidth = $0 }
                .onPreferenceChange(GuideSentinelKey.self) { sentinelY = $0 }
                .onPreferenceChange(GuideOffsetKey.self) { offsets in
                    updateCurrent(from: offsets)
                }
                .onChange(of: jumpRequest) { _, section in
                    guard let section else { return }
                    if reduceMotion {
                        proxy.scrollTo(section.rawValue, anchor: .top)
                    } else {
                        withAnimation(Motion.standard) {
                            proxy.scrollTo(section.rawValue, anchor: .top)
                        }
                    }
                    current = section
                    jumpRequest = nil
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentSurface()
    }

    @State private var jumpRequest: GuideSection?

    private func jump(to section: GuideSection) {
        // 从正文 inline 按钮跳到关系图时顺带点亮对应层
        jumpRequest = section
    }

    /// 反查当前节：取最后一个已滚过顶部 40pt 的节。
    /// 已滚到底时直接点亮最后一节——否则最后一节太矮，永远满足不了阈值。
    private func updateCurrent(from offsets: [GuideSection: CGFloat]) {
        let next: GuideSection
        if viewportHeight > 0, sentinelY <= viewportHeight + 8 {
            next = .local
        } else {
            next = GuideSection.allCases.last { (offsets[$0] ?? .infinity) <= 40 } ?? .start
        }
        guard next != current else { return }
        current = next
    }
}

private extension View {
    /// 给一节挂锚点 id 与几何上报
    func guideAnchor(_ section: GuideSection) -> some View {
        self
            .id(section.rawValue)
            .background {
                GeometryReader { geo in
                    Color.clear.preference(
                        key: GuideOffsetKey.self,
                        value: [section: geo.frame(in: .named("guideScroll")).minY]
                    )
                }
            }
    }
}

// MARK: - 锚点条（借 FavoritesTabs 的语法：quietControl 外框 + 白滑块）
//
// 刻意不用 accent 填充——accent 选中态是侧栏一级导航的专属语法，
// 借过来会和一级导航打架，用户会分不清自己切的是哪一层。

private struct GuideAnchorBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var anchorSpace
    var current: GuideSection
    var jump: (GuideSection) -> Void

    var body: some View {
        HStack(spacing: Theme.Space.s8) {
            HStack(spacing: 2) {
                ForEach(GuideSection.allCases) { section in
                    tab(section)
                }
            }
            .padding(2)
            .quietControl()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Space.s20)
        .padding(.top, Theme.Space.s16)
        .padding(.bottom, Theme.Space.s12)
        .animation(reduceMotion ? nil : Motion.control, value: current)
    }

    private func tab(_ section: GuideSection) -> some View {
        let active = current == section
        return Button {
            jump(section)
        } label: {
            Text(L(section.tab))
                .font(active ? Theme.Fonts.calloutEmphasis : Theme.Fonts.callout)
                .foregroundStyle(active ? Theme.textPrimary : Theme.textSecondary)
                .padding(.horizontal, Theme.Space.s12)
                .frame(height: 24)
                .background {
                    if active {
                        // 同心圆角：外 8 − 内缩 2 = 6
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(.background)
                            .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                            .matchedGeometryEffect(id: "guide-anchor", in: anchorSpace)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(LF("跳到「%@」", L(section.title)))
    }
}

// MARK: - 共用节头（全页最大一档，不吸顶）
//
// 标题 15 semibold 主色 + 副句 11 三级色纵向堆叠，上面压一条发丝分隔。
// 三件事同时在做：把节抬到条目之上（旧版倒挂）、把副句从并排挪到标题下
// （并排时它和标题争一行，读者要横着扫两个不同字号）、用分隔线给六节断句。
// 首节不画线——面板顶边已经是一条线，再画一条是重影。

struct GuideSectionHead: View {
    var section: GuideSection
    var help: String?
    /// 首节不画上分隔线
    var first = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !first {
                Rectangle()
                    .fill(Color.primary.opacity(0.07))
                    .frame(height: 1)
                    .padding(.bottom, GuideMetrics.sectionGap)
            }
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s8) {
                Text(L(section.title))
                    .font(Theme.Fonts.panelTitle)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let help {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                        .help(L(help))
                }
                Spacer(minLength: 0)
            }
            Text(L(section.note))
                .font(Theme.Fonts.secondary)
                .foregroundStyle(Theme.textTertiary)
                .padding(.top, 3)
        }
    }
}

// MARK: - 节内分组：一个组标题 + 一块发丝分隔的列表
//
// 旧版把每一条都包成独立的 quietControl 药丸，③④⑤ 加起来 14 个几乎一样的圆角块
// 竖着堆——这是「乱糟糟」的主要来源。改成 macOS 分组列表的原生写法：一个容器，
// 条目之间画发丝，不给每条各画一个框。同时组标题从 caption 10 三级色升到
// secondaryEmphasis 11 次级色——旧版它和节副句完全同款，读者分不清哪个是节、哪个是组。

private struct GuideGroup<Content: View>: View {
    var label: String?
    var note: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s8) {
            if label != nil || note != nil {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s8) {
                    if let label {
                        Text(L(label))
                            .font(Theme.Fonts.secondaryEmphasis)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    if let note {
                        Text(L(note))
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    Spacer(minLength: 0)
                }
            }
            VStack(spacing: 0) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
            .quietControl(cornerRadius: Theme.Radius.tile)
        }
    }
}

/// 分组列表里的条目间发丝。首条之前不画。
private struct GuideHairline: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.06))
            .frame(height: 1)
            .padding(.leading, Theme.Space.s12)
    }
}

/// 小动作按钮（安静样式，高 24）
/// 标签用 11 medium 不用 10：正文已经抬到 12，10pt 的按钮在旁边读起来像脚注，
/// 而它是这一页最主要的动作出口（去技能库、去体检、复制调用语都走它）。
private struct GuideActionButton: View {
    var title: String
    var help: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(L(title))
                .font(Theme.Fonts.secondaryEmphasis)
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, Theme.Space.s8 + 2)
                .frame(height: 24)
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .quietControl(cornerRadius: 6)
        .help(L(help))
    }
}

// MARK: - ① 三步把技能用起来

private struct GuideStartSection: View {
    @Environment(AppStore.self) private var store
    var wide: Bool
    var jump: (GuideSection) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s16) {
            GuideSectionHead(section: .start, first: true)
            if wide {
                HStack(alignment: .top, spacing: Theme.Space.s16) {
                    steps
                    FeaturedExample()
                        .frame(width: 360)
                        .padding(.top, 40)
                }
            } else {
                VStack(alignment: .leading, spacing: Theme.Space.s16) {
                    steps
                    FeaturedExample()
                }
            }
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepBlock(index: 1, title: "挑一个技能", detail: firstStepDetail) {
                AnyView(
                    GuideActionButton(title: "在技能库里搜", help: "打开技能库并聚焦搜索框（⌘K）") {
                        store.searchFocusRequest += 1
                    }
                )
            }
            StepBlock(
                index: 2,
                title: "复制调用语",
                detail: wide
                    ? "列表行悬停、详情页、菜单栏 ⌥⌘K 回车，都能一键复制。右边是一句教材示例，不是你库里的技能。"
                    : "列表行悬停、详情页、菜单栏 ⌥⌘K 回车，都能一键复制。下面是一句教材示例，不是你库里的技能。"
            ) {
                AnyView(EmptyView())
            }
            StepBlock(
                index: 3,
                title: "贴进 Agent 对话框",
                detail: "两种写法都行，区别只是稳不稳：",
                last: true
            ) {
                AnyView(thirdStepContent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 不举 pptx 为例：官方明确 PowerPoint/Excel/Word/PDF 四个内置技能在
    /// Claude Code 里不可用，举它会让读者以为自己的 Claude Code 自带。
    private var firstStepDetail: String {
        L("在技能库选中想用的；不确定用哪个就 ⌘K 直接搜任务本身，不用记技能叫什么。")
    }

    @ViewBuilder
    private var thirdStepContent: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s8) {
            phraseRow(label: "点名（最稳）", text: GuideSample.namedPhrase)
            phraseRow(label: "不点名（靠它自己认）", text: GuideSample.autoPhrase)
            // 跳转不做成行内文字链：整段挂 onTapGesture 会把三句话都变成点击热区，
            // 用户点任何一处都会被弹走；按钮与本文件其他跳转（inference / triageRow）同构
            HStack(alignment: .top, spacing: Theme.Space.s8) {
                Text(L("库里技能少的时候不点名也行。到了几十个，点名更稳，原因在下一节。Claude Code 里还可以直接打 /技能名，这是最确定的一种，因为清单永远保留每个技能的名字。"))
                    .font(Theme.Fonts.callout)
                    .lineSpacing(2)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Theme.Space.s4)
                GuideActionButton(title: "看机制那节", help: "跳到「它是怎么被看见、又怎么被读进去的」") {
                    jump(.mechanism)
                }
                .padding(.top, 1)
            }

            Text(L("技能挂到哪个客户端，哪个才能用。实体只有一份在本库里，各平台目录放的是指向它的软链，不是各装一份。各客户端对技能标准的支持程度不同，装上之后以实际能不能触发为准。"))
                .font(Theme.Fonts.callout)
                .lineSpacing(2)
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, Theme.Space.s4)
            platformRow
        }
    }

    private func phraseRow(label: String, text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.s8) {
            Text(L(label))
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 108, alignment: .leading)
                .padding(.top, 3)
            Text(text)
                .font(Theme.Fonts.body)
                .lineSpacing(2)
                .foregroundStyle(Theme.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            CopyIconButton(text: text, help: L("复制这句"))
        }
        .padding(.horizontal, Theme.Space.s12)
        .padding(.vertical, Theme.Space.s8)
        .quietControl(cornerRadius: Theme.Radius.row)
    }

    private var platformRow: some View {
        HStack(spacing: Theme.Space.s8) {
            ForEach(store.visiblePlatforms) { platform in
                HStack(spacing: Theme.Space.s4 + 1) {
                    PlatformLogo(platform: platform, size: 18)
                    Text(platform.displayName)
                        .font(Theme.Fonts.callout)
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
                    .font(Theme.Fonts.callout)
                    .lineSpacing(2)
                    .foregroundStyle(Theme.textSecondary)
                content()
            }
            .padding(.bottom, last ? 0 : Theme.Space.s20)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// 教材示例：固定中性技能，不读本机库。
private struct FeaturedExample: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var copied = false

    var body: some View {
        if store.skills.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.s8) {
                Text(L("库里还没有技能，先去安装一个。"))
                    .font(Theme.Fonts.callout)
                    .foregroundStyle(Theme.textTertiary)
                GuideActionButton(title: "安装技能", help: "粘贴 GitHub 链接或选择本地文件夹（⌘N）") {
                    store.installSheetPresented = true
                }
            }
            .padding(Theme.Space.s12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .quietControl(cornerRadius: Theme.Radius.tile)
        } else {
            VStack(alignment: .leading, spacing: Theme.Space.s8 + 2) {
                HStack(spacing: Theme.Space.s8 + 2) {
                    CategoryIcon(category: GuideSample.category, size: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(GuideSample.name)
                            .font(Theme.Fonts.rowTitle)
                            .foregroundStyle(Theme.textPrimary)
                        Text(L("教材示例，不是你库里的技能"))
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    Spacer()
                }
                Text(GuideSample.namedPhrase)
                    .font(Theme.Fonts.callout)
                    .lineSpacing(2)
                    .foregroundStyle(Theme.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.Space.s12)
                    .quietControl(cornerRadius: Theme.Radius.row)
                Button {
                    store.copyToPasteboard(GuideSample.namedPhrase)
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
        }
    }
}

// MARK: - ③ 它是怎么被看见、又怎么被读进去的
//
// 这一节是全页的机制底座。不讲这两个时刻，后面「怎么验证」「为什么不触发」
// 「装多了会怎样」每一条都是要背的规则；讲了，后面全是推论。

private struct GuideMechanismSection: View {
    @Environment(AppStore.self) private var store
    var jump: (GuideSection) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s16) {
            GuideSectionHead(
                section: .mechanism,
                help: "本页与体检页的预算数字按 token 估算。官方文档对这块预算的单位说法不一致：技能文档写的是「清单的字符预算」，设置文档写的是「上下文窗口的比例」。中文技能在两种口径下能差约 4 倍。所以这些数字只用来横向比较，别当绝对值。"
            )
            HStack(alignment: .top, spacing: Theme.Space.s12) {
                moment(
                    title: "时刻一 · 开会话时",
                    body: "客户端把库里每个技能的 name 和 description 拼成一份清单，随 system prompt 一起注入。此刻 Agent 只知道有哪些技能、各自能干什么，没读过任何一份正文。"
                )
                moment(
                    title: "时刻二 · 决定要用时",
                    body: "Agent 判断某个技能相关，才去读它的 SKILL.md 全文，然后照着里面的流程执行。附带的参考文件被引用才读。脚本由 bash 执行，代码本身不进上下文，只有输出进。所以捆再多参考文件也不额外花预算，只要没被读到。"
                )
            }
            GuideGroup(label: "三条推论", note: "都是上面两个时刻推出来的") {
                inference(
                    symbol: "arrow.triangle.branch",
                    title: "描述决定「会不会被想起」，正文决定「做得对不对」。",
                    body: "这是两件事，分开优化：技能不触发去改描述，触发了但做得不对去改正文。",
                    action: nil
                )
                GuideHairline()
            // 120 / 1090 两个数由 ContextDoctor.tokenEstimate（CJK×0.7 + 其余÷4，
            // 每条再 +15 开销）与 budgetTokens = 窗口/100 反算，默认 200k 窗口 → 2000。
            // 估算器对语种敏感（同样 1536 字符若是纯 ASCII 只有约 399 token），所以
            // 文案必须写明「中文描述」。改算法要同步改这里——否则本页会和 ⑥ 本机数据、
            // 体检页在同一屏里互相打脸（这正是旧文案「50 个 / 6 个」被删的原因）。
                inference(
                    symbol: "chart.pie",
                    title: "清单有预算。超了不会报错，会丢描述。",
                    body: "客户端只给技能清单留大约 1% 的上下文额度，默认 200k 窗口约合 2000 token。超了之后，它从你调用得最少的技能开始，把那条描述整条删掉，只留名字。技能还在，点名照样能用，模型只是不再知道它能干什么，于是不会自己想起它。所以真正的上限不在技能数量，在描述文本的总量：一条 150 字的中文描述约 120 token，十几条就把 2000 占满；一条写满 1536 字符的中文描述约 1090 token，两条就爆。该砍的是描述长度。",
                    action: ("看我现在的占用", "跳到本机数据，看你库里的实际占用", { jump(.local) })
                )
                GuideHairline()
                inference(
                    symbol: "ruler",
                    title: "单条描述有两道线。",
                    body: "Claude Code 把描述截断在 1536 字符，Agent Skills 开放标准规定的上限却是 1024 字符。写在这两者之间，本地能跑，但上传 claude.ai、走 Skills API 或用官方打包脚本时会校验失败。另外，社区实测真正起作用的触发词得落在描述前 250 字符里，埋在后面等于没写。",
                    action: nil
                )
            }
            Text(L("所以已经开着的会话不会中途多出一个技能，它手里那份清单是开会话那一刻定的。改完描述，要开新会话才生效。"))
                .font(Theme.Fonts.callout)
                .lineSpacing(2)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func moment(title: String, body text: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s4 + 2) {
            Text(L(title))
                .font(Theme.Fonts.rowTitle)
                .foregroundStyle(Theme.textPrimary)
            Text(L(text))
                .font(Theme.Fonts.callout)
                .lineSpacing(2)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Theme.Space.s12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .quietControl(cornerRadius: Theme.Radius.tile)
    }

    private func inference(
        symbol: String,
        title: String,
        body text: String,
        action: (String, String, () -> Void)?
    ) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.s12) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 20, height: 20)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Theme.accent.opacity(0.10))
                }
            VStack(alignment: .leading, spacing: Theme.Space.s4) {
                Text(L(title))
                    .font(Theme.Fonts.rowTitle)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(L(text))
                    .font(Theme.Fonts.callout)
                    .lineSpacing(2)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: GuideMetrics.measure, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Theme.Space.s8)
            if let action {
                GuideActionButton(title: action.0, help: action.1, action: action.2)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, Theme.Space.s12)
        .padding(.vertical, Theme.Space.s12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - ④ 用上了没有，没用上怎么办
//
// 顺序不能反：先给证据判断「是不是真没用上」，再给排查清单。
// 反过来读者会跑去修一个其实正常的东西。

private struct GuideTriageSection: View {
    @Environment(AppStore.self) private var store
    var jump: (GuideSection) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s16) {
            GuideSectionHead(section: .triage)
            evidenceBlock
            GuideGroup(label: "当场试一句", note: "按你平时会说的话打，看谁会抢答") {
                TriggerTryout()
            }
            triageBlock
            Text(L("试触发和体检都是离线近似。真实匹配是模型的语义判断，本应用能做的，是把明显不可能被看见的情况先排掉。"))
                .font(Theme.Fonts.callout)
                .lineSpacing(2)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 四级证据

    private var evidenceBlock: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s8) {
            GuideGroup(label: "四级证据，从弱到强") {
                evidence(
                    index: 1,
                    title: "模型说「我将使用 X」",
                    detail: "不算证据。它可能只是在复述你的话。",
                    trailing: nil
                )
                GuideHairline()
                evidence(
                    index: 2,
                    title: "输出结构对得上 SKILL.md 里的模板",
                    detail: "弱证据，但肉眼可查。结构对不上，多半没读到正文。",
                    trailing: AnyView(GuideActionButton(title: "去技能库看一份", help: "打开技能库，点选任意技能后可在详情里读 SKILL.md") {
                        store.nav = .library
                    })
                )
                GuideHairline()
                evidence(
                    index: 3,
                    title: "会话日志里出现了技能目录的路径引用",
                    detail: "硬证据，也是本应用统计使用次数的口径：扫 Claude 与 Codex 的会话记录，同一会话内同一技能只算一次。",
                    trailing: AnyView(
                        Text(LF("已统计到 %d 个技能用过", store.usedSkillCount))
                            .font(Theme.Fonts.caption)
                            .monospacedDigit()
                            .foregroundStyle(Theme.textTertiary)
                            .help(store.usageIndexInfo.isEmpty ? L("扫描本机会话日志得到") : store.usageIndexInfo)
                    )
                )
                GuideHairline()
                evidence(
                    index: 4,
                    title: "Hook 实时遥测",
                    detail: "唯一不靠事后翻日志的口径。设置页一键接入后，Claude Code 每次真正调用技能都会记一行。想要准的，开它。",
                    trailing: hookTrailing
                )
            }
            Text(L("Codex 会把全部技能目录内嵌进它的指令里，所以技能出现在上下文里，不等于真的用了。本应用只认真正的调用记录。有些技能你觉得天天在用、统计却是 0，多半就是这个原因。"))
                .font(Theme.Fonts.callout)
                .lineSpacing(2)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, Theme.Space.s12)
        }
    }

    private var hookTrailing: AnyView {
        if HookTelemetry.installed() {
            return AnyView(
                Text(LF("已接入 · %d 条事件", HookTelemetry.totalEvents))
                    .font(Theme.Fonts.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.healthy)
            )
        }
        return AnyView(
            GuideActionButton(title: "去设置页接入", help: "设置页「Hook 实时遥测」一键接入（⌘4）") {
                store.nav = .settings
            }
        )
    }

    private func evidence(index: Int, title: String, detail: String, trailing: AnyView?) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.s8) {
            Text("\(index)")
                .font(Theme.Fonts.caption)
                .monospacedDigit()
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 16, alignment: .leading)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(L(title))
                    .font(Theme.Fonts.rowTitle)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(L(detail))
                    .font(Theme.Fonts.callout)
                    .lineSpacing(2)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: GuideMetrics.measure, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Theme.Space.s8)
            trailing
        }
        .padding(.horizontal, Theme.Space.s12)
        .padding(.vertical, Theme.Space.s12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 六步排查

    private var triageBlock: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s8) {
            GuideGroup(label: "它没理你，按这个顺序查") {
                triageRow(
                    index: 1,
                    question: "挂上了吗？",
                    detail: L("列表行那个平台标是不是点亮的。技能挂在 Claude Code 上，你在 Codex 里说话，它当然不理。挂载出问题（断链 / 目标错误 / 普通目录）会在体检页「需要修复」里。"),
                    button: ("去技能库看挂载", "打开技能库（⌘1）", { store.nav = .library })
                )
                GuideHairline()
                triageRow(
                    index: 2,
                    question: "是不是停用了？",
                    detail: L("灰显 = 已停用，它根本没进清单。"),
                    button: ("筛出已停用", "在技能库里只看已停用的技能", {
                        store.clearFilters()
                        store.stateFilter = "已停用"
                        store.nav = .library
                    })
                )
                GuideHairline()
                triageRow(
                    index: 3,
                    question: "描述被丢弃了吗？",
                    detail: droppedDetail,
                    button: ("去体检看丢弃名单", "体检页的预算模拟（⌘2）", { store.nav = .doctor })
                )
                GuideHairline()
                triageRow(
                    index: 4,
                    question: "触发词埋太深？",
                    detail: L("你会说的那句话，在描述的前 250 字符里吗？体检页「触发词埋太深」会列出来，行尾「开药」能把含「」触发词的句子前置。只重排句子，一个字不增删，采纳前有前后对照。"),
                    button: ("去体检 · 描述体检", "描述体检：丢弃风险、截断、埋深（⌘2）", { store.nav = .doctor })
                )
                GuideHairline()
                triageRow(
                    index: 5,
                    question: "被同类抢走了？",
                    detail: overlapDetail,
                    button: nil
                )
                GuideHairline()
                triageRow(
                    index: 6,
                    question: "上面都对，还是不理？",
                    detail: L("直接点名：复制调用语，或者在 Claude Code 里直接打 /技能名。自动匹配是模型的语义判断，技能一多就不保准；点名没有歧义，而且清单永远保留每个技能的名字。"),
                    button: ("复制点名调用语", L("复制教材示例：") + GuideSample.namedPhrase, {
                        store.copyToPasteboard(GuideSample.namedPhrase)
                    })
                )
            }
        }
    }

    private var droppedDetail: String {
        let base = L("清单超预算时，用得最少的先被丢。这类技能你点名它照样能用，但它永远不会自己冒出来。")
        let report = store.doctorReport
        if report.overBudget {
            return base + LF("你现在有 %d 个技能在丢弃名单里。", report.atRisk.count)
        }
        return base + L("你现在预算还够。")
    }

    private var overlapDetail: String {
        let base = L("两个技能的触发词撞车时，模型可能挑错人。上面那个输入框就是干这个的：把你打算说的话打进去，看排第一的是谁。")
        if store.triggerOverlaps.isEmpty { return base }
        return base + LF("体检页已经检出 %d 对触发词重叠。", store.triggerOverlaps.count)
    }

    private func triageRow(
        index: Int,
        question: String,
        detail: String,
        button: (String, String, () -> Void)?
    ) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.s8) {
            Text("\(index)")
                .font(Theme.Fonts.caption)
                .monospacedDigit()
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 16, alignment: .leading)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(L(question))
                    .font(Theme.Fonts.rowTitle)
                    .foregroundStyle(Theme.textPrimary)
                Text(detail)
                    .font(Theme.Fonts.callout)
                    .lineSpacing(2)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: GuideMetrics.measure, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Theme.Space.s8)
            if let button {
                GuideActionButton(title: button.0, help: button.1, action: button.2)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, Theme.Space.s12)
        .padding(.vertical, Theme.Space.s12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 页内实时试触发：把这一页最抽象的那件事（谁会被叫醒）变成当场能试的东西。
/// 走的是菜单栏「试触发」同一套 TriggerLab 口径，只是搬到教学现场。
private struct TriggerTryout: View {
    @Environment(AppStore.self) private var store
    @State private var phrase = ""

    private var atRiskNames: Set<String> {
        Set(store.doctorReport.atRisk.map(\.skill.name))
    }

    private var results: [TriggerCandidate] {
        let query = phrase.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }
        return Array(
            TriggerLab.simulate(
                phrase: query,
                skills: GuidePrivacy.publicSkills(from: store.skills),
                usage: store.usage,
                atRiskNames: atRiskNames
            ).prefix(3)
        )
    }

    var body: some View {
        // 算一次就好：body 里多处引用会把 simulate 在 145 个技能上重复跑
        let ranked = results
        return VStack(alignment: .leading, spacing: Theme.Space.s8) {
            HStack(spacing: Theme.Space.s8) {
                Image(systemName: "text.bubble")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
                TextField(L("比如：帮我把这份会议记录整理成纪要"), text: $phrase)
                    .textFieldStyle(.plain)
                    .font(Theme.Fonts.callout)
                if !phrase.isEmpty {
                    Button {
                        phrase = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .help(L("清空"))
                }
            }
            .padding(.horizontal, Theme.Space.s12)
            .frame(height: 32)
            .quietControl(cornerRadius: Theme.Radius.row)

            if ranked.isEmpty {
                Text(L("这里用的是和菜单栏「试触发」同一套离线口径：只按名字与描述里的触发词算，不联网、不调用模型。"))
                    .font(Theme.Fonts.callout)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 2) {
                    ForEach(Array(ranked.enumerated()), id: \.element.id) { index, candidate in
                        resultRow(rank: index + 1, candidate: candidate)
                    }
                }
            }
        }
        .padding(Theme.Space.s12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func resultRow(rank: Int, candidate: TriggerCandidate) -> some View {
        HStack(spacing: Theme.Space.s8) {
            Text("\(rank)")
                .font(Theme.Fonts.caption)
                .monospacedDigit()
                .foregroundStyle(rank == 1 ? Theme.accent : Theme.textTertiary)
                .frame(width: 14)
            CategoryIcon(category: candidate.skill.category, size: 18, style: .quiet)
            Text(candidate.skill.name)
                .font(Theme.Fonts.calloutEmphasis)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            if !candidate.matched.isEmpty {
                Text(candidate.matched.prefix(3).joined(separator: " · "))
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: Theme.Space.s4)
            if candidate.atRisk {
                badge(L("描述可能被丢"), tint: Theme.warning)
            }
            if !candidate.buried.isEmpty {
                badge(L("触发词埋太深"), tint: Theme.warning)
            }
            Button {
                store.select(candidate.skill.name)
                store.nav = .library
            } label: {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(LF("在技能库里查看 %@", candidate.skill.name))
        }
        .padding(.horizontal, Theme.Space.s8)
        .padding(.vertical, Theme.Space.s4 + 1)
    }

    private func badge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(Theme.Fonts.caption)
            .foregroundStyle(tint)
            .padding(.horizontal, Theme.Space.s4 + 2)
            .frame(height: 18)
            .quietControl(cornerRadius: 6, tint: tint)
    }
}

// MARK: - ⑤ SKILL.md 长什么样（+ 快捷键 + 常见问题）

private struct GuideSkillFileSection: View {
    @Environment(AppStore.self) private var store
    var wide: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s16) {
            GuideSectionHead(section: .skillmd)
            if wide {
                HStack(alignment: .top, spacing: Theme.Space.s16) {
                    skeleton
                    notes.frame(width: 360)
                }
            } else {
                VStack(alignment: .leading, spacing: Theme.Space.s12) {
                    skeleton
                    notes
                }
            }
            writeYourOwn
            shortcuts
            GuideFAQ()
        }
    }

    /// 骨架只用教材示例。YAML 字段名保持字面量，属于语法不是文案。
    private var skeletonText: String {
        let body = L("# 正文：流程、模板、红线、示例")
        return "---\nname: \(GuideSample.directory)\n"
            + "description: \(GuideSample.description)\n"
            + "---\n\n\(body)"
    }

    private var skeleton: some View {
        Text(skeletonText)
            .font(Theme.Fonts.mono)
            .lineSpacing(3)
            .foregroundStyle(Theme.textSecondary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Space.s12)
            .quietControl(cornerRadius: Theme.Radius.row)
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s8) {
            note("--- 之间叫 frontmatter。", "标准只认六个字段：name、description、license、compatibility、metadata、allowed-tools。本应用读 name 和 description；name 必须和文件夹名一致，使用统计是按目录名认的。")
            note("description 是唯一会被无条件注入清单的部分。", "写「什么时候该用我」比写「我多能干」有用。把用户会说的原话用「」括起来放前面，本应用的试触发和开药都认这个信号。")
            note("正文长没关系。", "正文只在被调用那一刻才读，不占开会话时的清单预算。")
        }
    }

    private func note(_ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.s8) {
            Circle()
                .fill(Theme.accent.opacity(0.35))
                .frame(width: 4, height: 4)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(L(title))
                    .font(Theme.Fonts.secondaryEmphasis)
                    .foregroundStyle(Theme.textPrimary)
                Text(L(body))
                    .font(Theme.Fonts.callout)
                    .lineSpacing(2)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var writeYourOwn: some View {
        HStack(alignment: .top, spacing: Theme.Space.s8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L("自己写一个"))
                    .font(Theme.Fonts.rowTitle)
                    .foregroundStyle(Theme.textPrimary)
                Text(L("最小可用 = 一个文件夹 + 一个 SKILL.md。放进本库的 skills 目录，按 ⌘R 重扫，再点亮要挂的平台。"))
                    .font(Theme.Fonts.callout)
                    .lineSpacing(2)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Theme.Space.s8)
            // help 里不能直出绝对路径：/Users/<用户名>/ 会把本机账号名暴露在气泡和截图里
            GuideActionButton(title: "打开技能库目录", help: (AtlasPaths.libraryRoot.path as NSString).abbreviatingWithTildeInPath) {
                store.openFolder(AtlasPaths.libraryRoot.path)
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, Theme.Space.s12)
        .padding(.vertical, Theme.Space.s8 + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .quietControl(cornerRadius: Theme.Radius.row)
    }

    private var shortcuts: some View {
        GuideGroup(label: "三个随手能用的键") {
            shortcut("⌘K", "在技能库里搜。可以直接搜任务本身，不用记技能叫什么。")
            GuideHairline()
            shortcut("⌥⌘K", "在任何应用里呼出快速搜索：回车发起会话，⌥回车复制调用语。写东西写到一半想起要用某个技能时用这个。")
            GuideHairline()
            shortcut("⌥⌘K → 试触发", "把你打算说的话打进去，看谁会抢答、第几名。改完描述回来再打一次，能看出改动有没有用。")
        }
    }

    private func shortcut(_ key: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.s12) {
            Text(key)
                .font(Theme.Fonts.mono)
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, Theme.Space.s8)
                .frame(height: 22)
                .quietControl(cornerRadius: 6)
            Text(L(detail))
                .font(Theme.Fonts.callout)
                .lineSpacing(2)
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: GuideMetrics.measure, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Space.s12)
        .padding(.vertical, Theme.Space.s12)
    }
}

/// 常见问题：默认全收起的披露行。它是被查的，不是被读的——
/// 和上面「读」的内容刻意形成语法差。
private struct GuideFAQ: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded: Set<Int> = []

    private var items: [(String, String)] {
        var list: [(String, String)] = [
            ("装完技能要重启 Agent 吗？",
             "不用重启应用，但要开新会话。技能清单是在开会话那一刻注入的，已经聊着的会话不会中途多出一个技能。"),
            ("同一个技能要在每个客户端各装一份吗？",
             "不用。实体只有一份在本库里，各平台目录放的是指向它的软链。列表行点亮哪个平台标，哪个客户端就能用。"),
            ("我不点名，它会自己找到吗？",
             "会，但不保证。它开会话时只看得到每个技能的名称和描述，而这份清单有额度、会截断。技能少的时候够用；描述总量堆上去之后，点名更稳。"),
            ("「请使用 X：…」这句话必须一字不差吗？",
             "不必。它的全部作用是把技能名明确说出来，让匹配没有歧义。冒号后面的任务照你自己的话写就行。Claude Code 里也可以直接打 /技能名。"),
            ("我明明装了，它从来没触发过。",
             "先看 frontmatter 有没有写坏。YAML 解析失败时，Claude Code 会用空 metadata 加载正文。点名仍然能用，但描述为空，模型永远匹配不上。这比描述写太长更致命。"),
            ("为什么有的技能显示从没用过，我明明用过？",
             "使用统计靠会话日志里的技能目录路径引用，改过目录名、在没被扫描的客户端里用过、或日志已经清理，都会漏计。想要准的，在设置页开「Hook 实时遥测」。"),
            ("停用和卸载有什么区别？",
             "停用只是把它从清单里拿掉、回收预算，文件原样在，随时恢复。卸载会移除平台挂载，可选把库内目录移进废纸篓。"),
            ("技能之间会打架吗？",
             "会。描述里的触发词重叠时，模型可能挑错人。体检页有「触发词重叠」，上面的「当场试一句」能在你开口之前看出谁会抢答。"),
            ("技能会偷偷改我电脑上的东西吗？",
             "技能本身只是文本，真正动手的是 Agent 和它的权限。但文本能指挥 Agent 执行命令，所以来路不明的技能不该直接装。安装时会静态扫描 curl | sh、Base64 藏命令、allowed-tools 开全权这类写法，命中关键级会先把原文摆给你看。公开技能市场出过恶意技能事件，这条不是洁癖。"),
            ("MCP 能在这里装吗？",
             "不能，也不打算做。这里只管 Skill。MCP 在各 Agent 应用自己的配置里加。"),
            ("技能和 CLAUDE.md、全局提示词有什么区别？",
             "CLAUDE.md 是每次会话都全文加载的常驻规则，技能则是按需加载：只有描述进清单，正文等到真要用了才读。专项流程放技能里，比堆进常驻规则划算。"),
        ]
        // 只在库里真有链路关系时才出现，避免讲用户没有的东西
        if store.skills.contains(where: { ProductionChain.hasChain($0.directory) }) {
            list.append((
                "技能之间有先后顺序吗？",
                "有。上游的产出就是下游的输入，详情页「生产链路」能看到上游 / 下游 / 依赖 / 被依赖，都可点跳转。硬依赖坏起来是无声的：停用一个被依赖的技能，下游不会报错，只会做不出东西。所以你停用被依赖的技能时，本应用会拦一下。它只展示关系，不自动编排。"
            ))
        }
        return list
    }

    var body: some View {
        GuideGroup(label: "常见问题", note: "点开看答案") {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                if index > 0 { GuideHairline() }
                row(index: index, question: item.0, answer: item.1)
            }
        }
    }

    private func row(index: Int, question: String, answer: String) -> some View {
        let open = expanded.contains(index)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                if reduceMotion {
                    toggle(index)
                } else {
                    withAnimation(Motion.standard) { toggle(index) }
                }
            } label: {
                HStack(spacing: Theme.Space.s8) {
                    Text(L(question))
                        .font(Theme.Fonts.body)
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: Theme.Space.s8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                        .rotationEffect(.degrees(open ? 90 : 0))
                }
                .padding(.horizontal, Theme.Space.s12)
                .frame(minHeight: 40)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
            }
            .buttonStyle(.plain)
            .help(open ? L("收起") : L("展开"))
            if open {
                Text(L(answer))
                    .font(Theme.Fonts.callout)
                    .lineSpacing(2)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: GuideMetrics.measure, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Theme.Space.s12)
                    .padding(.bottom, Theme.Space.s12)
            }
        }
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(open ? Color.primary.opacity(0.04) : Color.clear)
        }
    }

    private func toggle(_ index: Int) {
        if expanded.contains(index) { expanded.remove(index) } else { expanded.insert(index) }
    }
}

// MARK: - ⑥ 你现在的实况
//
// 三个数与体检页同源。第三格必须用 doctorReport.atRisk.count，
// 不能再用「总数 − 某个固定上限」——那两个数来自完全不同的算法，
// 会在同一块面板上互相打架（描述都很短时上面说「可能被丢 5 个」、
// 下一行却说「预算还够」）。

private struct GuideLocalSection: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let total = store.skills.filter { !$0.disabled }.count
        let report = store.doctorReport
        VStack(alignment: .leading, spacing: Theme.Space.s16) {
            GuideSectionHead(section: .local)
            VStack(alignment: .leading, spacing: Theme.Space.s16) {
                metrics(total: total, report: report)
                statusLine(report)
                HStack {
                    Spacer(minLength: 0)
                    doctorButton
                }
            }
            .padding(Theme.Space.s16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .quietControl(cornerRadius: Theme.Radius.tile)
            Text(L("这三个数与体检页同源。预算按 token 估算，仅供横向比较。"))
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private func metrics(total: Int, report: DoctorReport) -> some View {
        HStack(alignment: .top, spacing: 0) {
            metric(value: total, label: "上架", note: "进清单的技能")
            divider
            metric(value: store.usedSkillCount, label: "用过", note: "日志里有调用记录")
            divider
            metric(value: report.atRisk.count, label: "描述可能被丢", note: "按当前预算模拟")
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.06))
            .frame(width: 1, height: 56)
            .padding(.horizontal, Theme.Space.s16)
    }

    private func metric(value: Int, label: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(Theme.Fonts.metric)
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : Motion.standard, value: value)
            Text(L(label))
                .font(Theme.Fonts.secondaryEmphasis)
                .foregroundStyle(Theme.textSecondary)
            Text(L(note))
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(width: 132, alignment: .leading)
    }

    private func statusLine(_ report: DoctorReport) -> some View {
        Text(report.overBudget
            ? LF("当前清单已超预算，估算有 %d 个技能的描述会被丢掉。技能还在，点名照样能用，只是 Claude 不再知道它们能干什么。", report.atRisk.count)
            : LF("清单占用约 %d%% 预算（估算）。丢的是描述不是技能，超了之后从用得最少的开始丢。", Int(report.usageFraction * 100)))
            .font(Theme.Fonts.callout)
            .lineSpacing(3)
            .foregroundStyle(report.overBudget ? Theme.warning : Theme.textSecondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var doctorButton: some View {
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
        .help(L("打开体检：预算、重叠、长期未用（⌘2）"))
    }
}
