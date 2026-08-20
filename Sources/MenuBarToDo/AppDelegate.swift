import AppKit
import SwiftUI

/// Owns the status-bar item and the floating panel that hosts the SwiftUI UI.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var panel: PanelWindowController?
    /// Preview/debug runs never touch the real tasks.json: routes like "empty" and
    /// "complete-anim" mutate the store destructively, and the next persist() would
    /// write that over the user's data.
    private static let isPreviewRun: Bool = {
        let env = ProcessInfo.processInfo.environment
        return env["MENUBAR_TODO_PREVIEW_WINDOW"] == "1" || env["MENUBAR_TODO_PREVIEW_ROUTE"] != nil
    }()
    private lazy var store = TaskStore(persistence: Self.isPreviewRun ? nil : .default)

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Accessory apps have no Dock icon and don't take over the menu bar.
        NSApp.setActivationPolicy(.accessory)
        // A main menu is still required so ⌘C/⌘V/⌘A/⌘Z work inside text fields.
        NSApp.mainMenu = MainMenu.make()

        configureStatusItem()
        configurePanel()
        _ = CompletionSound.shared // render the chime up front so the first check-off isn't late

        // Debug aids:
        //   MENUBAR_TODO_AUTO_OPEN=1       opens the panel right after launch.
        //   MENUBAR_TODO_PREVIEW_WINDOW=1  additionally shows the UI in a plain window
        //                                  (handy when a menu-bar manager hides the status item).
        let env = ProcessInfo.processInfo.environment
        if env["MENUBAR_TODO_AUTO_OPEN"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.showPanel() }
        }
        if env["MENUBAR_TODO_PREVIEW_WINDOW"] == "1" {
            // MENUBAR_TODO_PREVIEW_ROUTE=list|add|calendar|edit|done|drag-group|drag-row|… pre-selects a view.
            store.applyDebugRoute(env["MENUBAR_TODO_PREVIEW_ROUTE"])
            showPreviewWindow()
            // MENUBAR_TODO_PREVIEW_POPOVER=1 additionally opens the real floating panel next
            // to the preview window and prints its window id for frame captures.
            if env["MENUBAR_TODO_PREVIEW_POPOVER"] == "1", let frame = previewWindow?.frame {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    guard let self else { return }
                    let anchor = NSRect(x: frame.maxX + 40 + Theme.panelWidth, y: frame.maxY, width: 0, height: 0)
                    self.showPanel(below: anchor)
                    if let number = self.panel?.windowNumber {
                        print("POPOVER_WINDOW_ID=\(number)")
                        fflush(stdout)
                    }
                }
            }
        }
    }

    private var previewWindow: NSWindow?

    private func showPreviewWindow() {
        let host = NSHostingController(rootView: PanelView().environment(store))
        host.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: host)
        window.title = "Menu Bar To-Do (Preview)"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.setFrameTopLeftPoint(NSPoint(x: 80, y: (NSScreen.main?.visibleFrame.maxY ?? 900) - 400))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        previewWindow = window
        // Lets Scripts/snapshot.sh capture exactly this window (`screencapture -l <id>`).
        print("PREVIEW_WINDOW_ID=\(window.windowNumber)")
        fflush(stdout)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // MARK: - Status item

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "list.bullet", accessibilityDescription: "To-Do")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "Menu Bar To-Do"
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
            return
        }
        if panel?.isShown == true {
            panel?.close()
        } else {
            showPanel()
        }
    }

    /// Right-click on the status item: the only place to quit an accessory app.
    private func showContextMenu() {
        guard let item = statusItem else { return }
        let menu = NSMenu()
        menu.addItem(withTitle: "Menu Bar To-Do beenden",
                     action: #selector(NSApplication.terminate(_:)),
                     keyEquivalent: "q")
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil // detach again so left-click keeps toggling the panel
    }

    // MARK: - Panel

    private func configurePanel() {
        let root = PanelView(onSizeChange: { [weak self] size in
            // The collapse animation is layout-driven (see TaskListView.collapsible), so the
            // reported size changes every frame and the window simply follows it.
            self?.panel?.resize(to: size)
        })
        .environment(store)
        let panel = PanelWindowController(rootView: root)
        // Esc inside a form cancels the form (SwiftUI's onExitCommand); elsewhere it closes the panel.
        panel.shouldCloseOnEscape = { [weak self] in
            guard let self else { return true }
            switch self.store.route {
            case .add, .edit: return false
            default: return true
            }
        }
        self.panel = panel
    }

    /// Screen rect of the status item button (falls back to the top-right screen corner
    /// when a menu-bar manager has moved the item off-screen).
    private func statusItemScreenRect() -> NSRect {
        if let button = statusItem?.button, let window = button.window {
            let rect = window.convertToScreen(button.convert(button.bounds, to: nil))
            if NSScreen.screens.contains(where: { $0.frame.intersects(rect) }) { return rect }
        }
        let screen = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSRect(x: screen.maxX - 40, y: screen.maxY - 24, width: 28, height: 22)
    }

    private func showPanel(below anchor: NSRect? = nil) {
        store.panelWillOpen()
        panel?.show(below: anchor ?? statusItemScreenRect())
    }
}

/// Minimal main menu: App (Quit) + Edit (clipboard & undo) so the standard
/// text-editing key equivalents reach the popover's text fields.
enum MainMenu {
    static func make() -> NSMenu {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Menu Bar To-Do beenden",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Bearbeiten")
        edit.addItem(withTitle: "Widerrufen", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Wiederholen", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Ausschneiden", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Kopieren", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Einsetzen", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Alles auswählen", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        return main
    }
}
