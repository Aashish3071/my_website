import SwiftUI
import UIKit

/// Semantic colour tokens. Views should use these instead of literal colours.
///
/// Brand and status colours live in `Assets.xcassets`. Each one has light, dark,
/// and Increase Contrast variants. Every text/background pairing is checked to meet
/// WCAG 2.1 AA (4.5:1) by `ColorContrastTests`.
enum AppColor {
    // MARK: Brand
    static var brandPrimary: Color { AssetColor.brandPrimary.color }
    /// Text and icons drawn on top of `brandPrimary`.
    static var onBrandPrimary: Color { AssetColor.onBrandPrimary.color }

    // MARK: Status (always pair with an icon or text, never colour alone)
    static var success: Color { AssetColor.statusSuccess.color }
    static var warning: Color { AssetColor.statusWarning.color }
    static var critical: Color { AssetColor.statusCritical.color }

    // MARK: Text
    static var textPrimary: Color { Color(uiColor: .label) }
    /// Replaces `secondaryLabel`, which falls below 4.5:1 on light backgrounds.
    static var textSecondary: Color { AssetColor.textSecondary.color }

    // MARK: Surfaces (system colours adapt to dark mode and Increase Contrast)
    static var background: Color { Color(uiColor: .systemBackground) }
    static var groupedBackground: Color { Color(uiColor: .systemGroupedBackground) }
    static var surface: Color { Color(uiColor: .secondarySystemGroupedBackground) }
    static var separator: Color { Color(uiColor: .separator) }
}

/// Colour sets defined in `Assets.xcassets`.
enum AssetColor: String, CaseIterable {
    case brandPrimary = "BrandPrimary"
    case onBrandPrimary = "OnBrandPrimary"
    case textSecondary = "TextSecondary"
    case statusSuccess = "StatusSuccess"
    case statusWarning = "StatusWarning"
    case statusCritical = "StatusCritical"

    var color: Color { Color(rawValue) }
    var uiColor: UIColor? { UIColor(named: rawValue) }
}
