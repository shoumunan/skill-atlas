import AppKit
import SwiftUI
import UserNotifications
#if SWIFT_PACKAGE
import AtlasCore
#endif

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    /// 通知点击的落点由它转交（App 启动时由 SkillAtlasApp 注入）
    static weak var store: AppStore?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 离线验收探针：命中即解包并退出，不进入正常启动
        ZipChannel.runProbeIfRequested()
        NSApp.activate(ignoringOtherApps: true)
        // 设置页的语言与外观选择在窗口出现前先生效
        AppLanguage.applyStored()
        AppearanceMode.applyStored()
        SandboxTerminal.opener = { try SkillLauncher.openTerminalForSandbox(command: $0) }
        MetaSkill.ensure()
        // 通知点击要能落到条目上，否则 userInfo 里的深链没人消费
        UNUserNotificationCenter.current().delegate = self
        // ⌥⌘K 全局呼出菜单栏搜索浮层（注册失败静默降级，图标仍可点击）
        GlobalHotKey.register { GlobalHotKey.toggleMenuBarPanel() }
        // 调试钩子：-atlasMenubar 1 启动后自动呼出浮层（与热键同一路径，截图用）
        if UserDefaults.standard.bool(forKey: "atlasMenubar") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                GlobalHotKey.toggleMenuBarPanel()
            }
        }
    }

    /// 主窗口关闭后保持运行（菜单栏模式）；⌘Q 正常退出
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        if let raw = info["deepLink"] as? String, let url = URL(string: raw) {
            // 通知回调不在主 actor 上，路由要跳回主线程
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let store = Self.store else { return }
                    NSApp.activate(ignoringOtherApps: true)
                    handleDeepLink(url, store: store)
                }
            }
        }
        completionHandler()
    }

    /// App 在前台时也要显示通知，否则「有事找人」在你正开着窗口时静默失败
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

/// 外观模式：设置页「界面样式」的存储与应用（NSApp.appearance 全局生效，菜单栏浮层同步）
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    var symbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }

    static let storageKey = "atlasAppearanceMode"

    static var stored: AppearanceMode {
        AppearanceMode(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .system
    }

    static func applyStored() {
        apply(stored)
    }

    static func apply(_ mode: AppearanceMode) {
        // 调试参数 -atlasAppearance 优先（截图验收用），不落盘
        let debug = LaunchArgs.value("atlasAppearance") ?? UserDefaults.standard.string(forKey: "atlasAppearance")
        if let debug, ["dark", "light"].contains(debug) { return }
        switch mode {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    static func select(_ mode: AppearanceMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: storageKey)
        apply(mode)
    }
}

@MainActor
func handleDeepLink(_ url: URL, store: AppStore) {
    guard url.scheme == "skillatlas" else { return }
    let parts = url.pathComponents.filter { $0 != "/" }
    let host = url.host ?? parts.first
    let rest = url.host == nil ? Array(parts.dropFirst()) : parts
    if host == "review", let token = rest.first ?? url.path.split(separator: "/").map(String.init).last {
        store.openPendingReview(token: token)
    } else if host == "skill", let name = rest.first {
        store.select(name)
    } else if host == "profile", let name = rest.first {
        store.loadProfiles()
        if let profile = store.profiles.profiles.first(where: { $0.name == name || $0.id == name }) {
            store.requestProfileApply(profile, directory: nil)
        }
    } else if host == "discover" {
        store.nav = .discover
    } else if host == "supply" {
        // WP-S：supply/<scope> 定位具体范围；先落页
        store.nav = .supply
    } else if host == "inbox" {
        if let id = rest.first { Inbox.pendingFocusID = id }
        store.nav = .inbox
    }
}

@main
struct SkillAtlasApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = AppStore()
    /// 设置页「菜单栏快速搜索」开关：关掉即撤下菜单栏图标（⌥⌘K 热键随之无处呼出）
    @AppStorage("atlasMenuBarEnabled") private var menuBarEnabled = true

    /// 调试钩子：-atlasAppearance dark|light 强制配色（暗色验收用）
    private var forcedScheme: ColorScheme? {
        switch LaunchArgs.value("atlasAppearance") ?? UserDefaults.standard.string(forKey: "atlasAppearance") {
        case "dark": return .dark
        case "light": return .light
        default: return nil
        }
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView()
                // 切语言时整棵树重建，所有 LocalizedStringKey 立即按新语言取词
                .id(store.uiLanguage)
                .environment(\.locale, store.uiLanguage.resolvedLocale)
                .environment(store)
                .environment(store.usageIndex)
                .frame(minWidth: 1000, minHeight: 660)
                .background(WindowConfigurator())
                .preferredColorScheme(forcedScheme)
                .onOpenURL { url in
                    handleDeepLink(url, store: store)
                }
                .onAppear { AppDelegate.store = store }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1380, height: 860)
        .commands {
            CommandGroup(after: .appInfo) {
                Button(L("检查更新…")) { UpdateChecker.shared.checkFromMenu() }
            }
            CommandGroup(replacing: .newItem) {
                // ⌘N 落到发现页（DESIGN v15 入口表），不再直接弹旧安装 sheet：
                // 发现页才是「找并装上一个新技能」这条工作流的入口。
                Button(L("找并装技能…")) {
                    store.nav = .discover
                    store.discoverSearchFocus += 1
                }
                .keyboardShortcut("n", modifiers: .command)
                Button(L("导出技能清单…")) { store.exportSkillList() }
                    .keyboardShortcut("e", modifiers: .command)
                    .disabled(store.skills.isEmpty)
            }
            CommandMenu("管理") {
                Button(L("从 CC Switch 迁入…")) { store.migrationSheetPresented = true }
                    .disabled(!store.canMigrate || store.migrating)
                Button(L("撤销迁移")) { store.rollbackMigration() }
                    .disabled(!store.canRollback || store.migrating)
                Divider()
                Button(L("检查技能更新")) {
                    Task { await store.checkSkillUpdates(interactive: true) }
                }
                .keyboardShortcut("u", modifiers: .command)
                .disabled(store.skills.isEmpty)
                Button(L("更新全部…")) { store.requestUpdateAll() }
                    .keyboardShortcut("u", modifiers: [.command, .shift])
                    .disabled(store.updatableSkills.isEmpty)
            }
            CommandMenu("页面") {
                ForEach(Array(NavPage.allCases.enumerated()), id: \.element) { index, page in
                    Button(page.title) { store.nav = page }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                }
                Divider()
                Button(L("搜索技能")) { store.searchFocusRequest += 1 }
                    .keyboardShortcut("k", modifiers: .command)
                Button(L("重新扫描")) { Task { await store.rescan() } }
                    .keyboardShortcut("r", modifiers: .command)
            }
        }

        // 菜单栏常驻搜索：window 样式浮层，⌥⌘K 或点击图标呼出；设置页可整体关掉
        MenuBarExtra(isInserted: $menuBarEnabled) {
            MenuBarPalette()
                .id(store.uiLanguage)
                .environment(\.locale, store.uiLanguage.resolvedLocale)
                .environment(store)
        } label: {
            // 有待裁决事项时图标带点：App 的存在感来自「有事找你」，
            // 不是「等你来逛」（DESIGN v15 Ambient surface）
            Image(nsImage: store.inboxBadgeCount > 0 ? MenuBarIcon.alert : MenuBarIcon.template)
        }
        .menuBarExtraStyle(.window)
    }
}
