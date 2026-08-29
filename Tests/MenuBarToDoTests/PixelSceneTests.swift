import AppKit
import XCTest
@testable import MenuBarToDo

final class PixelSceneTests: XCTestCase {
    private func pixels(_ image: CGImage) -> Data {
        let rep = NSBitmapImageRep(cgImage: image)
        return rep.representation(using: .png, properties: [:]) ?? Data()
    }

    private let kinds: [PixelScene.Kind] = PixelScene.Kind.allCases

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

    /// Growing the panel must reveal more ground, not redraw it. The pebbles' count and
    /// spread were derived from the panel's height and the roots stopped consuming their
    /// RNG at the bottom edge, so every resize reshuffled the whole underground — the
    /// soil twitched while a group collapsed.
    func testGrowingTheSceneKeepsTheGroundItAlreadyDrew() {
        // Every kind: the bare-ground scenes once derived their soil fade from the
        // panel height, so each resize re-tinted ground that was already drawn.
        for kind in kinds {
            let short = PixelScene(width: 165, height: 165 * 10 / 16, totalHeight: 240, kind: kind)
            let tall = PixelScene(width: 165, height: 165 * 10 / 16, totalHeight: 400, kind: kind)
            let a = short.render(time: 2.0), b = tall.render(time: 2.0)

            let overlap = CGRect(x: 0, y: 0, width: 165, height: 240)
            let cropA = try! XCTUnwrap(a.cropping(to: overlap))
            let cropB = try! XCTUnwrap(b.cropping(to: overlap))
            XCTAssertEqual(pixels(cropA), pixels(cropB),
                           "\(kind): the ground is redrawn differently when the panel is taller")
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


final class ScenePreferenceTests: XCTestCase {
    private func settings() -> PanelSettings {
        let defaults = UserDefaults(suiteName: "scene-tests-\(UUID().uuidString)")!
        return PanelSettings(defaults: defaults)
    }

    /// One button has to show every landscape and hand the choice back to the clock,
    /// or a picked one would be a one-way door.
    func testCyclingShowsEveryLandscapeAndReturnsToTheClock() {
        let s = settings()
        var shown: [PixelScene.Kind?] = []
        for _ in 0..<(PixelScene.Kind.pickable.count + 1) {
            s.cycleScene()
            shown.append(s.scene)
        }
        XCTAssertEqual(Set(shown.compactMap { $0 }), Set(PixelScene.Kind.pickable), "a landscape is never shown")
        XCTAssertEqual(shown.filter { $0 == nil }.count, 1, "the cycle never gets back to the clock, or does so twice")
        XCTAssertEqual(shown.last, .some(nil), "the lap doesn't end on the clock")
    }

    /// The meadow, golden hour and night are the clock's alone: one landscape at three
    /// times of day. Pinning golden hour would leave an evening sky over the panel at ten
    /// in the morning, and pinning the meadow in the evening read as a duplicate of the
    /// golden hour before it — the clock's own scene is never a step in the cycle.
    func testTheClocksOwnScenesCannotBePicked() {
        let s = settings()
        for _ in 0...PixelScene.Kind.pickable.count * 2 {
            s.cycleScene()
            if let k = s.scene { XCTAssertFalse(PixelScene.Kind.clocks.contains(k), "\(k) is the clock's") }
        }
        for hour in [9, 18, 23] {
            XCTAssertTrue(PixelScene.Kind.clocks.contains(PixelScene.kind(forHour: hour)), "hour \(hour)")
        }
    }

    /// Every click has to change the picture — no two neighbours in the ring may paint
    /// the same landscape, whatever the hour.
    func testEveryClickChangesThePicture() {
        for hour in [9, 18, 23] {
            let clock = PixelScene.kind(forHour: hour)
            let s = settings()
            var shown = clock
            for step in 0...PixelScene.Kind.pickable.count * 2 {
                s.cycleScene()
                let next = s.scene ?? clock
                XCTAssertNotEqual(next, shown, "hour \(hour), step \(step): the panel looks the same afterwards")
                shown = next
            }
        }
    }

    /// A stored scene that is no longer pickable (the meadow, pinned before it moved to
    /// the clock) must not strand the button: the click still moves on.
    func testAStoredSceneOffTheRingStillStepsOn() {
        let s = settings()
        s.scene = .meadow
        s.cycleScene()
        XCTAssertNotNil(s.scene)
        XCTAssertNotEqual(s.scene, .meadow, "the click changes nothing")
    }

    /// The choice is a window preference: it has to survive a restart.
    func testThePickedSceneIsRemembered() {
        let defaults = UserDefaults(suiteName: "scene-tests-\(UUID().uuidString)")!
        let first = PanelSettings(defaults: defaults)
        first.scene = .desert
        XCTAssertEqual(PanelSettings(defaults: defaults).scene, .desert)
        XCTAssertEqual(PanelSettings.storedScene(defaults: defaults), .desert)

        first.scene = nil
        XCTAssertNil(PanelSettings(defaults: defaults).scene)
        XCTAssertNil(PanelSettings.storedScene(defaults: defaults), "the clock choice must not be stored")
    }

    /// The landscape is an AppKit view outside the observation graph, so a switch has
    /// to announce itself or the panel keeps the old scene until it is reopened.
    func testSwitchingTheSceneAnnouncesItself() {
        let s = settings()
        var posts = 0
        let token = NotificationCenter.default.addObserver(forName: .panelSceneChanged, object: nil, queue: nil) { _ in
            posts += 1
        }
        defer { NotificationCenter.default.removeObserver(token) }
        s.cycleScene()
        XCTAssertEqual(posts, 1)
    }
}
