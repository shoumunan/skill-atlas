import SwiftUI
import AppKit
import Carbon.HIToolbox
#if SWIFT_PACKAGE
import AtlasCore
#endif

// MARK: - 菜单栏常驻搜索入口
//
// MenuBarExtra（window style）+ ⌥⌘K 全局热键（Carbon RegisterEventHotKey，
// 不需要辅助功能权限；注册失败静默降级）。浮层用系统默认 popover 材质，
// 不硬套应用内的 L1/L2 玻璃层级——这是系统 chrome 语境。

// MARK: 模板图标（menu bar 图标必须是 template image）

enum MenuBarIcon {
    /// 应用 glyph（三叠玻璃卡）的单色模板版：alpha 梯度呼应玻璃景深
    static let template: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 16), flipped: false) { _ in
            let cards: [(rect: NSRect, radius: CGFloat, alpha: CGFloat)] = [
                (NSRect(x: 5.0, y: 12.6, width: 8.0, height: 2.6), 1.3, 0.35),  // 最远
                (NSRect(x: 3.5, y: 9.4, width: 11.0, height: 3.4), 1.7, 0.6),   // 中景
                (NSRect(x: 2.0, y: 1.0, width: 14.0, height: 7.6), 2.2, 1.0),   // 前景主卡
            ]
            for card in cards {
                NSColor.black.withAlphaComponent(card.alpha).setFill()
                NSBezierPath(roundedRect: card.rect, xRadius: card.radius, yRadius: card.radius).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }()

    /// 「有事」态：主卡右上角一个实心点。菜单栏只分安静 / 有事两态
    /// （DESIGN v15），不做数字、不做颜色——那是通知中心的活。
    static let alert: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 16), flipped: false) { _ in
            let cards: [(rect: NSRect, radius: CGFloat, alpha: CGFloat)] = [
                (NSRect(x: 5.0, y: 12.6, width: 8.0, height: 2.6), 1.3, 0.35),
                (NSRect(x: 3.5, y: 9.4, width: 11.0, height: 3.4), 1.7, 0.6),
                (NSRect(x: 2.0, y: 1.0, width: 14.0, height: 7.6), 2.2, 1.0),
            ]
            for card in cards {
                NSColor.black.withAlphaComponent(card.alpha).setFill()
                NSBezierPath(roundedRect: card.rect, xRadius: card.radius, yRadius: card.radius).fill()
            }
            // 先用 destinationOut 挖掉一圈，再点实心点：
            // 不留这圈空隙，点会和主卡糊成一个缺角
            NSGraphicsContext.current?.saveGraphicsState()
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            NSColor.black.setFill()
            NSBezierPath(ovalIn: NSRect(x: 11.2, y: 8.2, width: 6.6, height: 6.6)).fill()
            NSGraphicsContext.current?.restoreGraphicsState()
            NSColor.black.setFill()
            NSBezierPath(ovalIn: NSRect(x: 12.6, y: 9.6, width: 3.8, height: 3.8)).fill()
            return true
        }
        image.isTemplate = true
        return image
    }()
}

// MARK: 全局热键（⌥⌘K）

enum GlobalHotKey {
    private static var hotKeyRef: EventHotKeyRef?
    private static var handlerRef: EventHandlerRef?
    private static var action: (() -> Void)?
    private(set) static var registered = false

    /// 注册 ⌥⌘K。任何一步失败都静默返回（不弹错、不崩溃），菜单栏图标仍可点击呼出。
    static func register(action: @escaping () -> Void) {
        guard !registered else { return }
        Self.action = action

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let installStatus = InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, _, _ in
                DispatchQueue.main.async { GlobalHotKey.action?() }
                return noErr
            },
            1, &eventType, nil, &handlerRef
        )
        guard installStatus == noErr else { return }

        let hotKeyID = EventHotKeyID(signature: OSType(0x41_54_4C_53), id: 1)  // "ATLS"
        let registerStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_K),
            UInt32(cmdKey | optionKey),
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
        registered = (registerStatus == noErr)
    }

    /// 模拟点击本应用的菜单栏状态项，开/关 MenuBarExtra 浮层。
    /// MenuBarExtra 没有公开的编程呼出 API；遍历公开类型 NSStatusBarButton，找不到就什么都不做。
    static func toggleMenuBarPanel() {
        for window in NSApp.windows where window.className.contains("NSStatusBarWindow") {
            if let contentView = window.contentView, let button = findStatusButton(in: contentView) {
                button.performClick(nil)
                // 状态项可能被挤出菜单栏（图标过多 / Bartender 类工具收纳），
                // 浮层会跟着锚到屏幕外——检测到就挪回当前屏右上角（弹出有动画，多试几次）
                for delay in [0.1, 0.3, 0.6] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { rescueOffscreenPanel() }
                }
                return
            }
        }
    }

    private static func rescueOffscreenPanel() {
        guard let screen = NSScreen.main else { return }
        for window in NSApp.windows {
            guard window.level.rawValue > NSWindow.Level.normal.rawValue,
                  window.frame.width > 200, window.frame.width < 600,
                  !NSScreen.screens.contains(where: { $0.frame.intersects(window.frame) })
            else { continue }
            let visible = screen.visibleFrame
            window.setFrameOrigin(NSPoint(
                x: visible.maxX - window.frame.width - 8,
                y: visible.maxY - window.frame.height - 4
            ))
        }
    }

    private static func findStatusButton(in view: NSView) -> NSStatusBarButton? {
        if let button = view as? NSStatusBarButton { return button }
        for subview in view.subviews {
            if let found = findStatusButton(in: subview) { return found }
        }
        return nil
    }
}

