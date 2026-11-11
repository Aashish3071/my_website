import SwiftUI

/// Typography tokens. All of them are based on Dynamic Type text styles, so they
/// scale with the user's text size setting, including the accessibility sizes.
/// Do not use fixed point sizes for text.
enum AppFont {
    static let largeTitle = Font.largeTitle.weight(.bold)
    static let title = Font.title2.weight(.semibold)
    static let headline = Font.headline
    static let body = Font.body
    static let callout = Font.callout
    static let caption = Font.footnote
    /// Large numeric read-outs such as intensity level or fragrance remaining.
    static let readout = Font.system(.largeTitle, design: .rounded).weight(.semibold)
}
