import AppKit
import SwiftUI
#if SWIFT_PACKAGE
import AtlasCore
#endif

// MARK: - AppKit 技能表
//
// 行是纯 NSView：滚动、悬停、选中都不进 SwiftUI。
// SkillTableController 挂在 Store 上跨切页复用，避免 SwiftUI 卸页时丢掉表。

/// 表行只带画面用得到的字段。完整 Skill（searchText / 示例 / 挂载 / 健康）不进复用行。
struct SkillRowSnapshot: Equatable {
    var name: String
    var category: String
    var blurb: String
    var platforms: [String]
    var disabled: Bool
    var updateAvailable: Bool
    var origin: SkillOrigin
    /// v15 TierDots：挂在 Claude 但被档位排除出自动清单 → 半亮（口径 = 体检 listing 集合）
    var claudeListed: Bool

    init(_ skill: Skill, claudeListed: Bool) {
        name = skill.name
        category = skill.category
        blurb = SkillRowBlurb.make(skill.description)
        platforms = skill.platforms
        disabled = skill.disabled
        updateAvailable = skill.updateAvailable
        origin = skill.origin
        self.claudeListed = claudeListed
    }
}

enum SkillTableItem {
    case header(title: String, count: Int)
    case skill(SkillRowSnapshot)

    var id: String {
        switch self {
        case .header(let title, _): return "h:\(title)"
        case .skill(let row): return "s:\(row.name)"
        }
    }

    var dataStamp: String {
        switch self {
        case .header(let title, let count): return "h:\(title):\(count)"
        case .skill(let row):
            return "s:\(row.name)|\(row.category)|\(row.platforms.joined(separator: ","))|\(row.disabled)|\(row.updateAvailable)|\(row.claudeListed)"
        }
    }

    static func flatten(_ groups: [(String, [Skill])], claudeListed: Set<String>) -> [SkillTableItem] {
        var items: [SkillTableItem] = []
        items.reserveCapacity(groups.reduce(0) { $0 + $1.1.count + ($1.0.isEmpty ? 0 : 1) })
        for (name, skills) in groups {
            if !name.isEmpty {
                items.append(.header(title: name, count: skills.count))
            }
            for skill in skills {
                items.append(.skill(SkillRowSnapshot(skill, claudeListed: claudeListed.contains(skill.directory))))
            }
        }
        return items
    }
}

