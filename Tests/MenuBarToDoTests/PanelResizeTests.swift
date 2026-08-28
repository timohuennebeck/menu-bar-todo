import XCTest
@testable import MenuBarToDo

final class PanelResizeTests: XCTestCase {
    private func makeDefaults(_ name: String = #function) -> UserDefaults {
        let defaults = UserDefaults(suiteName: "PanelResizeTests.\(name)")!
        defaults.removePersistentDomain(forName: "PanelResizeTests.\(name)")
        return defaults
    }

    func testListHeightDefaultsToTheDesignCap() {
        XCTAssertEqual(PanelSettings(defaults: makeDefaults()).listMaxHeight, Theme.listMaxHeight)
    }

    func testListHeightSurvivesAcrossInstances() {
        let defaults = makeDefaults()
        PanelSettings(defaults: defaults).listMaxHeight = 600
        XCTAssertEqual(PanelSettings(defaults: defaults).listMaxHeight, 600)
    }

    /// A stored value below the design cap (older build, hand-edited defaults) must not
    /// shrink the panel below what it has always been.
    func testStoredValueBelowTheCapIsIgnored() {
        let defaults = makeDefaults()
        defaults.set(100, forKey: "panelListMaxHeight")
        XCTAssertEqual(PanelSettings(defaults: defaults).listMaxHeight, Theme.listMaxHeight)
    }

    /// The drag can never make the list shorter than the design cap, nor taller than the
    /// room left on screen; in between it passes through unchanged.
    func testClampKeepsTheListBetweenTheCapAndTheScreen() {
        XCTAssertEqual(PanelSettings.clampListHeight(100, available: 800), Theme.listMaxHeight)
        XCTAssertEqual(PanelSettings.clampListHeight(600, available: 800), 600)
        XCTAssertEqual(PanelSettings.clampListHeight(900, available: 800), 800)
    }

    /// A tiny screen (or a panel dragged near the bottom) never inverts the clamp.
    func testClampNeverGoesBelowTheCapEvenWhenThereIsNoRoom() {
        XCTAssertEqual(PanelSettings.clampListHeight(600, available: 200), Theme.listMaxHeight)
    }

    /// Same reason as the drag grip: the first click into the inactive app must start
    /// the resize, not just activate the panel.
    @MainActor
    func testResizeGripAcceptsFirstMouse() {
        XCTAssertTrue(ResizeGripArea.GripView().acceptsFirstMouse(for: nil))
    }
}

final class PanelWidthTests: XCTestCase {
    private func makeDefaults(_ name: String = #function) -> UserDefaults {
        let defaults = UserDefaults(suiteName: "PanelWidthTests.\(name)")!
        defaults.removePersistentDomain(forName: "PanelWidthTests.\(name)")
        return defaults
    }

    func testWidthDefaultsToTheDesignWidth() {
        XCTAssertEqual(PanelSettings(defaults: makeDefaults()).panelWidth, Theme.panelWidth)
    }

    func testWidthSurvivesAcrossInstances() {
        let defaults = makeDefaults()
        PanelSettings(defaults: defaults).panelWidth = 480
        XCTAssertEqual(PanelSettings(defaults: defaults).panelWidth, 480)
    }

    func testStoredWidthBelowTheDesignIsIgnored() {
        let defaults = makeDefaults()
        defaults.set(100, forKey: "panelWidth")
        XCTAssertEqual(PanelSettings(defaults: defaults).panelWidth, Theme.panelWidth)
    }

    /// Between the design width and the hard maximum, capped further by the screen.
    func testClampKeepsTheWidthBetweenTheDesignAndTheRoom() {
        XCTAssertEqual(PanelSettings.clampWidth(100, available: 1000), Theme.panelWidth)
        XCTAssertEqual(PanelSettings.clampWidth(480, available: 1000), 480)
        XCTAssertEqual(PanelSettings.clampWidth(900, available: 1000), PanelSettings.maxWidth)
        XCTAssertEqual(PanelSettings.clampWidth(480, available: 300), Theme.panelWidth)
        XCTAssertEqual(PanelSettings.clampWidth(480, available: 450), 450)
    }

    /// Widening only adds columns: the landscape keeps the height the design width gives
    /// it, so the hills never outgrow the 150 pt band.
    func testWiderSceneKeepsTheDesignHeight() {
        let narrow = SurfaceView.sceneSize(forWidth: Theme.panelWidth)
        let wide = SurfaceView.sceneSize(forWidth: 500)
        XCTAssertEqual(wide.height, narrow.height)
        XCTAssertGreaterThan(wide.width, narrow.width)
    }
}
