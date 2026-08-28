import AppKit
import SwiftUI

/// Owns the status-bar item and the floating panel that hosts the SwiftUI UI.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var panel: PanelWindowController?
    private lazy var hotKeys = GlobalHotKeys()
    /// Preview/debug runs never touch the real tasks.json: routes like "empty" and
    /// "complete-anim" mutate the store destructively, and the next persist() would
    /// write that over the user's data.
    private static let isPreviewRun: Bool = {
        let env = ProcessInfo.processInfo.environment
        return env["MENUBAR_TODO_PREVIEW_WINDOW"] == "1" || env["MENUBAR_TODO_PREVIEW_ROUTE"] != nil
    }()
    private lazy var store = TaskStore(persistence: Self.isPreviewRun ? nil : .default)
    /// Window chrome the user controls (currently just the pin). Unlike the store this
    /// is real UserDefaults even in preview runs — it holds no task data to corrupt.
    private let panelSettings = PanelSettings()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Accessory apps have no Dock icon and don't take over the menu bar.
        NSApp.setActivationPolicy(.accessory)
        // A main menu is still required so ⌘C/⌘V/⌘A/⌘Z work inside text fields.
        NSApp.mainMenu = MainMenu.make()

        configureStatusItem()
        configurePanel()
        configureHotKeys()
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
                    // MENUBAR_TODO_DUMP_PNG=/path.png writes the rendered panel after a second.
                    if let path = env["MENUBAR_TODO_DUMP_PNG"] {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                            self?.panel?.dumpPNG(to: path)
                            print("DUMPED=\(path)"); fflush(stdout)
                        }
                    }
                }
            }
        }
    }

    private var previewWindow: NSWindow?

    private func showPreviewWindow() {
        let host = NSHostingController(rootView: PanelView().environment(store).environment(panelSettings))
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

    /// A check-off only persists ~1 s after the click (once its animation ends);
    /// quitting inside that window must not lose an already-confirmed completion.
    func applicationWillTerminate(_ notification: Notification) {
        store.flushPendingCompletions()
    }

    // MARK: - Status item

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.toolTip = "Menu Bar To-Do"
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
        observeBadge()
    }

    /// Keeps the icon's badge (today + overdue) in sync with the store. Observation
    /// tracking fires once per change, so the tracking is re-armed after every update;
    /// that also covers the midnight rollover, which changes `store.today`.
    private func observeBadge() {
        withObservationTracking {
            statusItem?.button?.image = StatusIcon.image(badge: store.badgeCount)
        } onChange: { [weak self] in
            DispatchQueue.main.async { self?.observeBadge() }
        }
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        let event = NSApp.currentEvent
        // Right-click or Control-click (the trackpad/one-button equivalent) opens
        // the context menu — the app's only quit affordance.
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showContextMenu()
            return
        }
        togglePanel()
    }

    // MARK: - Keyboard shortcuts

    /// The combinations are defined on KeyCombo and work system-wide. One the system
    /// refuses (held by another Carbon hotkey) is logged and skipped — never fatal.
    /// Preview runs stay out of it: a snapshot taken while the real app runs would
    /// otherwise steal (or fail to get) its shortcuts.
    private func configureHotKeys() {
        guard !Self.isPreviewRun else { return }
        hotKeys.register(.togglePanel) { [weak self] in self?.togglePanel() }
        hotKeys.register(.addTask) { [weak self] in self?.openAddTask() }
    }

    private func togglePanel() {
        if panel?.isShown == true {
            panel?.close()
        } else {
            showPanel()
        }
    }

    /// Opens the panel (if needed) in the add form.
    private func openAddTask() {
        let wasShown = panel?.isShown == true
        // Route first, so the panel's first frame is sized for the form, not the list.
        if Self.opensAddForm(from: store.route, panelShown: wasShown) { store.openAdd() }
        if !wasShown { showPanel() }
    }

    /// Whether the add shortcut switches to the add form. A form the user is looking
    /// at is left alone so the shortcut can't wipe a half-typed task, and an add draft
    /// survives a panel close for the same reason. An edit form behind a *closed* panel
    /// does not win: `route` outlives the panel, and the shortcut promises the add form.
    nonisolated static func opensAddForm(from route: Route, panelShown: Bool) -> Bool {
        switch route {
        case .add: return false
        case .edit: return !panelShown
        case .list, .done: return true
        }
    }

    /// Right-click on the status item: the only place to quit an accessory app.
    private func showContextMenu() {
        guard let item = statusItem else { return }
        let menu = NSMenu()
        // Twins of the global hotkeys, with the combination spelled out for discoverability.
        // AppKit reads shift off the *case* of the key equivalent: an uppercase letter
        // draws (and binds) ⇧ even when the mask omits it, so only shifted combos get
        // the uppercase form — ⌃⌘T would otherwise show up as ⌃⇧⌘T.
        func addShortcut(_ title: String, combo: KeyCombo, action: Selector) {
            let key = combo.modifiers.contains(.shift) ? combo.key : combo.key.lowercased()
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = combo.modifiers
            item.target = self
        }
        addShortcut("Ein-/Ausblenden", combo: .togglePanel, action: #selector(menuTogglePanel))
        addShortcut("Task hinzufügen", combo: .addTask, action: #selector(menuAddTask))
        menu.addItem(.separator())
        menu.addItem(withTitle: "Menu Bar To-Do beenden",
                     action: #selector(NSApplication.terminate(_:)),
                     keyEquivalent: "q")
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil // detach again so left-click keeps toggling the panel
    }

    // Both menu actions defer to the next run-loop turn: the menu closes first, and
    // opening the panel on the same turn would have it hang off a status item that is
    // still in its highlighted state.
    @objc private func menuTogglePanel() {
        DispatchQueue.main.async { [weak self] in self?.togglePanel() }
    }

    @objc private func menuAddTask() {
        DispatchQueue.main.async { [weak self] in self?.openAddTask() }
    }

    // MARK: - Panel

    private func configurePanel() {
        let root = PanelView(onSizeChange: { [weak self] size in
            // The collapse animation is layout-driven (see TaskListView.collapsible), so the
            // reported size changes every frame and the window simply follows it.
            self?.panel?.resize(to: size)
        }, onClose: { [weak self] in
            // `panel` is assigned below, before any click can reach this.
            self?.panel?.close()
        })
        .environment(store)
        .environment(panelSettings)
        let panel = PanelWindowController(rootView: root)
        // The status item's own button toggles the panel on mouse-up; the outside-click
        // monitor must not close it on the mouse-down first (that made the click reopen it).
        panel.shouldIgnoreClick = { [weak self] event in
            event.window === self?.statusItem?.button?.window
        }
        // Esc leaves a focused text field first (PanelWindowController), then cancels a
        // form (SwiftUI's onExitCommand), then closes the panel.
        panel.onEscape = { [weak self] in
            guard let self, self.store.route.isForm else { return false }
            self.store.cancel()
            return true
        }
        // Pinned, the panel ignores outside clicks and focus changes; the status item,
        // ⌃⌘T and Esc still close it (PanelWindowController.dismisses).
        panel.isPinned = { [weak self] in self?.panelSettings.isPinned ?? false }
        // Ticking a task off sets the computers in the landscape cheering.
        store.onTaskCompleted = { [weak self] in self?.panel?.celebrate() }
        self.panel = panel
        observePin()
    }

    /// The pin also changes the window level, which is AppKit state the SwiftUI toggle
    /// can't set itself. Re-armed after every change, like observeBadge().
    private func observePin() {
        withObservationTracking {
            _ = panelSettings.isPinned
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                self?.panel?.applyPinnedLevel()
                self?.observePin()
            }
        }
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
