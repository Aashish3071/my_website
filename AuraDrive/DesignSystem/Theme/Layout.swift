import CoreGraphics

/// Spacing scale (4-point grid).
enum Spacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let s: CGFloat = 12
    static let m: CGFloat = 16
    static let l: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
}

enum Layout {
    /// Apple's minimum touch target (44 x 44 pt).
    static let minimumTapTarget: CGFloat = 44
    static let cornerRadius: CGFloat = 14
    /// Keeps lines of text at a readable length in landscape.
    static let readableContentWidth: CGFloat = 560
}
