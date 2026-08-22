import AppKit

/// The Cobra mark, rasterised from the shared pixel map.
///
/// Drawn into an `NSImage` rather than a SwiftUI `Canvas`: `NSStatusItem`
/// measures its label view, and `Canvas` reports no intrinsic size, so the menu
/// bar item collapsed to zero width and no icon appeared. An `NSImage` has a
/// real size and is what AppKit expects here.
enum CobraMark {
    /// Monochrome version for the idle menu bar. Marked as a template so macOS
    /// tints it for light and dark menu bars and highlights it when the menu is
    /// open — behaviour a hard-coded colour would lose.
    static let template: NSImage = {
        let image = render(fill: .black, tongue: .black, size: 18)
        image.isTemplate = true
        return image
    }()

    /// Full-colour version, used while Cobra is actually listening.
    static let active: NSImage = render(
        fill: NSColor(srgbRed: 0x7C / 255, green: 0xFF / 255, blue: 0x4F / 255, alpha: 1),
        tongue: NSColor(srgbRed: 0xFF / 255, green: 0x4F / 255, blue: 0x5E / 255, alpha: 1),
        size: 18
    )

    static func render(fill: NSColor, tongue: NSColor, size: CGFloat) -> NSImage {
        let rows = CobraPixels.map
        let columns = rows.map(\.count).max() ?? 1

        return NSImage(size: NSSize(width: size, height: size), flipped: true) { _ in
            // Snap the cell to whole points so the art stays crisp instead of
            // being resampled into mush at menu bar dimensions.
            let cell = (size / CGFloat(max(columns, rows.count))).rounded(.down)
            guard cell > 0 else { return true }

            let originX = (size - cell * CGFloat(columns)) / 2
            let originY = (size - cell * CGFloat(rows.count)) / 2

            for (row, line) in rows.enumerated() {
                for (column, character) in line.enumerated() {
                    switch character {
                    case "#": fill.setFill()
                    case "~": tongue.setFill()
                    default: continue  // "." and "o" are holes.
                    }
                    NSRect(
                        x: originX + CGFloat(column) * cell,
                        y: originY + CGFloat(row) * cell,
                        width: cell,
                        height: cell
                    ).fill()
                }
            }
            return true
        }
    }
}
