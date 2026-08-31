import SwiftUI

/// DeepSeek Harness UI palette, mapped 1:1 from the `dsh-client-ui-theme`
/// tokens:
///   - static: `--dsw-static-deepseek-*`, `--dsw-static-neutral-bluish-*`
///   - semantic aliases: `--dsw-alias-*` (light = `body{}`, dark = `body[data-ds-dark-theme]{}`)
/// Every color is dynamic so the chat + composer follow the system light/dark
/// appearance while keeping the exact harness look.
enum DSHTheme {
    // MARK: Brand accent (deepseek-500 → deepseek-450 in dark)
    static let brand = Color.dynamic(lightHex: 0x4176E6, darkHex: 0x5686FE)
    static let brandStrong = Color(hex: 0x4868B2)                          // deepseek-600
    static let brandSoft = Color.dynamic(lightHex: 0xE4EDFD, darkHex: 0x34415B) // deepseek-100 / deepseek-800

    /// Inverse-contrast primary fill (DSH `button-primary-fill`): near-black
    /// in light, near-white in dark.
    static let brandPrimary = Color.dynamic(lightHex: 0x0F1115, darkHex: 0xF9FAFB)
    static let brandPrimaryText = Color.dynamic(lightHex: 0xFFFFFF, darkHex: 0x151517)

    // MARK: State
    static let success = Color(hex: 0x22C55E)                               // green-500
    static let warn = Color(hex: 0xF59E0B)                                  // amber-500
    static let error = Color.dynamic(lightHex: 0xEC1313, darkHex: 0xF25A5A) // red-600 / red-400

    // MARK: Backgrounds (base + surfacing layers)
    /// Window / content base. bluish-00 (#fff) light, bluish-950 (#151517) dark.
    static let bg = Color.dynamic(lightHex: 0xFFFFFF, darkHex: 0x151517)
    /// ZCode-style desktop navigation chrome. The sidebar is deliberately
    /// lighter than the conversation canvas in dark mode, so the hierarchy
    /// stays visible without relying on separator lines.
    static let sidebarBg = Color.dynamic(lightHex: 0xF3F3F4, darkHex: 0x39393B)
    static let titlebarBg = Color.dynamic(lightHex: 0xFAFAFB, darkHex: 0x1A1A1C)
    static let sidebarSelection = Color.dynamic(lightHex: 0xE5E5E7, darkHex: 0x444447)
    /// Layer-1 card. bluish-00 light, bluish-875 (#232324) dark.
    static let bgLayer1 = Color.dynamic(lightHex: 0xFFFFFF, darkHex: 0x232324)
    /// Layer-2 card / dock. bluish-00 light, bluish-850 (#2C2C2E) dark.
    static let surface = Color.dynamic(lightHex: 0xFFFFFF, darkHex: 0x2C2C2E)
    /// Layer-3 raised surface. bluish-00 light, bluish-800 (#353638) dark.
    static let surfaceRaised = Color.dynamic(lightHex: 0xFFFFFF, darkHex: 0x353638)
    /// Module / platform chrome. bluish-60 (#F5F6F7) light, bluish-800 dark.
    static let moduleBg = Color.dynamic(lightHex: 0xF5F6F7, darkHex: 0x353638)

    // MARK: Borders
    /// Subtle hairline (DSH `border-l2`): 10% black light, 12% white dark.
    static let border = Color.dynamic(lightHex: 0xE6E6E6, darkHex: 0x3A3A3C)
    static let borderStrong = Color.dynamic(lightHex: 0xD9D9D9, darkHex: 0x44444A)

    // MARK: Labels
    static let label = Color.dynamic(lightHex: 0x0F1115, darkHex: 0xF9FAFB)    // primary
    static let labelDim = Color.dynamic(lightHex: 0x61666B, darkHex: 0xCFD3D6)  // secondary
    static let labelTertiary = Color.dynamic(lightHex: 0x81858C, darkHex: 0xADB2B8)

    // MARK: Markdown
    static let codeBlockBg = Color.dynamic(lightHex: 0xF9FAFB, darkHex: 0x1B1B1C)     // bluish-50 / 900
    static let codeBlockBanner = Color.dynamic(lightHex: 0xF9FAFB, darkHex: 0x2C2C2E) // bluish-50 / 850

    // MARK: Shadow
    static let cardShadow = Color.black.opacity(0.08)

    // MARK: Interactive hover (DSH `interactive-bg-hover`)
    static let interactiveHover = Color.dynamic(lightHex: 0x0F1115, darkHex: 0xFFFFFF).opacity(0.08)
    static let interactiveHoverStrong = Color.dynamic(lightHex: 0x0F1115, darkHex: 0xFFFFFF).opacity(0.14)

    // MARK: Radii (DSH `--dsl-*-radius: 12px`)
    static let radiusCard: CGFloat = 12
    static let radiusPill: CGFloat = 8
}

/// DSH inverse-contrast primary button (`button-primary-fill`): near-black
/// fill / white text in light, near-white fill / near-black text in dark.
struct DSHPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(DSHTheme.brandPrimaryText)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                DSHTheme.brandPrimary.opacity(configuration.isPressed ? 0.85 : 1),
                in: RoundedRectangle(cornerRadius: DSHTheme.radiusPill)
            )
            .contentShape(RoundedRectangle(cornerRadius: DSHTheme.radiusPill))
    }
}

extension Color {
    init(hex: UInt) {
        self.init(
            nsColor: NSColor(
                srgbRed: Double((hex >> 16) & 0xFF) / 255,
                green: Double((hex >> 8) & 0xFF) / 255,
                blue: Double(hex & 0xFF) / 255,
                alpha: 1
            )
        )
    }

    /// A color that switches between a light and dark variant to follow the
    /// system appearance.
    static func dynamic(lightHex: UInt, darkHex: UInt) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: isDark ? darkHex : lightHex)
        })
    }
}

private extension NSColor {
    convenience init(hex: UInt) {
        self.init(
            srgbRed: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
