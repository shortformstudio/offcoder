import SwiftUI

struct FrostyBentoModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .background(Color.white.opacity(0.015))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
    }
}

extension View {
    func frostyBento() -> some View {
        self.modifier(FrostyBentoModifier())
    }
}

enum CockpitFonts {
    private static let scaleFactor: CGFloat = 1.5

    static func ultraThin(size: CGFloat) -> Font {
        // "AvenirNext-UltraLight" is the PostScript name for Avenir Next Ultra Light
        return Font.custom("AvenirNext-UltraLight", size: size * scaleFactor)
    }

    static func regular(size: CGFloat) -> Font {
        return Font.custom("AvenirNext-Regular", size: size * scaleFactor)
    }

    static func medium(size: CGFloat) -> Font {
        return Font.custom("AvenirNext-Medium", size: size * scaleFactor)
    }

    static func bold(size: CGFloat) -> Font {
        return Font.custom("AvenirNext-Bold", size: size * scaleFactor)
    }

    static func mono(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .bold: name = "AvenirNext-Bold"
        case .semibold, .heavy, .black: name = "AvenirNext-DemiBold"
        case .medium: name = "AvenirNext-Medium"
        case .ultraLight, .thin, .light: name = "AvenirNext-UltraLight"
        default: name = "AvenirNext-Regular"
        }
        return Font.custom(name, size: size * scaleFactor)
    }

    /// System monospaced font — ONLY for date/time and localhost:port URL displays
    static func code(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        return Font.system(size: size * scaleFactor, weight: weight, design: .monospaced)
    }
}

extension View {
    func cyanGlow(radius: CGFloat = 8, opacity: Double = 0.55) -> some View {
        self.shadow(color: Color.cyan.opacity(opacity), radius: radius, x: 0, y: 0)
    }

    func softGlow(color: Color = .white, radius: CGFloat = 6, opacity: Double = 0.35) -> some View {
        self.shadow(color: color.opacity(opacity), radius: radius, x: 0, y: 0)
    }
}

enum CockpitPalette {
    static let background = Color(red: 0.04, green: 0.05, blue: 0.06)
    static let header = Color.black.opacity(0.35)
    static let bayBackground = Color.white.opacity(0.015)
    static let border = Color.white.opacity(0.06)
    static let cardBackground = Color.black.opacity(0.4)
}

enum CockpitLayout {
    enum Breakpoint {
        case bento4
        case drawer3
        case grid2x2
        case singleBay
    }

    static func breakpoint(for width: CGFloat) -> Breakpoint {
        if width >= 1280 { return .bento4 }
        if width >= 980 { return .drawer3 }
        if width >= 760 { return .grid2x2 }
        return .singleBay
    }
}
