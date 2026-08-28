import AppKit
import Carbon.HIToolbox
import XCTest
@testable import MenuBarToDo

final class HotKeyTests: XCTestCase {
    func testDefaultCombos() {
        XCTAssertEqual(KeyCombo.togglePanel.keyCode, UInt32(kVK_ANSI_T))
        XCTAssertEqual(KeyCombo.togglePanel.modifiers, [.control, .command])
        XCTAssertEqual(KeyCombo.togglePanel.key, "T")
        XCTAssertEqual(KeyCombo.addTask.keyCode, UInt32(kVK_ANSI_N))
        XCTAssertEqual(KeyCombo.addTask.modifiers, [.control, .command])
        XCTAssertEqual(KeyCombo.addTask.key, "N")
        // Two identical combos can't both register — the second RegisterEventHotKey fails.
        XCTAssertNotEqual(KeyCombo.togglePanel, KeyCombo.addTask)
    }

    func testCarbonModifiersMapEveryFlag() {
        func combo(_ modifiers: NSEvent.ModifierFlags) -> KeyCombo {
            KeyCombo(keyCode: 0, modifiers: modifiers, key: "")
        }
        XCTAssertEqual(combo([.command]).carbonModifiers, UInt32(cmdKey))
        XCTAssertEqual(combo([.shift]).carbonModifiers, UInt32(shiftKey))
        XCTAssertEqual(combo([.option]).carbonModifiers, UInt32(optionKey))
        XCTAssertEqual(combo([.control]).carbonModifiers, UInt32(controlKey))
        XCTAssertEqual(KeyCombo.togglePanel.carbonModifiers, UInt32(controlKey | cmdKey))
        // Flags Carbon has no notion of (caps lock, function) must not leak into the mask.
        XCTAssertEqual(combo([.command, .capsLock, .function]).carbonModifiers, UInt32(cmdKey))
    }

    func testDisplayStringUsesMacSymbolOrder() {
        // macOS convention: ⌃ ⌥ ⇧ ⌘ then the key.
        XCTAssertEqual(KeyCombo.togglePanel.displayString, "⌃⌘T")
        XCTAssertEqual(KeyCombo.addTask.displayString, "⌃⌘N")
        XCTAssertEqual(KeyCombo(keyCode: 0, modifiers: [.command, .shift, .option, .control], key: "T").displayString,
                       "⌃⌥⇧⌘T")
    }

    func testRouteIsForm() {
        XCTAssertTrue(Route.add.isForm)
        XCTAssertTrue(Route.edit(UUID()).isForm)
        XCTAssertFalse(Route.list.isForm)
        XCTAssertFalse(Route.done.isForm)
    }

    func testAddShortcutLeavesVisibleFormsAloneButNotStaleEdits() {
        // Panel open: never disturb what the user is looking at.
        XCTAssertFalse(AppDelegate.opensAddForm(from: .add, panelShown: true))
        XCTAssertFalse(AppDelegate.opensAddForm(from: .edit(UUID()), panelShown: true))
        XCTAssertTrue(AppDelegate.opensAddForm(from: .list, panelShown: true))
        XCTAssertTrue(AppDelegate.opensAddForm(from: .done, panelShown: true))
        // Panel closed: an add draft survives, but a left-over edit form must not reopen.
        XCTAssertFalse(AppDelegate.opensAddForm(from: .add, panelShown: false))
        XCTAssertTrue(AppDelegate.opensAddForm(from: .edit(UUID()), panelShown: false))
        XCTAssertTrue(AppDelegate.opensAddForm(from: .list, panelShown: false))
    }
}