// MARK: 浮层内容

struct MenuBarPalette: View {
    @Environment(AppStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @FocusState private var searchFocused: Bool
    @State private var query = ""
    @State private var selection = 0
    @State private var copiedName: String?
    /// 模式：搜技能（回车复制）/ 试触发（这句话会唤醒谁）
    @State private var triggerMode = false

    /// 结果按使用频率加权：常用的排前面（第一轮使用统计的直接复用）
    private var results: [Skill] {
        let keyword = query.trimmingCharacters(in: .whitespaces).lowercased()
        return store.skills
            .filter { !$0.disabled && (keyword.isEmpty || $0.searchText.contains(keyword)) }
            .sorted {
                let a = store.usage[$0.directory]?.total ?? 0
                let b = store.usage[$1.directory]?.total ?? 0
                return a != b ? a > b : $0.name.lowercased() < $1.name.lowercased()
            }
            .prefix(8)
            .map { $0 }
    }

    private var triggerResults: [TriggerCandidate] {
        let atRisk = Set(store.doctorReport.atRisk.map(\.skill.name))
        return TriggerLab.simulate(
            phrase: query, skills: store.skills, usage: store.usage, atRiskNames: atRisk
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            modeTabs
                .padding(.horizontal, Theme.Space.s8)
                .padding(.top, Theme.Space.s8)
            searchField
                .padding(Theme.Space.s8)
            Divider()
            if triggerMode {
                triggerList
            } else {
                searchList
            }
            Divider()
            footer
        }
        .frame(width: 360)
        .onAppear {
            query = ""
            selection = 0
            copiedName = nil
            // 浮层动画结束后再聚焦，太早会丢
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { searchFocused = true }
        }
        .onChange(of: query) { selection = 0 }
    }

    // MARK: 模式切换

    private var modeTabs: some View {
        HStack(spacing: 2) {
            modeTab(L("搜技能"), active: !triggerMode) { triggerMode = false }
            modeTab(L("试一句话"), active: triggerMode) { triggerMode = true }
            Spacer()
        }
    }

    private func modeTab(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(active ? Theme.Fonts.secondaryEmphasis : Theme.Fonts.secondary)
                .foregroundStyle(active ? Theme.textPrimary : Theme.textTertiary)
                .padding(.horizontal, Theme.Space.s8)
                .frame(height: 20)
                .background {
                    if active {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(0.08))
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var searchField: some View {
        HStack(spacing: Theme.Space.s8) {
            Image(systemName: triggerMode ? "bolt" : "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            TextField(
                triggerMode ? L("打你打算说的话，看谁会抢答") : L("搜技能或要做的事，回车复制"),
                text: $query
            )
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($searchFocused)
                .onSubmit { handleSubmit() }
                .onKeyPress(.downArrow) {
                    selection = min(selection + 1, results.count - 1)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    selection = max(selection - 1, 0)
                    return .handled
                }
                .onExitCommand { closePanel() }
        }
        .padding(.horizontal, Theme.Space.s8)
        .frame(height: 30)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        }
    }

    // MARK: 搜技能列表（回车复制调用语）

    private var searchList: some View {
        let list = results
        return Group {
            if list.isEmpty {
                Text(store.skills.isEmpty ? L("还没有技能") : LF("没有匹配「%@」的技能", query))
                    .font(Theme.Fonts.secondary)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Space.s20)
            } else {
                VStack(spacing: 1) {
                    ForEach(Array(list.enumerated()), id: \.element.name) { index, skill in
                        PaletteRow(
                            skill: skill,
                            usage: store.usage[skill.directory]?.total ?? 0,
                            selected: index == selection,
                            copied: copiedName == skill.name
                        ) {
                            copyAndClose(skill)
                        }
                        .onHover { if $0 { selection = index } }
                    }
                }
                .padding(Theme.Space.s4)
            }
        }
    }

    // MARK: 试触发列表（F1：这句话会唤醒谁）

    private var triggerList: some View {
        let candidates = triggerResults
        return Group {
            if query.trimmingCharacters(in: .whitespaces).count < 2 {
                Text(L("像平时一样打一句话，比如「做个PPT」"))
                    .font(Theme.Fonts.secondary)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Space.s20)
            } else if candidates.isEmpty {
                Text(L("没有技能会接这句话。试试点名。"))
                    .font(Theme.Fonts.secondary)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Space.s20)
            } else {
                VStack(spacing: 1) {
                    ForEach(Array(candidates.enumerated()), id: \.element.id) { index, candidate in
                        TriggerRow(candidate: candidate, rank: index + 1) {
                            store.select(candidate.skill.name)
                            openWindow(id: "main")
                            NSApp.activate(ignoringOtherApps: true)
                            closePanel()
                        }
                    }
                }
                .padding(Theme.Space.s4)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button {
                closePanel()
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Text("打开 Skill Atlas")
                    .font(Theme.Fonts.secondaryEmphasis)
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
            Spacer()
            Text(triggerMode
                    ? L("点结果去详情")
                    : L("回车复制调用语"))
                .font(Theme.Fonts.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, Theme.Space.s12)
        .padding(.vertical, Theme.Space.s8)
    }

    // MARK: 动作

    private func handleSubmit() {
        guard !triggerMode else { return }
        let list = results
        guard list.indices.contains(selection) else { return }
        let skill = list[selection]
        copyAndClose(skill)
    }

    private func copyAndClose(_ skill: Skill) {
        store.copyToPasteboard(AppStore.callPhrase(for: skill))
        copiedName = skill.name
        // 短暂展示「已复制」反馈再自动关闭
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            closePanel()
        }
    }

    private func closePanel() {
        copiedName = nil
        dismiss()
    }
}

/// 试触发结果行：名次 + 技能 + 命中词 + 风险徽标
private struct TriggerRow: View {
    var candidate: TriggerCandidate
    var rank: Int
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: Theme.Space.s8) {
                Text("\(rank)")
                    .font(Theme.Fonts.caption)
                    .monospacedDigit()
                    .foregroundStyle(rank == 1 ? Color.white : Color.secondary)
                    .frame(width: 16, height: 16)
                    .background {
                        Circle().fill(rank == 1 ? Theme.accent : Color.primary.opacity(0.06))
                    }
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: Theme.Space.s4) {
                        Text(candidate.skill.name)
                            .font(.system(size: 12.5, weight: rank == 1 ? .semibold : .medium))
                            .lineLimit(1)
                        if candidate.disabled {
                            flag(L("已停用"), tint: .secondary)
                        }
                        if candidate.atRisk {
                            flag(L("可能被藏"), tint: Theme.warning)
                        }
                        if !candidate.buried.isEmpty {
                            flag(L("关键词靠后"), tint: Theme.warning)
                        }
                    }
                    Text(LF("命中：%@", candidate.matched.prefix(4).joined(separator: "、")))
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: Theme.Space.s4)
                if candidate.usageCount > 0 {
                    Text(LF("%lld 次", candidate.usageCount))
                        .font(Theme.Fonts.caption)
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, Theme.Space.s8)
            .padding(.vertical, 5)
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(rank == 1 ? Theme.accent.opacity(0.08) : Color.clear)
            }
        }
        .buttonStyle(.plain)
    }

    private func flag(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 4)
            .frame(height: 14)
            .background {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(tint.opacity(0.10))
            }
    }
}

private struct PaletteRow: View {
    var skill: Skill
    var usage: Int
    var selected: Bool
    var copied: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.s8) {
                CategoryIcon(category: skill.category, size: 22, style: .quiet)
                Text(skill.name)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: Theme.Space.s8)
                if copied {
                    Label(L("已复制"), systemImage: "checkmark")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.healthy)
                } else if usage > 0 {
                    Text(LF("%lld 次", usage))
                        .font(Theme.Fonts.caption)
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                } else if selected {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, Theme.Space.s8)
            .frame(height: 30)
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(selected ? Color.primary.opacity(0.08) : Color.clear)
            }
        }
        .buttonStyle(.plain)
    }
}
