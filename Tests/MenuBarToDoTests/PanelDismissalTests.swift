import AppKit
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

final class WindowDragAreaTests: XCTestCase {
    /// The scene band must start a window drag on the *first* click, even while the app
    /// is inactive. NSView refuses first mouse by default, so that click is swallowed as
    /// the activating click and never reaches mouseDown — leaving the grip dead until
    /// you click once to focus. Only reachable since the panel can stay open unfocused
    /// (pinned); before that an outside click just closed it.
    @MainActor
    func testDragGripAcceptsFirstMouse() {
        XCTAssertTrue(WindowDragArea.DragView().acceptsFirstMouse(for: nil))
    }
}

final class AddButtonRouteTests: XCTestCase {
    /// The scene band's + replaces the footer link, so it must appear exactly where that
    /// link did: never over a form, where it would be a no-op (.add) or would throw away
    /// what is being edited (.edit).
    func testAddButtonShowsOnlyOutsideForms() {
        XCTAssertTrue(PanelView.showsAddButton(for: .list))
        XCTAssertTrue(PanelView.showsAddButton(for: .done))
        XCTAssertFalse(PanelView.showsAddButton(for: .add))
        XCTAssertFalse(PanelView.showsAddButton(for: .edit(UUID())))
    }
}

final class EscapeRouteTests: XCTestCase {
    private func makeStore() -> TaskStore { TaskStore(persistence: nil) }

    /// The done list is a page on top of the list, like the form: Esc goes back to
    /// the list instead of closing the whole panel.
    func testEscapeLeavesTheDoneList() {
        let store = makeStore()
        store.goDone()
        XCTAssertTrue(store.handleEscape())
        XCTAssertEqual(store.route, .list)
    }

    /// Unchanged: Esc in a form cancels it, keeping the panel open.
    func testEscapeCancelsAForm() {
        let store = makeStore()
        store.openAdd()
        store.draft.title = "halb getippt"
        XCTAssertTrue(store.handleEscape())
        XCTAssertEqual(store.route, .list)
        XCTAssertEqual(store.draft.title, "")

        let task = store.sortedItems[0]
        store.openEdit(task)
        XCTAssertTrue(store.handleEscape())
        XCTAssertEqual(store.route, .list)
    }

    /// On the list itself there is nothing left to leave, so Esc closes the panel.
    func testEscapeOnTheListIsNotHandled() {
        let store = makeStore()
        XCTAssertFalse(store.handleEscape())
        XCTAssertEqual(store.route, .list)
    }
}
