// The ScreenPulse mark: three rows of dots (1, 2, 3) — the blink code for A, B and C.

import AppKit

enum BrandIcon {
    /// Dot centres on a 3×3 grid, top row first: 1 dot, 2 dots, 3 dots.
    private static let dots: [(col: Int, row: Int)] = [(0, 0), (0, 1), (1, 1), (0, 2), (1, 2), (2, 2)]

    /// Menu bar icon. A template image, so it follows the light/dark menu bar.
    static func menuBarImage() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let img = NSImage(size: size, flipped: true) { _ in
            NSColor.black.setFill()
            let d: CGFloat = 4.0, step: CGFloat = 5.5, origin: CGFloat = 1.5
            for dot in dots {
                let rect = NSRect(x: origin + CGFloat(dot.col) * step, y: origin + CGFloat(dot.row) * step, width: d, height: d)
                NSBezierPath(ovalIn: rect).fill()
            }
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = AppInfo.name
        return img
    }
}
