import AppKit
import Foundation
#if SWIFT_PACKAGE
import AtlasCore
#endif

// MARK: - 界面语言（简中 / English / 日本語 / 한국어）
//
// SwiftUI 字面量（Text/Button/.help/TextField…）经 LocalizedStringKey 自动查表；
// String 语境走 core 的 L()/LF()。
// 运行时切换：swizzle Bundle.main 的 localizedString(forKey:)，
// 视图树用 .id(store.uiLanguage) 整体重建，立即生效、无需重启。
// object_setClass 是 AppKit/ObjC 运行时，不能进 core。

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case zhHans = "zh-Hans"
    case english = "en"
    case japanese = "ja"
    case korean = "ko"

    var id: String { rawValue }

    /// 语言名用它自己的语言写（惯例：语言菜单不翻译语言名）
    var label: String {
        switch self {
        case .system: return L("跟随系统")
        case .zhHans: return "简体中文"
        case .english: return "English"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        }
    }

    static let storageKey = "atlasLanguage"

    static var stored: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .system
    }

    /// lproj 覆盖路径；system 与简中都走 nil（开发语言就是中文）
    var lprojOverride: String? {
        switch self {
        case .system:
            // 跟随系统：系统首选语言命中 en/ja/ko 时用对应包，否则中文
            for preferred in Locale.preferredLanguages {
                for candidate in ["en", "ja", "ko"] where preferred.hasPrefix(candidate) {
                    return Bundle.main.path(forResource: candidate, ofType: "lproj")
                }
                if preferred.hasPrefix("zh") { return nil }
            }
            return nil
        case .zhHans:
            return nil
        case .english, .japanese, .korean:
            return Bundle.main.path(forResource: rawValue, ofType: "lproj")
        }
    }

    /// SwiftUI Text(LocalizedStringKey) 的取词 locale（system 时跟随系统首选）
    var resolvedLocale: Locale {
        switch self {
        case .system:
            for preferred in Locale.preferredLanguages {
                for candidate in ["en", "ja", "ko"] where preferred.hasPrefix(candidate) {
                    return Locale(identifier: candidate)
                }
                if preferred.hasPrefix("zh") { return Locale(identifier: "zh-Hans") }
            }
            return Locale(identifier: "zh-Hans")
        case .zhHans: return Locale(identifier: "zh-Hans")
        case .english: return Locale(identifier: "en")
        case .japanese: return Locale(identifier: "ja")
        case .korean: return Locale(identifier: "ko")
        }
    }

    static func select(_ language: AppLanguage) {
        UserDefaults.standard.set(language.rawValue, forKey: storageKey)
        apply(language)
    }

    static func applyStored() {
        apply(stored)
    }

    static func apply(_ language: AppLanguage) {
        LocalizedBundle.activate()
        LocalizedBundle.overridePath = language.lprojOverride
    }
}

/// Bundle 子类替换 Bundle.main 的 class，把查表路由到所选语言包
final class LocalizedBundle: Bundle, @unchecked Sendable {
    static var overridePath: String?
    private static var activated = false

    static func activate() {
        guard !activated else { return }
        activated = true
        object_setClass(Bundle.main, LocalizedBundle.self)
    }

    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let path = Self.overridePath, let bundle = Bundle(path: path) {
            // 语言包缺这条时回退中文原文（key 本身）
            return bundle.localizedString(forKey: key, value: value ?? key, table: tableName)
        }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }
}
