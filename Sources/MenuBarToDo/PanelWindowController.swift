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
    private var surface: SurfaceView?
    private var eventMonitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    /// Top-right corner the panel hangs from (screen coordinates).
    private var anchorTopRight: NSPoint = .zero
    /// Where the user last dragged the panel to (top-right, screen coordinates).
    /// Once set, the panel reopens there instead of under the status item.
    private var draggedTopRight: NSPoint? {
        didSet {
            guard let p = draggedTopRight else { return }
            UserDefaults.standard.set([p.x, p.y], forKey: PanelWindowController.positionKey)
        }
    }
    private static let positionKey = "panelTopRight"
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
    /// Whether the user has pinned the panel open (see `dismisses`). Asked per event,
    /// so toggling the pin while the panel is shown takes effect immediately.
    var isPinned: () -> Bool = { false }

    /// True while the close fade-out runs; the panel is already "closed" for
    /// toggling purposes then.
    private var isClosing = false
    /// Invalidates in-flight close completions when the panel is re-shown.
    private var closeGeneration = 0

    var isShown: Bool { window.isVisible && !isClosing }
    var windowNumber: Int { window.windowNumber }

    /// Debug aid: renders the panel's content view (background scene + SwiftUI) to a PNG.
    func dumpPNG(to path: String) {
        guard let view = window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

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
        // Not movable by background: that would swallow the rows' `.onDrag` reorder.
        // The scene band at the top is the drag grip instead (WindowDragArea).
        window.isMovableByWindowBackground = false
        window.animationBehavior = .none
        window.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]

        // Flat, opaque surface (no behind-window blur) so the panel reads like a card.
        let effect = SurfaceView()
        surface = effect
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

        if let saved = UserDefaults.standard.array(forKey: PanelWindowController.positionKey) as? [Double], saved.count == 2 {
            draggedTopRight = NSPoint(x: saved[0], y: saved[1])
        }
    }

    // MARK: - Show / hide

    /// Shows the panel hanging from `anchor` (a screen rect, e.g. the status item button).
    func show(below anchor: NSRect) {
        isClosing = false
        closeGeneration += 1 // a pending close completion must not hide this show
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main
        let bounds = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        if let dragged = draggedTopRight {
            // Reopen where the user put it, nudged back on screen if the display changed.
            let screen = NSScreen.screens.first { $0.frame.contains(dragged) } ?? screen
            let bounds = screen?.visibleFrame ?? bounds
            anchorTopRight = NSPoint(x: min(max(dragged.x, bounds.minX + Theme.panelWidth), bounds.maxX),
                                     y: min(max(dragged.y, bounds.minY + 100), bounds.maxY))
        } else {
            let top = min(anchor.minY, bounds.maxY) - PanelWindowController.topGap
            var right = anchor.maxX
            right = min(right, bounds.maxX - PanelWindowController.edgeInset)
            right = max(right, bounds.minX + PanelWindowController.edgeInset + Theme.panelWidth)
            anchorTopRight = NSPoint(x: right, y: top)
        }

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

        applyPinnedLevel()
        surface?.start()
        window.alphaValue = 0
        window.orderFrontRegardless()
        window.makeKey()
        // Coming on screen lays the content out for a route that changed while hidden
        // (the add shortcut). SwiftUI reports that size *before* `isVisible` flips, so
        // `resize` only remembered it. Push it through again now that the window is
        // visible: a changed size is applied on the next turn (still at alpha ≈ 0),
        // an unchanged one is a no-op.
        if contentSize.height > 0 { resize(to: contentSize) }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            window.animator().alphaValue = 1
        }
        installMonitors()
    }

    /// Closes only if `cause` dismisses the panel in its current pin state; the
    /// unconditional `close()` stays for the status item and ⌃⌘T.
    private func close(on cause: Dismissal) {
        guard PanelWindowController.dismisses(cause, pinned: isPinned()) else { return }
        close()
    }

    func close() {
        guard isShown else { return }
        isClosing = true
        closeGeneration += 1
        let generation = closeGeneration
        pendingFrame = nil // drop any coalesced resize still in flight
        removeMonitors()
        surface?.stop()
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

    /// A transient popover belongs above menus and popups; a *pinned* panel is a
    /// utility window the user parked on screen, and at `.popUpMenu` it would cover
    /// other apps' menus, Spotlight and popovers all day. `.floating` still keeps it
    /// above normal windows. Call whenever the pin changes.
    func applyPinnedLevel() {
        window.level = isPinned() ? .floating : .popUpMenu
    }

    // MARK: - Sizing

    /// Follows the SwiftUI content size. Top-right stays put. Snaps by default;
    /// with `animated` the frame eases over `duration` — used while a row collapses,
    /// so the window shrinks in lockstep with SwiftUI's own ease-out of the content
    /// (the size reader reports the final layout height right at the start).
    func resize(to size: CGSize, display: Bool = true, animated: Bool = false,
                duration: TimeInterval = TaskStore.collapseDuration) {
        guard size.width > 0, size.height > 0 else { return }
        if PanelWindowController.logsSizes { NSLog("panel size report %.0f×%.0f (visible %d)", size.width, size.height, window.isVisible ? 1 : 0) }
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
            // That setFrame runs a layout pass, and the first real layout for the current
            // route can happen right there — SwiftUI then reports the true size
            // *re-entrantly* (stored above, but not applied: the window isn't visible).
            // Place again with it, or the panel shows up at the stale pre-layout height
            // (a 153 pt window around the 313 pt add form).
            if contentSize != size {
                resize(to: contentSize, display: display)
                return
            }
            window.invalidateShadow()
        }
    }

    /// `MENUBAR_TODO_LOG_SIZES=1` logs every window resize (debugging layout animations).
    private static let logsSizes = ProcessInfo.processInfo.environment["MENUBAR_TODO_LOG_SIZES"] == "1"

    // MARK: - Dismissal (transient behaviour)

    /// What just happened that *might* close the panel.
    enum Dismissal: CaseIterable {
        /// Mouse-down in another application.
        case outsideClick
        /// Mouse-down in one of our own windows that isn't the panel.
        case ownAppClick
        /// Something else took key status (Cmd-Tab, another window of ours).
        case resignKey
        /// The user pressed Esc outside a form.
        case escape
    }

    /// The whole pin behaviour: unpinned, the panel is a transient popover and every
    /// cause dismisses it; pinned, only Esc does. The status item and ⌃⌘T call
    /// `close()` directly and so always work, pinned or not.
    nonisolated static func dismisses(_ cause: Dismissal, pinned: Bool) -> Bool {
        guard pinned else { return true }
        return cause == .escape
    }

    private func installMonitors() {
        removeMonitors()
        // Clicks in other apps.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown],
                                                          handler: { [weak self] _ in self?.close(on: .outsideClick) }) {
            eventMonitors.append(global)
        }
        // Clicks in our own app outside the panel, and Esc.
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown],
                                                        handler: { [weak self] event in
            guard let self else { return event }
            switch event.type {
            case .keyDown where event.keyCode == 53: // Esc
                if self.window.isKeyWindow, self.shouldCloseOnEscape() {
                    self.close(on: .escape)
                    return nil
                }
                return event
            case .leftMouseDown, .rightMouseDown, .otherMouseDown:
                if event.window !== self.window, !self.shouldIgnoreClick(event) { self.close(on: .ownAppClick) }
                return event
            default:
                return event
            }
        }) {
            eventMonitors.append(local)
        }
        // Dragged by the user: content-driven resizes must keep the new spot instead
        // of snapping back under the status item.
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification,
                                                                object: window, queue: .main) { [weak self] _ in
            guard let self, self.pendingFrame == nil else { return } // our own coalesced setFrame
            let topRight = NSPoint(x: self.window.frame.maxX, y: self.window.frame.maxY)
            guard topRight != self.anchorTopRight else { return } // our resizes keep the top-right fixed
            self.anchorTopRight = topRight
            self.draggedTopRight = topRight
        })
        // Cmd-Tab / another window of ours taking key status.
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,
                                                                object: window, queue: .main) { [weak self] _ in
            guard let self else { return }
            // Menus/popups keep us key; a real key change means the user moved on.
            DispatchQueue.main.async {
                if self.window.isVisible, !self.window.isKeyWindow, NSApp.keyWindow !== self.window {
                    self.close(on: .resignKey)
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

/// Animated pixel-art landscape behind the panel content. Draws the scene at
/// `pixelSize` points per scene pixel, anchored to the top edge, and extends the
/// ground colour below it so any panel height is covered. Only animates while
/// the panel is shown.
final class SurfaceView: NSView {
    static let pixelSize: CGFloat = 2
    static let fps = PixelScene.fps
    /// The HTML's "bead grid": a radial shade over each pixel so the scene looks like
    /// fused Perler beads. Drawn as one tile, pattern-filled over the whole view.
    static let beadGrid = true

    private var scene: PixelScene?
    private var frame_: CGImage?
    private var timer: Timer?
    private var started: CFTimeInterval = 0

    override var isFlipped: Bool { true }

    func start() {
        rebuildScene()
        started = CACurrentMediaTime()
        tick()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1 / SurfaceView.fps, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// The scene's ground continues to the bottom of the view, so it is rebuilt at the
    /// view's current height (the static parts are seeded, so the layout stays stable).
    private func rebuildScene() {
        let hour = Calendar.current.component(.hour, from: Date())
        let w = Int(Theme.panelWidth / SurfaceView.pixelSize)
        let total = Int((bounds.height / SurfaceView.pixelSize).rounded(.up))
        scene = PixelScene(width: w, height: w * 10 / 16, totalHeight: total, kind: PixelScene.kind(forHour: hour))
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if let scene, Int((newSize.height / SurfaceView.pixelSize).rounded(.up)) != scene.totalH {
            rebuildScene()
            if timer != nil { tick() }
        }
    }

    private func tick() {
        guard let scene else { return }
        scene.lookAt = mouseInScene()
        frame_ = scene.render(time: CACurrentMediaTime() - started)
        needsDisplay = true
    }

    /// Current mouse position in scene pixels (polled, so it works while the
    /// pointer is outside the panel too).
    private func mouseInScene() -> (x: Double, y: Double)? {
        guard let window else { return nil }
        let p = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        return (p.x / SurfaceView.pixelSize, p.y / SurfaceView.pixelSize)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        guard let scene, let image = frame_ else {
            ctx.setFillColor(Theme.surfaceNSColor.cgColor)
            ctx.fill(bounds)
            return
        }
        ctx.setFillColor(scene.groundColor.cgColor)
        ctx.fill(bounds)
        let size = CGSize(width: CGFloat(scene.W) * SurfaceView.pixelSize,
                          height: CGFloat(scene.totalH) * SurfaceView.pixelSize)
        // Flipped view: undo the flip for the image so it isn't drawn upside down.
        ctx.saveGState()
        ctx.interpolationQuality = .none
        ctx.translateBy(x: 0, y: size.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(origin: .zero, size: size))
        ctx.restoreGState()
        if SurfaceView.beadGrid { drawBeadGrid(ctx) }
        // Dark scrim from below the computer to the bottom so the content (white text)
        // stays readable and the ground below the scene fades out instead of showing
        // as a flat green slab.
        let nominal = CGFloat(scene.H) * SurfaceView.pixelSize, top = nominal * 0.5
        let colors = [CGColor(gray: 0, alpha: 0), CGColor(gray: 0, alpha: 0.5), CGColor(gray: 0, alpha: 0.32)] as CFArray
        let locations: [CGFloat] = [0, min(1, (nominal - top) / max(1, bounds.height - top)), 1]
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceGray(), colors: colors, locations: locations) {
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: top), end: CGPoint(x: 0, y: bounds.height), options: [.drawsAfterEndLocation])
        }
    }

    private static let beadTile: CGImage = {
        let n = Int(pixelSize * 4) // draw at 4× and let the pattern scale it down for smooth shading
        let c = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        // radial-gradient(circle at 50% 50%, transparent 0 32%, rgba(0,0,0,0.28) 78%)
        let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                           colors: [CGColor(gray: 0, alpha: 0), CGColor(gray: 0, alpha: 0), CGColor(gray: 0, alpha: 0.28), CGColor(gray: 0, alpha: 0.28)] as CFArray,
                           locations: [0, 0.32, 0.78, 1])!
        let mid = CGPoint(x: CGFloat(n) / 2, y: CGFloat(n) / 2)
        c.drawRadialGradient(g, startCenter: mid, startRadius: 0, endCenter: mid, endRadius: CGFloat(n) / 2 * 1.42, options: [.drawsAfterEndLocation])
        return c.makeImage()!
    }()

    private func drawBeadGrid(_ ctx: CGContext) {
        let s = SurfaceView.pixelSize
        var callbacks = CGPatternCallbacks(version: 0, drawPattern: { _, c in
            c.draw(SurfaceView.beadTile, in: CGRect(x: 0, y: 0, width: SurfaceView.pixelSize, height: SurfaceView.pixelSize))
        }, releaseInfo: nil)
        guard let pattern = CGPattern(info: nil, bounds: CGRect(x: 0, y: 0, width: s, height: s),
                                      matrix: .identity, xStep: s, yStep: s, tiling: .constantSpacing,
                                      isColored: true, callbacks: &callbacks),
              let space = CGColorSpace(patternBaseSpace: nil) else { return }
        ctx.saveGState()
        ctx.setFillColorSpace(space)
        var alpha: CGFloat = 1
        ctx.setFillPattern(pattern, colorComponents: &alpha)
        ctx.fill(bounds)
        ctx.restoreGState()
    }
}

/// Drag grip for the panel: a mouse-down here moves the whole window. Placed over
/// the scene band at the top so it never competes with the rows' reorder drag.
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        /// Without this the grip is dead until the panel is focused: AppKit swallows the
        /// first click into an inactive app as the activating click, so `mouseDown` never
        /// runs and the drag never starts. The panel is a non-activating panel that can
        /// now sit open while another app is frontmost (pinned), so that first click is
        /// the common case, not an edge case.
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ nsView: DragView, context: Context) {}
}
