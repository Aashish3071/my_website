import Testing
import UIKit
@testable import AuraDrive

/// Checks that colour pairings meet WCAG 2.1 AA (4.5:1 for normal text) in light,
/// dark, and Increase Contrast modes.
@MainActor
struct ColorContrastTests {
    private struct Variant {
        let name: String
        let traits: UITraitCollection
    }

    private var variants: [Variant] {
        let combinations: [(UIUserInterfaceStyle, UIAccessibilityContrast)] = [
            (.light, .normal), (.dark, .normal), (.light, .high), (.dark, .high),
        ]
        return combinations.map { style, contrast in
            Variant(
                name: "\(style == .dark ? "dark" : "light"), \(contrast == .high ? "high contrast" : "standard contrast")",
                traits: UITraitCollection { traits in
                    traits.userInterfaceStyle = style
                    traits.accessibilityContrast = contrast
                }
            )
        }
    }

    @Test func allAssetColoursExist() {
        for asset in AssetColor.allCases {
            #expect(asset.uiColor != nil, "Missing colour set \(asset.rawValue) in Assets.xcassets")
        }
    }

    @Test func foregroundColoursMeetAAOnAppBackgrounds() throws {
        let foregrounds: [AssetColor] = [
            .brandPrimary, .textSecondary, .statusSuccess, .statusWarning, .statusCritical,
        ]
        let backgrounds: [(String, UIColor)] = [
            ("systemBackground", .systemBackground),
            ("systemGroupedBackground", .systemGroupedBackground),
            ("secondarySystemGroupedBackground", .secondarySystemGroupedBackground),
        ]

        for variant in variants {
            for foreground in foregrounds {
                let fg = try #require(foreground.uiColor).resolvedColor(with: variant.traits)
                for (backgroundName, background) in backgrounds {
                    let bg = background.resolvedColor(with: variant.traits)
                    let ratio = WCAG.contrastRatio(fg, bg)
                    #expect(
                        ratio >= 4.5,
                        "\(foreground.rawValue) on \(backgroundName) (\(variant.name)) is \(ratio):1"
                    )
                }
            }
        }
    }

    @Test func textOnBrandPrimaryMeetsAA() throws {
        for variant in variants {
            let fg = try #require(AssetColor.onBrandPrimary.uiColor).resolvedColor(with: variant.traits)
            let bg = try #require(AssetColor.brandPrimary.uiColor).resolvedColor(with: variant.traits)
            let ratio = WCAG.contrastRatio(fg, bg)
            #expect(ratio >= 4.5, "OnBrandPrimary on BrandPrimary (\(variant.name)) is \(ratio):1")
        }
    }
}

/// WCAG 2.1 relative luminance and contrast ratio.
private enum WCAG {
    static func relativeLuminance(of color: UIColor) -> Double {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        func linearize(_ component: CGFloat) -> Double {
            let c = Double(min(max(component, 0), 1))
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }

        return 0.2126 * linearize(red) + 0.7152 * linearize(green) + 0.0722 * linearize(blue)
    }

    static func contrastRatio(_ first: UIColor, _ second: UIColor) -> Double {
        let l1 = relativeLuminance(of: first)
        let l2 = relativeLuminance(of: second)
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }
}
