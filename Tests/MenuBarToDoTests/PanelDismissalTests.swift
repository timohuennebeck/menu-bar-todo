import XCTest
@testable import MenuBarToDo

final class PanelDismissalTests: XCTestCase {
    /// Unpinned, the panel is a transient popover: everything dismisses it.
    func testUnpinnedPanelDismissesOnEveryCause() {
        for cause in PanelWindowController.Dismissal.allCases {
            XCTAssertTrue(PanelWindowController.dismisses(cause, pinned: false),
                          "\(cause) must close an unpinned panel")
        }
    }

    /// Pinned, incidental focus changes leave it alone — that is the whole point.
    func testPinnedPanelSurvivesIncidentalFocusChanges() {
        XCTAssertFalse(PanelWindowController.dismisses(.outsideClick, pinned: true))
        XCTAssertFalse(PanelWindowController.dismisses(.ownAppClick, pinned: true))
        XCTAssertFalse(PanelWindowController.dismisses(.resignKey, pinned: true))
    }

    /// Esc stays an escape hatch: without it a pinned panel could only be closed
    /// from the status item.
    func testEscapeClosesEvenWhenPinned() {
        XCTAssertTrue(PanelWindowController.dismisses(.escape, pinned: true))
    }
}

final class PanelSettingsTests: XCTestCase {
    private func makeDefaults(_ name: String = #function) -> UserDefaults {
        let defaults = UserDefaults(suiteName: "PanelSettingsTests.\(name)")!
        defaults.removePersistentDomain(forName: "PanelSettingsTests.\(name)")
        return defaults
    }

    func testDefaultsToUnpinned() {
        XCTAssertFalse(PanelSettings(defaults: makeDefaults()).isPinned)
    }

    func testPinSurvivesAcrossInstances() {
        let defaults = makeDefaults()
        PanelSettings(defaults: defaults).isPinned = true
        XCTAssertTrue(PanelSettings(defaults: defaults).isPinned)

        PanelSettings(defaults: defaults).isPinned = false
        XCTAssertFalse(PanelSettings(defaults: defaults).isPinned)
    }
}