@MainActor
final class SkillTableController: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    var store: AppStore
    let table: HoverTable
    let scroll: NSScrollView

    static func shared(for store: AppStore) -> SkillTableController {
        if let existing = store.skillTable {
            existing.store = store
            return existing
        }
        let created = SkillTableController(store: store)
        store.skillTable = created
        return created
    }

    init(store: AppStore) {
        self.store = store
        let table = HoverTable()
        table.headerView = nil
        table.allowsColumnReordering = false
        table.allowsColumnResizing = false
        table.allowsMultipleSelection = false
        table.allowsEmptySelection = true
        table.selectionHighlightStyle = .none
        table.focusRingType = .none
        table.usesAlternatingRowBackgroundColors = false
        table.backgroundColor = Theme.panelNSColor
        table.wantsLayer = true
        table.layerContentsRedrawPolicy = .onSetNeedsDisplay
        table.gridStyleMask = []
        table.intercellSpacing = NSSize(width: 0, height: 2)
        table.rowHeight = 44
        table.style = .plain

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle

        let scroll = OverlayScrollView()
        scroll.documentView = table
        scroll.wantsLayer = true
        scroll.drawsBackground = true
        scroll.backgroundColor = Theme.panelNSColor
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        scroll.scrollerInsets = NSEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)

        self.table = table
        self.scroll = scroll
        super.init()
        table.dataSource = self
        table.delegate = self
    }

    private var items: [SkillTableItem] = []
    private var ids: [String] = []
    private var stamps: [String] = []
    private var lastSelected: String?
    private var lastFavorites: Set<String> = []

    /// 多选集合（⌘点按累积）。独立小模型：SwiftUI 的批量操作条要观察它，
    /// 而控制器本身不进 Observation（ADR-14：库页状态不进 AppStore）。
    let multi = TableSelectionModel()

    func reloadFromStore() {
        apply(
            items: SkillTableItem.flatten(
                store.groupedSkills(store.filteredSkills),
                claudeListed: Set(store.doctorReport.entries.map { $0.skill.directory })
            ),
            selectedName: store.selectedName,
            favorites: store.favorites
        )
    }

    func apply(items: [SkillTableItem], selectedName: String?, favorites: Set<String>) {
        // 筛选/删除后，多选集合里已经不在列表上的名字要剪掉
        if !multi.names.isEmpty {
            let visible = Set(items.compactMap { item -> String? in
                if case .skill(let row) = item { return row.name }
                return nil
            })
            if !multi.names.isSubset(of: visible) {
                multi.names.formIntersection(visible)
            }
        }
        let ids = items.map(\.id)
        let stamps = items.map(\.dataStamp)
        let structureChanged = ids != self.ids
        let dataChanged = stamps != self.stamps
        self.items = items
        self.ids = ids
        self.stamps = stamps

        if structureChanged {
            table.reloadData()
        } else if dataChanged {
            refreshVisible()
        } else {
            if lastSelected != selectedName {
                updateSelectionChrome(from: lastSelected, to: selectedName)
            }
            if lastFavorites != favorites {
                refreshFavorites(old: lastFavorites, new: favorites)
            }
        }

        if lastSelected != selectedName {
            lastSelected = selectedName
            if let selectedName,
               let row = items.firstIndex(where: {
                   if case .skill(let item) = $0 { return item.name == selectedName }
                   return false
               }) {
                table.scrollRowToVisible(row)
            }
        }
        lastFavorites = favorites
    }

    func refreshVisible() {
        let rows = table.rows(in: table.visibleRect)
        guard rows.length > 0 else { return }
        for row in rows.location..<(rows.location + rows.length) {
            guard row >= 0, row < items.count else { continue }
            switch items[row] {
            case .header(let title, let count):
                (table.view(atColumn: 0, row: row, makeIfNecessary: false) as? SkillHeaderCell)?
                    .apply(title: title, count: count)
            case .skill(let rowItem):
                (table.view(atColumn: 0, row: row, makeIfNecessary: false) as? SkillRowCell)?
                    .apply(
                        row: rowItem,
                        selected: rowItem.name == store.selectedName || multi.names.contains(rowItem.name),
                        favorite: store.favorites.contains(rowItem.name),
                        hovering: row == table.hoveredRow,
                        platforms: store.visiblePlatforms
                    )
            }
        }
    }

    private func updateSelectionChrome(from old: String?, to new: String?) {
        if let old, let row = rowIndex(named: old) {
            (table.view(atColumn: 0, row: row, makeIfNecessary: false) as? SkillRowCell)?
                .setSelected(new == old)
        }
        if let new, new != old, let row = rowIndex(named: new) {
            (table.view(atColumn: 0, row: row, makeIfNecessary: false) as? SkillRowCell)?
                .setSelected(true)
        }
    }

    private func refreshFavorites(old: Set<String>, new: Set<String>) {
        for name in old.symmetricDifference(new) {
            guard let row = rowIndex(named: name) else { continue }
            (table.view(atColumn: 0, row: row, makeIfNecessary: false) as? SkillRowCell)?
                .setFavorite(new.contains(name))
        }
    }

    private func rowIndex(named name: String) -> Int? {
        items.firstIndex { item in
            if case .skill(let row) = item { return row.name == name }
            return false
        }
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row >= 0, row < items.count else { return nil }
        switch items[row] {
        case .header(let title, let count):
            let id = NSUserInterfaceItemIdentifier("header")
            let cell = (tableView.makeView(withIdentifier: id, owner: nil) as? SkillHeaderCell) ?? SkillHeaderCell()
            cell.identifier = id
            cell.apply(title: title, count: count)
            return cell
        case .skill(let rowItem):
            let id = NSUserInterfaceItemIdentifier("skill")
            let cell = (tableView.makeView(withIdentifier: id, owner: nil) as? SkillRowCell) ?? SkillRowCell()
            cell.identifier = id
            cell.coordinator = self
            cell.apply(
                row: rowItem,
                selected: rowItem.name == store.selectedName || multi.names.contains(rowItem.name),
                favorite: store.favorites.contains(rowItem.name),
                hovering: row == table.hoveredRow,
                platforms: store.visiblePlatforms
            )
            return cell
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard row >= 0, row < items.count else { return 44 }
        switch items[row] {
        case .header: return 28
        case .skill: return 44
        }
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }

    func toggleSelect(_ name: String, command: Bool = false) {
        if command {
            // ⌘点按进入/扩展多选；锚点自动并入，取消到只剩一个时保持多选态由用户清
            var set = multi.names
            if set.isEmpty, let anchor = store.selectedName, anchor != name {
                set.insert(anchor)
            }
            if set.contains(name) { set.remove(name) } else { set.insert(name) }
            multi.names = set
            if store.selectedName == nil { store.selectedName = name }
            refreshVisible()
        } else {
            if !multi.names.isEmpty {
                multi.names = []
                store.selectedName = name
                refreshVisible()
            } else {
                store.selectedName = store.selectedName == name ? nil : name
            }
        }
    }

    func clearMultiSelection() {
        guard !multi.names.isEmpty else { return }
        multi.names = []
        refreshVisible()
    }

    func skill(named name: String) -> Skill? {
        store.skills.first { $0.name == name }
    }

    func skill(at row: Int) -> Skill? {
        guard row >= 0, row < items.count, case .skill(let item) = items[row] else { return nil }
        return skill(named: item.name)
    }

    func menu(forRow row: Int) -> NSMenu? {
        guard let skill = skill(at: row) else { return nil }
        return SkillRowMenu.build(skill: skill, store: store)
    }
}

