import AppKit
import XCTest
@testable import MenuBarToDo

final class PixelSceneTests: XCTestCase {
    private func pixels(_ image: CGImage) -> Data {
        let rep = NSBitmapImageRep(cgImage: image)
        return rep.representation(using: .png, properties: [:]) ?? Data()
    }

    private let kinds: [PixelScene.Kind] = [.meadow, .dusk, .night, .coast]

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
        for kind in kinds {
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

    /// Ticking a task off makes the computers cheer, so the frame must actually change.
    func testCheckingOffChangesTheFrame() {
        for kind in kinds {
            let idle = scene(kind)
            let cheering = scene(kind)
            cheering.celebratedAt = 2.9 // mid-cheer at t = 3
            XCTAssertNotEqual(pixels(idle.render(time: 3.0)), pixels(cheering.render(time: 3.0)),
                              "\(kind): the check-off does not show in the scene")
        }
    }

    /// The cheer is derived from the elapsed time like everything else, so a rebuild
    /// during it — a panel resize, which a check-off causes as the row collapses — must
    /// not restart or skip it.
    func testCheerSurvivesARebuildMidAnimation() {
        for kind in kinds {
            let running = scene(kind)
            running.celebratedAt = 2.5
            var frame: CGImage?
            for step in 0...54 { frame = running.render(time: Double(step) / 18) }

            let rebuilt = scene(kind)
            rebuilt.celebratedAt = 2.5
            XCTAssertEqual(pixels(try! XCTUnwrap(frame)), pixels(rebuilt.render(time: 3.0)),
                           "\(kind): the scene jumps when rebuilt mid-cheer")
        }
    }

    /// It has to land back exactly on the idle bob, or the computers would sit at an
    /// offset for the rest of the session.
    func testCheerSettlesBackToIdle() {
        for kind in kinds {
            let idle = scene(kind)
            let settled = scene(kind)
            settled.celebratedAt = 0.5
            XCTAssertEqual(pixels(idle.render(time: 6.0)), pixels(settled.render(time: 6.0)),
                           "\(kind): the cheer leaves the scene changed")
        }
    }
}

final class CheerTriggerTests: XCTestCase {
    /// The scene reacts to a check-off, so ticking a task off has to announce itself.
    func testTickingOffAnnouncesTheCheckOff() {
        let store = TaskStore(persistence: nil)
        var cheers = 0
        store.onTaskCompleted = { cheers += 1 }
        let id = try! XCTUnwrap(store.items.first?.id)

        store.beginComplete(id, sound: false)
        XCTAssertEqual(cheers, 1)

        // beginComplete already guards double clicks; the cheer must not double either.
        store.beginComplete(id, sound: false)
        XCTAssertEqual(cheers, 1)
    }

    /// Reopening the done list must not set the computers off.
    func testUncheckingDoesNotCheer() {
        let store = TaskStore(persistence: nil)
        let id = try! XCTUnwrap(store.items.first?.id)
        store.complete(id)
        var cheers = 0
        store.onTaskCompleted = { cheers += 1 }
        store.restore(id)
        XCTAssertEqual(cheers, 0)
    }
}

