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