/// 系统「始终显示滚动条」会在 tile 里把样式打回带槽的 legacy。
/// 滑块自己画、槽不画：即使样式被改回去，右边也不会出现灰轨道。
/// 系统 overlay 滑块约 15pt，和行尾 18pt 平台图标抢位置，所以宽度自己收。
final class OverlayOnlyScroller: NSScroller {
    private static let barWidth: CGFloat = 9
    private static let knobWidth: CGFloat = 4

    override class var isCompatibleWithOverlayScrollers: Bool { true }

    override class func scrollerWidth(for controlSize: NSControl.ControlSize, scrollerStyle: NSScroller.Style) -> CGFloat {
        barWidth
    }

    override func draw(_ dirtyRect: NSRect) {
        drawKnob()
    }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}

    override func drawKnob() {
        let slot = rect(for: .knob)
        guard slot.height > 2 else { return }
        let knob = NSRect(
            x: slot.midX - Self.knobWidth / 2,
            y: slot.minY,
            width: Self.knobWidth,
            height: slot.height
        )
        let alpha: CGFloat = hitPart == .knob ? 0.42 : 0.28
        NSColor.labelColor.withAlphaComponent(alpha).setFill()
        NSBezierPath(roundedRect: knob, xRadius: Self.knobWidth / 2, yRadius: Self.knobWidth / 2).fill()
    }
}

final class OverlayScrollView: NSScrollView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        pinOverlay()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(pinOverlay),
            name: NSScroller.preferredScrollerStyleDidChangeNotification,
            object: nil
        )
    }

    required init?(coder: NSCoder) { nil }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        pinOverlay()
    }

    override func tile() {
        scrollerStyle = .overlay
        super.tile()
        pinOverlay()
    }

    @objc private func pinOverlay() {
        scrollerStyle = .overlay
        autohidesScrollers = true
        hasHorizontalScroller = false
        if !(verticalScroller is OverlayOnlyScroller) {
            let scroller = OverlayOnlyScroller(frame: verticalScroller?.frame ?? .zero)
            scroller.controlSize = .small
            verticalScroller = scroller
        }
        verticalScroller?.scrollerStyle = .overlay
        verticalScroller?.controlSize = .small
    }
}

// MARK: - 表级悬停：不靠 cell 的 tracking area（复用行会把 entered 吞掉，阴影就跟手延迟）

