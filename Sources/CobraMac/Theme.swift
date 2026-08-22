import SwiftUI

/// Cobra's visual language: matte black surfaces, one acid-green accent.
///
/// The HUD floats over other people's apps, so it commits to its own dark
/// palette rather than following the system appearance — a light-mode HUD would
/// glare over a dark editor, and vice versa.
enum Theme {
    enum Palette {
        static let background = Color(hex: 0x0B0B0D)
        static let surface = Color(hex: 0x141417)
        static let border = Color(hex: 0x2A2A30)
        static let text = Color(hex: 0xE8E8EA)
        static let textDim = Color(hex: 0x8A8A93)
        static let venom = Color(hex: 0x7CFF4F)
        static let danger = Color(hex: 0xFF4F5E)
    }

    enum Metrics {
        static let hudCornerRadius: CGFloat = 18
        static let hudHeight: CGFloat = 36
        static let hudPadding: CGFloat = 14
        /// Distance between the caret and the top of the HUD.
        static let caretGap: CGFloat = 12
    }

    enum Typeface {
        /// Monospaced digits keep the level meter from jittering the layout.
        static let label = Font.system(size: 12, weight: .medium, design: .rounded)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
