import AppKit
import SwiftUI
import XCTest
@testable import MenuBarToDo

/// The chips on the pixel landscape are small and sit in a bare corner, where a
/// fraction of a point off-centre is visible. SwiftUI centres a Text's *line box*,
/// not its ink, so a character that leaves the descender space empty renders low —
/// that is why these use SF Symbols. Measured off the real views, not a mock-up.
final class GlyphCenteringTests: XCTestCase {
    /// Renders `view` at 16× and returns the glyph ink's offset from the chip centre, in points.
    @MainActor
    private func inkOffset(_ view: some View, box: CGFloat = 22) throws -> (dx: CGFloat, dy: CGFloat) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 16
        let cg = try XCTUnwrap(renderer.cgImage)
        let n = cg.width, m = cg.height
        var buf = [UInt8](repeating: 0, count: n * m * 4)
        let ctx = try XCTUnwrap(CGContext(data: &buf, width: n, height: m, bitsPerComponent: 8,
                                          bytesPerRow: n * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: n, height: m))

        func bounds(_ keep: (_ red: UInt8, _ alpha: UInt8) -> Bool) throws -> CGRect {
            var minX = n, maxX = -1, minY = m, maxY = -1
            for y in 0..<m {
                for x in 0..<n {
                    let i = (y * n + x) * 4
                    guard keep(buf[i], buf[i + 3]) else { continue }
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                }
            }
            try XCTAssertGreaterThan(maxX, -1, "nothing matched")
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }
        let chip = try bounds { _, alpha in alpha > 10 }              // the chip itself
        let ink = try bounds { red, alpha in alpha > 10 && red > 140 } // the light glyph on it
        let scale = CGFloat(n) / box
        return (dx: (ink.midX - chip.midX) / scale, dy: (ink.midY - chip.midY) / scale)
    }

    /// One device pixel on a 2× display is 0.5 pt; anything under a tenth of a point
    /// cannot be seen and leaves room for the symbol being re-cut in a later macOS.
    private let tolerance: CGFloat = 0.1

    @MainActor
    func testCloseGlyphIsCentredInItsChip() throws {
        let (dx, dy) = try inkOffset(IconButton(systemImage: "xmark", help: "", onScene: true) {})
        XCTAssertEqual(dx, 0, accuracy: tolerance, "✕ off-centre horizontally by \(dx) pt")
        XCTAssertEqual(dy, 0, accuracy: tolerance, "✕ off-centre vertically by \(dy) pt")
    }

    @MainActor
    func testPinGlyphIsCentredInItsChip() throws {
        let settings = PanelSettings(defaults: UserDefaults(suiteName: "GlyphCenteringTests")!)
        let (dx, dy) = try inkOffset(PinButton().environment(settings))
        XCTAssertEqual(dx, 0, accuracy: tolerance, "pin off-centre horizontally by \(dx) pt")
        XCTAssertEqual(dy, 0, accuracy: tolerance, "pin off-centre vertically by \(dy) pt")
    }

    /// Guards the reason the ✕ is an SF Symbol: the old Text("✕") was visibly low.
    @MainActor
    func testTextGlyphWouldNotBeCentred() throws {
        let (_, dy) = try inkOffset(
            Text("✕").font(.system(size: 12)).foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(SceneChip.background(hovering: false), in: SceneChip.shape))
        XCTAssertGreaterThan(abs(dy), tolerance,
                             "Text(\"✕\") is centred after all — the SF Symbol switch can be reverted")
    }
}
