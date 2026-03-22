import SwiftUI

// stonerOS design system — warm dark, muted accents, high-density functional
enum Theme {
    // Brand palette (dark variants)
    static let purple = Color(hex: 0x8A75D6)   // Primary — system building, AI
    static let slate  = Color(hex: 0x6A9CC4)   // Supporting
    static let green  = Color(hex: 0x66B47A)   // Success, growth
    static let gold   = Color(hex: 0xD4AD3A)   // Warmth, warning
    static let coral  = Color(hex: 0xD47878)   // Energy, urgency

    // Background — warm dark brown-black
    static let bg = Color(hex: 0x110A0F)

    // Text — warm neutrals, never pure white
    static let textPrimary   = Color(hex: 0xD2CBC7)
    static let textSecondary = Color(hex: 0xB5ACA7)
    static let textMuted     = Color(hex: 0x908580)
    static let textFaint     = Color(hex: 0x645A56)

    // Surfaces — translucent white, not solid gray
    static let cardBg     = Color.white.opacity(0.06)
    static let cardBorder = Color.white.opacity(0.08)
    static let hoverBg    = Color.white.opacity(0.04)

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
