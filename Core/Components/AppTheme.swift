//
//  AppTheme.swift
//  存放全 App 统一的颜色、字体定义、间距规范。
//

import SwiftUI

// MARK: - App Theme Constants
struct AppTheme {
    static let primaryColor = Color.blue
    // ... 可以在这里定义更多主题相关的常量
}

// MARK: - Font Extension for SF Expanded
extension Font {
    static func systemExpanded(size: CGFloat, weight: Font.Weight) -> Font {
        return Font(UIFont.systemFont(
            ofSize: size,
            weight: UIFont.Weight(rawValue: weight.uiFontWeight),
            width: .expanded
        ))
    }
}

extension Font.Weight {
    var uiFontWeight: CGFloat {
        switch self {
        case .ultraLight: return UIFont.Weight.ultraLight.rawValue
        case .thin: return UIFont.Weight.thin.rawValue
        case .light: return UIFont.Weight.light.rawValue
        case .regular: return UIFont.Weight.regular.rawValue
        case .medium: return UIFont.Weight.medium.rawValue
        case .semibold: return UIFont.Weight.semibold.rawValue
        case .bold: return UIFont.Weight.bold.rawValue
        case .heavy: return UIFont.Weight.heavy.rawValue
        case .black: return UIFont.Weight.black.rawValue
        default: return UIFont.Weight.regular.rawValue
        }
    }
}

