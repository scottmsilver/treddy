import SwiftUI

/// Design system — leans on Apple's semantic colors wherever possible.
/// Custom values only where the system colors don't fit (background gradient).
enum AppColors {
    // Background — subtle warm gradient, darker than systemBackground
    static let bgGradient = LinearGradient(
        colors: [
            Color(red: 0.07, green: 0.07, blue: 0.06),
            Color(red: 0.09, green: 0.09, blue: 0.07),
            Color(red: 0.07, green: 0.07, blue: 0.06),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let bg = Color(red: 0.07, green: 0.07, blue: 0.06)

    // Card backgrounds — use system fills for glass compatibility
    static let card = Color(.systemGray6)
    static let elevated = Color(.systemGray5)

    // Text — use Apple's semantic hierarchy
    static let text = Color(.label)
    static let text2 = Color(.secondaryLabel)
    static let text3 = Color(.tertiaryLabel)

    // Accents — Apple's system colors (tuned for dark mode)
    static let green = Color.green
    static let red = Color(.systemRed)
    static let yellow = Color(.systemYellow)
    static let purple = Color(.systemPurple)
}