final class HoverTable: NSTableView {
    var hoveredRow = -1

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func validateProposedFirstResponder(_ responder: NSResponder, for event: NSEvent?) -> Bool {
        true
    }

    override func scrollWheel(with event: NSEvent) {
        if hoveredRow >= 0 { applyHover(-1) }
        super.scrollWheel(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        applyHover(row(at: convert(event.locationInWindow, from: nil)))
    }

    override func mouseEntered(with event: NSEvent) {
        applyHover(row(at: convert(event.locationInWindow, from: nil)))
    }

    override func mouseExited(with event: NSEvent) {
        applyHover(-1)
    }

    private func applyHover(_ row: Int) {
        let next = row >= 0 ? row : -1
        guard next != hoveredRow else { return }
        if hoveredRow >= 0 {
            (view(atColumn: 0, row: hoveredRow, makeIfNecessary: false) as? SkillRowCell)?.setHovering(false)
        }
        hoveredRow = next
        if next >= 0 {
            (view(atColumn: 0, row: next, makeIfNecessary: false) as? SkillRowCell)?.setHovering(true)
        }
    }

    override func mouseDown(with event: NSEvent) {
        MainActor.assumeIsolated {
            let loc = convert(event.locationInWindow, from: nil)
            let rowIndex = row(at: loc)
            if rowIndex >= 0, let cell = view(atColumn: 0, row: rowIndex, makeIfNecessary: false) as? SkillRowCell {
                let inCell = cell.convert(event.locationInWindow, from: nil)
                if cell.hitControl(at: inCell) {
                    super.mouseDown(with: event)
                    return
                }
                cell.handleBackgroundClick(command: event.modifierFlags.contains(.command))
                return
            }
            super.mouseDown(with: event)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        MainActor.assumeIsolated {
            let loc = convert(event.locationInWindow, from: nil)
            let rowIndex = row(at: loc)
            if rowIndex >= 0, let coordinator = delegate as? SkillTableController {
                return coordinator.menu(forRow: rowIndex)
            }
            return nil
        }
    }
}

// MARK: - 分组头

private final class SkillHeaderCell: NSTableCellView {
    private let titleField = NSTextField(labelWithString: "")
    private let countField = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        titleField.font = .systemFont(ofSize: 11, weight: .medium)
        titleField.textColor = .secondaryLabelColor
        titleField.lineBreakMode = .byTruncatingTail
        countField.font = .systemFont(ofSize: 10, weight: .medium)
        countField.textColor = .tertiaryLabelColor
        addSubview(titleField)
        addSubview(countField)
    }

    required init?(coder: NSCoder) { nil }

    override var isOpaque: Bool { true }

    func apply(title: String, count: Int) {
        titleField.stringValue = title
        countField.stringValue = "\(count)"
        needsLayout = true
    }

    override func draw(_ dirtyRect: NSRect) {
        Theme.panelNSColor.setFill()
        bounds.fill()
        super.draw(dirtyRect)
    }

    override func layout() {
        super.layout()
        countField.sizeToFit()
        let countW = countField.frame.width
        titleField.frame = NSRect(x: 12, y: 6, width: max(40, bounds.width - 24 - countW - 8), height: 16)
        countField.frame = NSRect(x: titleField.frame.maxX + 4, y: 7, width: countW, height: 14)
    }
}

// MARK: - 技能行

private enum SkillRowBlurb {
    static func make(_ text: String) -> String {
        var clean = ""
        clean.reserveCapacity(min(text.count, 80))
        var pendingSpace = false
        for character in text {
            if character.isWhitespace || character.isNewline {
                pendingSpace = !clean.isEmpty
            } else {
                if pendingSpace {
                    clean.append(" ")
                    pendingSpace = false
                }
                clean.append(character)
                if clean.count >= 72 { break }
            }
        }
        for prefix in ["Use this skill", "Use when", "当任务", "用于"]
        where clean.lowercased().hasPrefix(prefix.lowercased()) {
            clean = String(clean.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            break
        }
        return clean.count > 60 ? String(clean.prefix(60)) + "…" : clean
    }
}

private final class SkillRowCell: NSTableCellView {
    weak var coordinator: SkillTableController?
    private var row: SkillRowSnapshot?
    private var selected = false
    private var hovering = false
    private var favorite = false
    private var platforms: [AgentPlatform] = []

