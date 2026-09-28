import SwiftUI

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

struct NoiseOverlay: View {
    var body: some View {
        GeometryReader { _ in
            // Fallback noise implementation using repeating linear gradients or standard SwiftUI shapes
            // to simulate grain. In a real app we might load a tiled PNG.
            Color.white.opacity(0.02)
                .blendMode(.screen)
        }
    }
}

struct FrostyBentoModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.black.opacity(0.45))
            .background(VisualEffectView(material: .hudWindow, blendingMode: .withinWindow))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.4), radius: 10, x: 0, y: 5)
    }
}

extension View {
    func frostyBento() -> some View {
        self.modifier(FrostyBentoModifier())
    }
}

enum CockpitFonts {
    static var scaleFactor: CGFloat = 1.5

    static func ultraThin(size: CGFloat) -> Font {
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

    static func code(size: CGFloat, weight: Font.Weight = .regular) -> Font {
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

