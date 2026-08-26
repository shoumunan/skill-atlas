import SwiftUI
#if SWIFT_PACKAGE
import AtlasCore
#endif

// MARK: - 模型的 UI 元数据（从 Models.swift 拆出）
//
// 分类色、健康色、Color(hex:) 只给 App 用。core/CoreModels.swift 保持 Foundation-only。

extension Health {
    var tint: Color {
        switch self {
        case .healthy: return Theme.healthy
        case .warning: return Theme.warning
        case .error: return Theme.error
        }
    }
}

struct CategoryMeta {
    var symbol: String
    var tint: Color
}

enum Categories {
    static let meta: [String: CategoryMeta] = [
        "基金与投研": .init(symbol: "chart.line.uptrend.xyaxis", tint: Color(hex: 0x34C759)),
        "社交内容": .init(symbol: "bubble.left.and.text.bubble.right.fill", tint: Color(hex: 0xFF375F)),
        "演示与文档": .init(symbol: "doc.richtext.fill", tint: Color(hex: 0xFF9500)),
        "网页与自动化": .init(symbol: "globe", tint: Color(hex: 0x0A84FF)),
        "视觉与设计": .init(symbol: "paintbrush.pointed.fill", tint: Color(hex: 0xBF5AF2)),
        "数据与研究": .init(symbol: "chart.bar.xaxis", tint: Color(hex: 0x32ADE6)),
        "沟通与运营": .init(symbol: "megaphone.fill", tint: Color(hex: 0x5E5CE6)),
        "开发与工具": .init(symbol: "chevron.left.forwardslash.chevron.right", tint: Color(hex: 0x555A60)),
        "思考与协作": .init(symbol: "lightbulb.fill", tint: Color(hex: 0xA2845E)),
        "通用工具": .init(symbol: "briefcase.fill", tint: Color(hex: 0x8E8E93)),
    ]

    static func meta(for category: String) -> CategoryMeta {
        meta[category] ?? meta["通用工具"]!
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}