    private let chrome = NSView()
    private let iconChrome = NSView()
    private let iconView = NSImageView()
    private let nameField = NSTextField(labelWithString: "")
    private let subtitleField = NSTextField(labelWithString: "")
    private let copyButton = NSButton()
    private let starButton = NSButton()
    private let platformBox = NSView()
    private var platformButtons: [NSButton] = []
    private let updateView = NSImageView()
    private let statusField = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        chrome.wantsLayer = true
        chrome.layer?.cornerRadius = 10
        chrome.layer?.cornerCurve = .continuous
        addSubview(chrome)

        iconChrome.wantsLayer = true
        iconChrome.layer?.cornerRadius = 28 * 0.3
        iconChrome.layer?.cornerCurve = .continuous
        iconView.imageScaling = .scaleProportionallyDown
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)

        nameField.font = .systemFont(ofSize: 13, weight: .semibold)
        nameField.textColor = NSColor.labelColor.withAlphaComponent(0.85)
        nameField.lineBreakMode = .byTruncatingTail
        subtitleField.font = .systemFont(ofSize: 11)
        subtitleField.textColor = .secondaryLabelColor
        subtitleField.lineBreakMode = .byTruncatingTail
        statusField.font = .systemFont(ofSize: 10, weight: .medium)
        statusField.textColor = .tertiaryLabelColor
        configureIconButton(copyButton, symbol: "doc.on.doc", action: #selector(copyPhrase))
        copyButton.toolTip = L("复制调用语")
        configureIconButton(starButton, symbol: "star", action: #selector(toggleFavorite))
        updateView.imageScaling = .scaleProportionallyDown
        updateView.toolTip = L("有新版本，右键或详情页更新")
        updateView.contentTintColor = NSColor(Theme.accent)
        updateView.image = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: nil)

        addSubview(iconChrome)
        addSubview(iconView)
        addSubview(nameField)
        addSubview(subtitleField)
        addSubview(copyButton)
        addSubview(starButton)
        addSubview(platformBox)
        addSubview(updateView)
        addSubview(statusField)
    }

    required init?(coder: NSCoder) { nil }

    override var isOpaque: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        Theme.panelNSColor.setFill()
        bounds.fill()
        super.draw(dirtyRect)
    }

    private func configureIconButton(_ button: NSButton, symbol: String, action: Selector) {
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.bezelStyle = .inline
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.contentTintColor = .tertiaryLabelColor
        button.target = self
        button.action = action
        button.setButtonType(.momentaryChange)
    }

    func apply(row: SkillRowSnapshot, selected: Bool, favorite: Bool, hovering: Bool, platforms: [AgentPlatform]) {
        let sameRow = self.row?.name == row.name
        let categoryChanged = self.row?.category != row.category
        let lightsChanged = !sameRow
            || self.row?.platforms != row.platforms
            || self.row?.disabled != row.disabled
            || self.row?.origin != row.origin
            || self.row?.claudeListed != row.claudeListed
            || self.platforms != platforms
        self.row = row
        self.selected = selected
        self.favorite = favorite
        self.hovering = hovering
        self.platforms = platforms
        if nameField.stringValue != row.name { nameField.stringValue = row.name }
        if subtitleField.stringValue != row.blurb { subtitleField.stringValue = row.blurb }
        if categoryChanged { applyCategoryIcon(row.category) }
        alphaValue = row.disabled ? 0.55 : 1
        statusField.stringValue = row.disabled ? L("已停用") : ""
        statusField.isHidden = !row.disabled
        updateView.isHidden = row.disabled || !row.updateAvailable
        applyStar()
        if !sameRow || platformButtons.count != platforms.count { rebuildPlatformsIfNeeded() }
        if lightsChanged { updatePlatformLights() }
        applyAccessories()
        updateChrome()
        needsLayout = true
    }

    func setHovering(_ hovering: Bool) {
        guard self.hovering != hovering else { return }
        self.hovering = hovering
        applyAccessories()
        updateChrome()
    }

