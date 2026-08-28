import Foundation

// MARK: - 多语言查表（Foundation 版，App 与 CLI 共用）
//
// 键 = 中文原文。缺译时回退中文原文，永不显示裸 key。
// App 侧在 L10n.swift 里 swizzle Bundle.main，于是这里的 L() 会自动跟界面语言。
// CLI 没有 lproj 时 L() 原样返回中文键——CLI 默认中文，符合冻结面。

/// String 语境查表：L("技能库") → 当前语言文案（缺译回退原文）
package func L(_ key: String) -> String {
    Bundle.main.localizedString(forKey: key, value: key, table: nil)
}

/// 带参数的查表：LF("筛选出 %d / %d 项", a, b)
package func LF(_ key: String, _ args: CVarArg...) -> String {
    String(format: L(key), arguments: args)
}

/// 与 Info.plist CFBundleShortVersionString 对齐。发版改这一处 + plist。
package enum AtlasVersion {
    package static let string = "2.1.1"
    package static let build = "211"
}
