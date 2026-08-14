import SwiftUI
import AppKit
import Carbon.HIToolbox

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
    @EnvironmentObject private var store: AppStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @FocusState private var searchFocused: Bool
    @State private var query = ""
    @State private var selection = 0
    @State private var copiedName: String?

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

    var body: some View {
        let list = results
        VStack(alignment: .leading, spacing: 0) {
            searchField
                .padding(Theme.Space.s8)
            Divider()
            if list.isEmpty {
                Text(store.skills.isEmpty ? L("还没有可用的技能") : LF("没有匹配「%@」的技能", query))
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
            Divider()
            footer
        }
        .frame(width: 340)
        .onAppear {
            query = ""
            selection = 0
            copiedName = nil
            // 浮层动画结束后再聚焦，太早会丢
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { searchFocused = true }
        }
        .onChange(of: query) { selection = 0 }
    }

    private var searchField: some View {
        HStack(spacing: Theme.Space.s8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("搜索技能，⏎ 复制调用语", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($searchFocused)
                .onSubmit {
                    let list = results
                    guard list.indices.contains(selection) else { return }
                    copyAndClose(list[selection])
                }
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
            Text("↑↓ 选择 · ⏎ 复制 · ⌥⌘K 呼出")
                .font(Theme.Fonts.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, Theme.Space.s12)
        .padding(.vertical, Theme.Space.s8)
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
                    Label("已复制", systemImage: "checkmark")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.healthy)
                } else if usage > 0 {
                    Text("\(usage) 次")
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