    func setSelected(_ selected: Bool) {
        guard self.selected != selected else { return }
        self.selected = selected
        applyAccessories()
        updateChrome()
    }

    func setFavorite(_ favorite: Bool) {
        guard self.favorite != favorite else { return }
        self.favorite = favorite
        applyStar()
        applyAccessories()
    }

    private var isDark: Bool {
        effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    private func applyCategoryIcon(_ category: String) {
        let meta = Categories.meta(for: category)
        let tint = NSColor(meta.tint)
        iconChrome.layer?.backgroundColor = tint.withAlphaComponent(isDark ? 0.24 : 0.15).cgColor
        iconView.image = NSImage(systemSymbolName: meta.symbol, accessibilityDescription: category)
        iconView.contentTintColor = tint
    }

    private func applyStar() {
        starButton.image = NSImage(systemSymbolName: favorite ? "star.fill" : "star", accessibilityDescription: nil)
        starButton.contentTintColor = favorite ? NSColor(Theme.accent) : .tertiaryLabelColor
        starButton.toolTip = favorite ? L("取消收藏") : L("收藏")
    }

    private func applyAccessories() {
        let show = hovering || selected
        copyButton.alphaValue = show ? 1 : 0
        starButton.alphaValue = (show || favorite) ? 1 : 0
    }

    private func rebuildPlatformsIfNeeded() {
        platformButtons.forEach { $0.removeFromSuperview() }
        platformButtons = platforms.enumerated().map { index, _ in
            let button = NSButton()
            button.isBordered = false
            button.imagePosition = .imageOnly
            button.bezelStyle = .inline
            button.wantsLayer = true
            button.layer?.cornerRadius = 18 * 0.3
            button.layer?.cornerCurve = .continuous
            button.layer?.masksToBounds = true
            button.layer?.borderWidth = 0.5
            button.tag = index
            button.target = self
            button.action = #selector(togglePlatform(_:))
            platformBox.addSubview(button)
            return button
        }
    }

    private func updatePlatformLights() {
        guard let row else { return }
        let dark = isDark
        for (index, platform) in platforms.enumerated() {
            guard index < platformButtons.count else { continue }
            let button = platformButtons[index]
            let lit = row.platforms.contains(platform.label)
            // v15 TierDots 半亮：Claude 挂着但被档位排除出自动清单（仅 /名字 可调或 off）
            let halfLit = lit && platform == .claude && !row.claudeListed && !row.disabled
            let togglable = row.origin == .atlas && !row.disabled
            button.isEnabled = togglable
            button.image = PlatformChipImage.image(for: platform, lit: lit)
            button.imageScaling = .scaleProportionallyDown
            if let spec = PlatformBrand.spec(for: platform) {
                let fill = lit ? NSColor(spec.tint).withAlphaComponent(dark ? 0.20 : 0.12)
                    : NSColor.labelColor.withAlphaComponent(dark ? 0.07 : 0.04)
                button.layer?.backgroundColor = fill.cgColor
                button.layer?.borderColor = (lit
                    ? NSColor(spec.tint).withAlphaComponent(dark ? 0.30 : 0.20)
                    : NSColor.labelColor.withAlphaComponent(0.06)).cgColor
                if spec.tintedGlyph, lit {
                    button.contentTintColor = NSColor(spec.tint)
                } else {
                    button.contentTintColor = spec.template
                        ? (lit ? NSColor.labelColor.withAlphaComponent(0.85) : NSColor.tertiaryLabelColor)
                        : nil
                }
                button.alphaValue = halfLit ? 0.55 : (lit ? 1 : 0.5)
            }
            button.toolTip = halfLit
                ? LF("%@：已挂载但不进自动清单（档位）。点击停止同步；改档去供给页。", platform.displayName)
                : platformHelp(platform, lit: lit, togglable: togglable, origin: row.origin)
        }
    }

    private func platformHelp(_ platform: AgentPlatform, lit: Bool, togglable: Bool, origin: SkillOrigin) -> String {
        if togglable {
            return lit
                ? LF("停止同步到 %@", platform.displayName)
                : LF("同步到 %@", platform.displayName)
        }
        switch origin {
        case .ccSwitch: return LF("%@：%@（由 CC Switch 管理）", platform.displayName, lit ? L("已同步") : L("未同步"))
        case .local: return LF("%@：收进本库后可以开关同步", platform.displayName)
        case .atlas: return LF("%@：已停用，恢复后可以开关同步", platform.displayName)
        }
    }

    private func updateChrome() {
        let accent = NSColor(Theme.accent)
        if selected {
            chrome.layer?.backgroundColor = accent.withAlphaComponent(0.12).cgColor
            chrome.layer?.borderWidth = 0.5
            chrome.layer?.borderColor = accent.withAlphaComponent(0.20).cgColor
        } else if hovering {
            chrome.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.06).cgColor
            chrome.layer?.borderWidth = 0
            chrome.layer?.borderColor = nil
        } else {
            chrome.layer?.backgroundColor = NSColor.clear.cgColor
            chrome.layer?.borderWidth = 0
            chrome.layer?.borderColor = nil
        }
    }

