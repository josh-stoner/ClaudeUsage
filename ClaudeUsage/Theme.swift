import SwiftUI

// stonerOS design system — warm neutrals, muted accents, high-density functional
// Light values from design_themes.md; dark values are the original palette.
@MainActor
enum Theme {
    @AppStorage("appearance") static var isDark: Bool = true

    // Brand palette — light/dark variants from design_themes.md
    static var purple: Color { isDark ? Color(hex: 0x8A75D6) : Color(hex: 0x6D5ACD) }
    static var steel: Color  { isDark ? Color(hex: 0x7B9BE0) : Color(hex: 0x557BCC) }
    static var rose: Color   { isDark ? Color(hex: 0xD48A9E) : Color(hex: 0xC47088) }
    static var green: Color  { isDark ? Color(hex: 0x66B47A) : Color(hex: 0x4A9960) }
    static var gold: Color   { isDark ? Color(hex: 0xD4AD3A) : Color(hex: 0xB8941F) }
    static var coral: Color  { isDark ? Color(hex: 0xD47878) : Color(hex: 0xC06060) }

    // Backgrounds
    static var bg: Color { isDark ? Color(hex: 0x110A0F) : Color(hex: 0xF1F0ED) }

    // Text
    static var textPrimary: Color   { isDark ? Color(hex: 0xD2CBC7) : Color(hex: 0x1A1A1A) }
    static var textSecondary: Color { isDark ? Color(hex: 0xB5ACA7) : Color(hex: 0x666666) }
    static var textMuted: Color     { isDark ? Color(hex: 0x908580) : Color(hex: 0x666666) }
    static var textFaint: Color     { isDark ? Color(hex: 0x645A56) : Color(hex: 0x999999) }

    // Surfaces
    static var cardBg: Color     { isDark ? Color.white.opacity(0.06) : Color.white }
    static var cardBorder: Color { isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06) }
    static var hoverBg: Color    { isDark ? Color.white.opacity(0.04) : Color.black.opacity(0.02) }

    // Radii (design charter)
    static let cardRadius: CGFloat = 12
    static let tagRadius: CGFloat = 8
    static let barRadius: CGFloat = 6
}

extension Color {
    init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
