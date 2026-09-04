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

enum CockpitPalette {
    static let background = Color(red: 0.05, green: 0.06, blue: 0.07)
    static let header = Color.black.opacity(0.4)
    static let bayBackground = Color.white.opacity(0.02)
    static let border = Color.white.opacity(0.06)
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