    override func layout() {
        super.layout()
        chrome.frame = bounds
        let midY = bounds.midY
        iconChrome.frame = NSRect(x: 12, y: midY - 14, width: 28, height: 28)
        iconView.frame = NSRect(x: 19, y: midY - 7, width: 14, height: 14)

        var right = bounds.width - 12
        if !statusField.isHidden {
            statusField.sizeToFit()
            let width = min(52, statusField.frame.width)
            statusField.frame = NSRect(x: right - width, y: midY - 8, width: width, height: 16)
            right -= width + 8
        }
        if !updateView.isHidden {
            updateView.frame = NSRect(x: right - 14, y: midY - 7, width: 14, height: 14)
            right -= 22
        }
        let chipCount = max(platformButtons.count, 1)
        let chipsW = CGFloat(chipCount) * 18 + CGFloat(max(0, chipCount - 1)) * 4
        platformBox.frame = NSRect(x: right - chipsW, y: midY - 9, width: chipsW, height: 18)
        for (index, button) in platformButtons.enumerated() {
            button.frame = NSRect(x: CGFloat(index) * 22, y: 0, width: 18, height: 18)
        }
        right -= chipsW + 8
        starButton.frame = NSRect(x: right - 24, y: midY - 12, width: 24, height: 24)
        right -= 24
        copyButton.frame = NSRect(x: right - 24, y: midY - 12, width: 24, height: 24)
        right -= 24

        let textX: CGFloat = 48
        let textW = max(40, right - textX - 8)
        nameField.frame = NSRect(x: textX, y: midY + 1, width: textW, height: 16)
        subtitleField.frame = NSRect(x: textX, y: midY - 15, width: textW, height: 14)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        if let row { applyCategoryIcon(row.category) }
        updatePlatformLights()
        updateChrome()
    }

    func hitControl(at point: NSPoint) -> Bool {
        if copyButton.alphaValue > 0.5 && copyButton.frame.contains(point) { return true }
        if starButton.alphaValue > 0.5 && starButton.frame.contains(point) { return true }
        return platformBox.frame.contains(point)
    }

    func handleBackgroundClick(command: Bool = false) {
        guard let name = row?.name else { return }
        MainActor.assumeIsolated {
            coordinator?.toggleSelect(name, command: command)
        }
    }

    @objc private func copyPhrase() {
        guard let name = row?.name else { return }
        MainActor.assumeIsolated {
            guard let skill = coordinator?.skill(named: name) else { return }
            coordinator?.store.copyToPasteboard(AppStore.callPhrase(for: skill))
        }
    }

    @objc private func toggleFavorite() {
        guard let name = row?.name else { return }
        MainActor.assumeIsolated {
            coordinator?.store.toggleFavorite(name)
        }
    }

    @objc private func togglePlatform(_ sender: NSButton) {
        guard let row, sender.tag >= 0, sender.tag < platforms.count else { return }
        let platform = platforms[sender.tag]
        guard row.origin == .atlas, !row.disabled else { return }
        let lit = row.platforms.contains(platform.label)
        MainActor.assumeIsolated {
            guard let skill = coordinator?.skill(named: row.name) else { return }
            coordinator?.store.setPlatform(skill, platform: platform, enabled: !lit)
        }
    }

}

