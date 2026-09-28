import SwiftUI

struct MoonpondTheme {
    static let baseDarkGreen = Color(red: 0.04, green: 0.08, blue: 0.06)
    static let neonAccent = Color(red: 0.3, green: 0.8, blue: 0.6)
    static let neonCyan = Color(red: 0.3, green: 0.7, blue: 0.8)
    static let glassOverlay = Color.black.opacity(0.45)
    
    // Very subtle, low contrast gradient for the Bento borders
    static let subtleNeonGradient = LinearGradient(
        colors: [
            neonAccent.opacity(0.2), 
            neonCyan.opacity(0.1), 
            Color.white.opacity(0.05)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
