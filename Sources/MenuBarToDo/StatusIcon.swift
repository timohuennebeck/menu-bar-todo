import AppKit

/// The status-bar icon: the clipboard symbol, optionally with a badge — a filled
/// circle in the bottom-right corner with the count knocked out of it. It is a
/// *template* image (alpha only), so it follows the menu bar's light/dark look
/// exactly like the system's own icons; that is also why the digit is a cut-out
/// rather than white-on-red.
enum StatusIcon {
    static let size = NSSize(width: 20, height: 18)
    static let badgeRadius: CGFloat = 5
    /// Bottom-right, overhanging the symbol a little so the circle reads as a badge.
    static let badgeCenter = CGPoint(x: 14.5, y: 5)

    /// "1" … "9", then "9+" — two digits don't fit a 10 pt circle.
    static func badgeText(_ count: Int) -> String { count > 9 ? "9+" : String(count) }

    static func image(badge count: Int) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            drawSymbol(in: rect)
            if count > 0 { drawBadge(text: badgeText(count)) }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = count > 0 ? "To-Do, \(count) fällig" : "To-Do"
        return image
    }

    private static func drawSymbol(in rect: NSRect) {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        guard let symbol = NSImage(systemSymbolName: "list.clipboard.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else {
            // Never leave an invisible status item — it is the app's only entry point.
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 14, weight: .bold),
                                                        .foregroundColor: NSColor.black]
            ("✓" as NSString).draw(at: NSPoint(x: 3, y: 1), withAttributes: attrs)
            return
        }
        let s = symbol.size
        symbol.draw(in: NSRect(x: 1, y: (rect.height - s.height) / 2, width: s.width, height: s.height),
                    from: .zero, operation: .sourceOver, fraction: 1)
    }

    private static func drawBadge(text: String) {
        guard let cg = NSGraphicsContext.current?.cgContext else { return }
        let c = badgeCenter, r = badgeRadius
        // A cleared ring separates the badge from the symbol underneath it.
        cg.saveGState()
        cg.setBlendMode(.clear)
        cg.fillEllipse(in: CGRect(x: c.x - r - 1.2, y: c.y - r - 1.2, width: 2 * (r + 1.2), height: 2 * (r + 1.2)))
        cg.restoreGState()
        NSColor.black.setFill()
        NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)).fill()
        // The number is punched out of the circle.
        let font = NSFont.systemFont(ofSize: text.count > 1 ? 6 : 7.5, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let label = text as NSString
        let bounds = label.boundingRect(with: NSSize(width: 100, height: 100), options: [], attributes: attrs)
        cg.saveGState()
        cg.setBlendMode(.destinationOut)
        label.draw(at: NSPoint(x: c.x - bounds.width / 2, y: c.y - bounds.height / 2 + 0.3), withAttributes: attrs)
        cg.restoreGState()
    }
}