// MARK: - 平台同步图标（18pt 列表密度）

private enum PlatformChipImage {
    private static var cache: [String: NSImage] = [:]

    static func image(for platform: AgentPlatform, lit: Bool) -> NSImage? {
        let key = "\(platform.rawValue)|\(lit ? "1" : "0")"
        if let cached = cache[key] { return cached }
        guard let source = PlatformBrand.image(for: platform) else { return nil }
        let spec = PlatformBrand.spec(for: platform)
        let size: CGFloat = 18
        let glyph = size * (spec?.glyphScale ?? 0.62)
        let rendered = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            let inset = (size - glyph) / 2
            source.draw(
                in: NSRect(x: inset, y: inset, width: glyph, height: glyph),
                from: .zero,
                operation: .sourceOver,
                fraction: lit ? 1 : 0.45,
                respectFlipped: true,
                hints: [.interpolation: NSImageInterpolation.high]
            )
            return true
        }
        if spec?.template == true { rendered.isTemplate = true }
        cache[key] = rendered
        return rendered
    }
}

// MARK: - 右键菜单

private enum SkillRowMenu {
    @MainActor
    static func build(skill: Skill, store: AppStore) -> NSMenu {
        let menu = NSMenu()
        add(menu, L("复制调用语")) { store.copyToPasteboard(AppStore.callPhrase(for: skill)) }
        add(menu, L("查看说明")) {
            store.select(skill.name)
            store.readerSkill = skill
        }
        menu.addItem(.separator())
        if skill.origin == .atlas && !skill.disabled {
            let platformMenu = NSMenu()
            for platform in store.visiblePlatforms {
                let enabled = skill.platforms.contains(platform.label)
                let item = NSMenuItem(title: platform.label, action: #selector(MenuTrampoline.run(_:)), keyEquivalent: "")
                item.state = enabled ? .on : .off
                item.target = MenuTrampoline.shared
                item.representedObject = ClosureBox {
                    store.setPlatform(skill, platform: platform, enabled: !enabled)
                }
                platformMenu.addItem(item)
            }
            let parent = NSMenuItem(title: L("平台"), action: nil, keyEquivalent: "")
            parent.submenu = platformMenu
            menu.addItem(parent)
        }
        if skill.origin == .local && !skill.disabled {
            add(menu, L("收进本库…")) { store.requestAdopt(skill) }
        }
        if skill.origin == .atlas && skill.updateAvailable {
            add(menu, L("有新版本…")) { store.requestUpdate(skill) }
        }
        add(menu, store.favorites.contains(skill.name) ? L("取消收藏") : L("收藏")) {
            store.toggleFavorite(skill.name)
        }
        add(menu, L("在访达中显示")) { store.openFolder(skill.sourcePath) }
        add(menu, L("档位与供给…")) { store.nav = .supply }
        if skill.origin != .ccSwitch {
            menu.addItem(.separator())
            add(menu, skill.disabled ? L("恢复") : L("停用")) {
                if skill.disabled {
                    store.setSkillDisabled(skill, disabled: false)
                } else {
                    store.requestDisable(skill)
                }
            }
            add(menu, L("卸载…")) { store.requestUninstall(skill) }
        }
        return menu
    }

    @discardableResult
    private static func add(_ menu: NSMenu, _ title: String, handler: @escaping () -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(MenuTrampoline.run(_:)), keyEquivalent: "")
        item.target = MenuTrampoline.shared
        item.representedObject = ClosureBox(handler)
        menu.addItem(item)
        return item
    }
}

private final class ClosureBox: NSObject {
    let handler: () -> Void
    init(_ handler: @escaping () -> Void) { self.handler = handler }
}

private final class MenuTrampoline: NSObject {
    static let shared = MenuTrampoline()
    @objc func run(_ sender: NSMenuItem) {
        (sender.representedObject as? ClosureBox)?.handler()
    }
}

/// 多选集合的可观察载体：SwiftUI 批量操作条读它，控制器写它
@MainActor
@Observable
final class TableSelectionModel {
    var names: Set<String> = []
}
