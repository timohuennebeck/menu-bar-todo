import AppKit
import XCTest
@testable import MenuBarToDo

final class PixelSceneTests: XCTestCase {
    private func pixels(_ image: CGImage) -> Data {
        let rep = NSBitmapImageRep(cgImage: image)
        return rep.representation(using: .png, properties: [:]) ?? Data()
    }

    private func scene(_ kind: PixelScene.Kind) -> PixelScene {
        // The panel's real proportions: 330 pt wide at 2 pt per scene pixel, 16:10 scene,
        // extended downwards for the list below it.
        PixelScene(width: 165, height: 165 * 10 / 16, totalHeight: 260, kind: kind)
    }

    /// A route change resizes the panel, which rebuilds the scene at the new height
    /// (SurfaceView.setFrameSize). The animation must not restart when that happens:
    /// clouds, gulls and motes used to be advanced one step per frame and stored, so a
    /// rebuild snapped them back to their seeded start — a visible jump when opening a
    /// task or the add form. Everything the frame shows must come from `time` alone.
    func testRebuildingMidAnimationKeepsTheFrameIdentical() {
        for kind in [PixelScene.Kind.meadow, .dusk, .night, .coast] {
            let running = scene(kind)
            // Play it forward the way the 18 fps timer does.
            var frame: CGImage?
            for step in 0...54 { frame = running.render(time: Double(step) / 18) }
            let advanced = pixels(try! XCTUnwrap(frame))

            // Same instant, but reached by a scene that was just rebuilt.
            let rebuilt = pixels(scene(kind).render(time: 3.0))

            XCTAssertEqual(advanced, rebuilt, "\(kind): the scene jumps when it is rebuilt")
        }
    }

    /// The frame is a pure function of time, so it must also be reproducible out of order.
    func testFrameDependsOnlyOnTime() {
        let a = scene(.meadow), b = scene(.meadow)
        _ = a.render(time: 10)
        XCTAssertEqual(pixels(a.render(time: 2.5)), pixels(b.render(time: 2.5)))
    }
}
