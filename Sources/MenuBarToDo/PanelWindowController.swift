import AppKit
import SwiftUI

/// Borderless, non-activating panel that hosts the SwiftUI panel below the
/// status item — the design's floating card (12 pt radius, blur, shadow, no arrow).
///
/// Why not NSPopover: it animates `contentSize` changes on its own clock and
/// tears its window down when the size is driven while content animates, which
/// showed up as a flicker when a row slid out. Here the window frame simply
/// follows the SwiftUI content size, top-anchored, with no window animation.
final class PanelWindowController {
    private final class PanelWindow: NSPanel {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }
    }

    static let cornerRadius: CGFloat = 12
    /// Gap between the menu bar and the panel, and to the screen edge (design: 8 / 12).
    static let topGap: CGFloat = 8
    static let edgeInset: CGFloat = 12

    private let window: PanelWindow
    private let host: NSHostingController<AnyView>
    private var eventMonitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    /// Top-right corner the panel hangs from (screen coordinates).
    private var anchorTopRight: NSPoint = .zero
    /// Last size PanelView reported; used to size the window before it is shown.
    private var contentSize: CGSize = .zero
    /// Latest shrink frame waiting for the coalesced apply (see `resize`).
    private var pendingFrame: NSRect?
    private var applyScheduled = false

    /// Called when the panel closed for any reason (outside click, Esc, …).
    var onClose: (() -> Void)?
    /// Asked before Esc closes the panel; return false to let SwiftUI handle it (e.g. cancel a form).
    var shouldCloseOnEscape: () -> Bool = { true }
    /// Clicks the dismissal monitors must NOT treat as "outside" — the status
    /// item's own button, whose mouse-up toggles the panel. Without this, the
    /// mouse-*down* monitor closed the panel first and the mouse-up saw it as
    /// closed and reopened it: the icon could never dismiss the panel.
    var shouldIgnoreClick: (NSEvent) -> Bool = { _ in false }

    /// True while the close fade-out runs; the panel is already "closed" for
    /// toggling purposes then.
    private var isClosing = false
    /// Invalidates in-flight close completions when the panel is re-shown.
    private var closeGeneration = 0

    var isShown: Bool { window.isVisible && !isClosing }
    var windowNumber: Int { window.windowNumber }

    init(rootView: some View) {
        host = NSHostingController(rootView: AnyView(rootView))
        host.sizingOptions = [] // we size the window from PanelView's reported size

        window = PanelWindow(contentRect: NSRect(x: 0, y: 0, width: Theme.panelWidth, height: 200),
                             styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .popUpMenu
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.isMovableByWindowBackground = false
        window.animationBehavior = .none
        window.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]

        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        // The blur region is the *mask image*, not the layer's corner radius: with only
        // `layer.cornerRadius` the material is clipped but the behind-window blur still
        // covers the full rectangle, leaving a lighter square outside every rounded corner.
        // The mask's corners are circular, so the layer uses the default curve too — a
        // `.continuous` layer corner inside a circular mask would show the same artifact.
        effect.maskImage = PanelWindowController.roundedMask
        effect.wantsLayer = true
        effect.layer?.cornerRadius = PanelWindowController.cornerRadius // clips the SwiftUI content
        effect.layer?.masksToBounds = true

        host.view.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: effect.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: effect.bottomAnchor)
        ])
        window.contentView = effect
    }

    // MARK: - Shape

    /// Resizable rounded-rect mask for the effect view: the corners stay fixed and the
    /// edges stretch, so one image fits the panel at every height.
    private static let roundedMask: NSImage = {
        let radius = PanelWindowController.cornerRadius
        let side = radius * 2 + 1
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }()

    // MARK: - Show / hide

    /// Shows the panel hanging from `anchor` (a screen rect, e.g. the status item button).
    func show(below anchor: NSRect) {
        isClosing = false
        closeGeneration += 1 // a pending close completion must not hide this show
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main
        let bounds = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let top = min(anchor.minY, bounds.maxY) - PanelWindowController.topGap
        var right = anchor.maxX
        right = min(right, bounds.maxX - PanelWindowController.edgeInset)
        right = max(right, bounds.minX + PanelWindowController.edgeInset + Theme.panelWidth)
        anchorTopRight = NSPoint(x: right, y: top)

        // Size to the content before the first frame is drawn. PanelView reports its size
        // from its first layout pass, which normally already happened when the hosting
        // view joined the window. If show() comes before that pass, run it now — the
        // report lands in `contentSize` synchronously. (The root view always adopts the
        // proposed size, so the hosting controller's sizeThatFits can't measure it.)
        if contentSize.height == 0 {
            host.view.layoutSubtreeIfNeeded()
        }
        if contentSize.height > 0 { resize(to: contentSize, display: false) }
        if PanelWindowController.logsSizes { NSLog("panel window #%ld at %@", window.windowNumber, NSStringFromRect(window.frame)) }

        window.alphaValue = 0
        window.orderFrontRegardless()
        window.makeKey()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            window.animator().alphaValue = 1
        }
        installMonitors()
    }

    func close() {
        guard isShown else { return }
        isClosing = true
        closeGeneration += 1
        let generation = closeGeneration
        pendingFrame = nil // drop any coalesced resize still in flight
        removeMonitors()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.10
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            // Superseded by a show() mid-fade → leave the fresh panel alone.
            guard let self, self.closeGeneration == generation else { return }
            self.isClosing = false
            self.window.orderOut(nil)
            self.window.alphaValue = 1
        })
        onClose?()
    }

    // MARK: - Sizing

    /// Follows the SwiftUI content size. Top-right stays put. Snaps by default;
    /// with `animated` the frame eases over `duration` — used while a row collapses,
    /// so the window shrinks in lockstep with SwiftUI's own ease-out of the content
    /// (the size reader reports the final layout height right at the start).
    func resize(to size: CGSize, display: Bool = true, animated: Bool = false,
                duration: TimeInterval = TaskStore.collapseDuration) {
        guard size.width > 0, size.height > 0 else { return }
        contentSize = size
        guard window.isVisible || !display else { return } // remember only; place it on show()
        let w = ceil(size.width), h = ceil(size.height)
        let frame = NSRect(x: anchorTopRight.x - w, y: anchorTopRight.y - h, width: w, height: h)
        guard window.frame != frame else { pendingFrame = nil; return }
        if PanelWindowController.logsSizes { NSLog("panel resize → %.0f×%.0f%@", w, h, animated ? " (animated)" : "") }
        if animated, window.isVisible {
            pendingFrame = nil
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = duration
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().setFrame(frame, display: true)
            }, completionHandler: { [window] in
                window.invalidateShadow()
            })
        } else if window.isVisible {
            // Resizing while shown. The size reader fires from *inside* SwiftUI's update
            // (every frame of a layout animation, or once for a route change), and a
            // synchronous setFrame there re-enters AppKit layout with the hosting view
            // mid-update: when the panel grew, the hosting view came out taller than the
            // window by the growth (853 for a 583 window), hanging out above the top edge
            // — header clipped, blank strip at the bottom, until the next state change.
            // While shrinking it merely jittered. Coalesce to one setFrame per runloop
            // turn, applied after the layout pass, so the window and the freshly laid-out
            // content move together and AppKit lays the hosting view out exactly once.
            pendingFrame = frame
            guard !applyScheduled else { return }
            applyScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.applyScheduled = false
                guard let frame = self.pendingFrame else { return }
                self.pendingFrame = nil
                guard self.window.isVisible, self.window.frame != frame else { return }
                self.window.setFrame(frame, display: true, animate: false)
                self.window.invalidateShadow()
            }
        } else {
            // Placing before show: nothing is on screen yet, apply immediately.
            pendingFrame = nil
            window.setFrame(frame, display: display, animate: false)
            window.invalidateShadow()
        }
    }

    /// `MENUBAR_TODO_LOG_SIZES=1` logs every window resize (debugging layout animations).
    private static let logsSizes = ProcessInfo.processInfo.environment["MENUBAR_TODO_LOG_SIZES"] == "1"

    // MARK: - Dismissal (transient behaviour)

    private func installMonitors() {
        removeMonitors()
        // Clicks in other apps.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown],
                                                          handler: { [weak self] _ in self?.close() }) {
            eventMonitors.append(global)
        }
        // Clicks in our own app outside the panel, and Esc.
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown],
                                                        handler: { [weak self] event in
            guard let self else { return event }
            switch event.type {
            case .keyDown where event.keyCode == 53: // Esc
                if self.window.isKeyWindow, self.shouldCloseOnEscape() {
                    self.close()
                    return nil
                }
                return event
            case .leftMouseDown, .rightMouseDown, .otherMouseDown:
                if event.window !== self.window, !self.shouldIgnoreClick(event) { self.close() }
                return event
            default:
                return event
            }
        }) {
            eventMonitors.append(local)
        }
        // Cmd-Tab / another window of ours taking key status.
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,
                                                                object: window, queue: .main) { [weak self] _ in
            guard let self else { return }
            // Menus/popups keep us key; a real key change means the user moved on.
            DispatchQueue.main.async {
                if self.window.isVisible, !self.window.isKeyWindow, NSApp.keyWindow !== self.window {
                    self.close()
                }
            }
        })
    }

    private func removeMonitors() {
        eventMonitors.forEach { NSEvent.removeMonitor($0) }
        eventMonitors.removeAll()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
    }

    deinit {
        removeMonitors()
    }
}
