import SwiftUI

// stonerOS design system — warm neutrals, muted accents, high-density functional
// Round 4: gradient fills, glow accents, depth shadows, vivid chroma (app-scoped charter departure).
// Light values from design_themes.md; dark accents saturation-nudged +8–10% for R4 richness.
@MainActor
enum Theme {
    @AppStorage("appearance") static var isDark: Bool = true

    // Brand palette — dark mode saturation-nudged for R4 richness; light mode unchanged
    static var purple:   Color { isDark ? Color(hex: 0x9B82E8) : Color(hex: 0x6D5ACD) }
    static var lavender: Color { isDark ? Color(hex: 0xBAAAF0) : Color(hex: 0x9183D1) }
    static var steel:    Color { isDark ? Color(hex: 0x7AAAF0) : Color(hex: 0x557BCC) }
    static var rose:     Color { isDark ? Color(hex: 0xE08FAC) : Color(hex: 0xC47088) }
    static var green:    Color { isDark ? Color(hex: 0x60C070) : Color(hex: 0x4A9960) }
    static var gold:     Color { isDark ? Color(hex: 0xE0B838) : Color(hex: 0xB8941F) }
    static var coral:    Color { isDark ? Color(hex: 0xE07878) : Color(hex: 0xC06060) }

    // Backgrounds
    static var bg: Color { isDark ? Color(hex: 0x110A0F) : Color(hex: 0xF1F0ED) }

    // Text
    static var textPrimary:   Color { isDark ? Color(hex: 0xD2CBC7) : Color(hex: 0x1A1A1A) }
    static var textSecondary: Color { isDark ? Color(hex: 0xB5ACA7) : Color(hex: 0x666666) }
    static var textMuted:     Color { isDark ? Color(hex: 0x908580) : Color(hex: 0x666666) }
    static var textFaint:     Color { isDark ? Color(hex: 0x645A56) : Color(hex: 0x999999) }

    // Flat surfaces — used for skeletons, error banners, tab pills (unchanged)
    static var cardBg:     Color { isDark ? Color.white.opacity(0.06) : Color.white }
    static var cardBorder: Color { isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06) }
    static var hoverBg:    Color { isDark ? Color.white.opacity(0.04) : Color.black.opacity(0.02) }

    // R4 rich surfaces

    /// Gradient card surface — subtle warm-tinted vertical ramp so surfaces catch light.
    static var cardFill: LinearGradient {
        isDark
            ? LinearGradient(colors: [.white.opacity(0.078), .white.opacity(0.042)],
                             startPoint: .top, endPoint: .bottom)
            : LinearGradient(colors: [.white, .white.opacity(0.96)],
                             startPoint: .top, endPoint: .bottom)
    }

    /// Glossy gradient fill for usage bars and bar charts.
    static func meterFill(_ tint: Color) -> LinearGradient {
        LinearGradient(
            colors: [tint, tint.opacity(0.72)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Full-popover ambient hue wash keyed to the active tab — animates on tab switch.
    static func accentWash(_ tint: Color) -> LinearGradient {
        LinearGradient(
            colors: [tint.opacity(0.10), .clear],
            startPoint: .top,
            endPoint: .center
        )
    }

    // Radii (design charter)
    static let cardRadius: CGFloat = 12
    static let tagRadius:  CGFloat = 8
    static let barRadius:  CGFloat = 6
}

// MARK: - View depth extensions (R4)

extension View {
    /// Layered depth shadow for rich card surfaces.
    func cardDepth() -> some View {
        self
            .shadow(color: .black.opacity(0.22), radius: 10, x: 0, y: 3)
            .shadow(color: Color(hex: 0xEEDEE6, opacity: 0.06), radius: 18, x: 0, y: 0)
    }

    /// Subtle scale + shadow lift on hover for interactive cards.
    func hoverLift() -> some View {
        modifier(HoverLiftModifier())
    }
}

struct HoverLiftModifier: ViewModifier {
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(hovering ? 1.012 : 1.0)
            .shadow(color: .black.opacity(hovering ? 0.30 : 0), radius: hovering ? 14 : 0, x: 0, y: 4)
            .animation(.spring(response: 0.2, dampingFraction: 0.75), value: hovering)
            .onHover { hovering = $0 }
    }
}

extension Color {
    init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8)  & 0xFF) / 255,
            blue:  Double(hex         & 0xFF) / 255,
            opacity: opacity
        )
    }
}
