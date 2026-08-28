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
    /// Esc with no text field focused. Return true if it was dealt with (a form
    /// cancelled); false lets the panel close. It cannot be left to SwiftUI's
    /// onExitCommand: the first Esc resigns first responder, which takes the SwiftUI
    /// view out of the responder chain, and the next Esc would then reach nothing.
    var onEscape: () -> Bool = { false }
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

    /// Sets the computers in the landscape cheering (a task was ticked off).
    func celebrate() { surface?.celebrate() }

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
                // Esc escalates: leave the text field, then cancel the form, then close
                // the panel. Without the first step a single Esc cancelled the whole
                // form, losing what had been typed.
                guard self.window.isKeyWindow else { return event }
                if self.resignFocusedText() { return nil }
                if self.onEscape() { return nil }
                self.close(on: .escape)
                return nil
            case .leftMouseDown, .rightMouseDown, .otherMouseDown:
                if event.window !== self.window, !self.shouldIgnoreClick(event) { self.close(on: .ownAppClick) }
                // A click anywhere in the panel that isn't in the focused field ends
                // editing, the way clicking off an input does on the web. The monitor
                // sees this before the views do, so buttons, chips and rows are covered
                // too — a background tap gesture can only catch the gaps between them.
                if event.window === self.window { self.resignTextIfClickOutside(event) }
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

    /// Ends text editing if a text field has focus. Returns whether it did.
    @discardableResult
    private func resignFocusedText() -> Bool {
        guard window.firstResponder is NSTextView else { return false }
        window.makeFirstResponder(nil)
        return true
    }

    /// Same, unless the click landed inside the field being edited.
    private func resignTextIfClickOutside(_ event: NSEvent) {
        guard let editor = window.firstResponder as? NSTextView else { return }
        // The field editor covers only the text; `delegate` is the field itself, whose
        // frame includes its padding — clicking a field's own inset must not blur it.
        let target = (editor.delegate as? NSView) ?? editor
        let point = target.convert(event.locationInWindow, from: nil)
        if !target.bounds.contains(point) { window.makeFirstResponder(nil) }
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
    /// Scene time of the last check-off. Kept here rather than on the scene so that
    /// rebuilding the scene (any panel resize) doesn't restart or lose the cheer.
    private var celebratedAt: Double?

    func celebrate() { celebratedAt = CACurrentMediaTime() - started }

    override var isFlipped: Bool { true }

    func start() {
        rebuildScene()
        started = CACurrentMediaTime()
        // `started` moves, so a stamp from the last time the panel was open would land
        // at an arbitrary point on the new clock and could fire a stray cheer.
        celebratedAt = nil
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
        scene.celebratedAt = celebratedAt
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
            // Explicitly the dark surface, not the appearance-dependent one: the panel's
            // content is always dark, and in light mode the dynamic colour resolves to
            // near-white — a white panel for the frame before the first scene render.
            ctx.setFillColor(Theme.surfaceDarkNSColor.cgColor)
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
        if SurfaceView.beadGrid {
            // Same rect as the scene, so bead cell (x, y) lies exactly on scene pixel (x, y).
            ctx.draw(beadOverlay(rows: scene.totalH), in: CGRect(origin: .zero, size: size))
        }
        ctx.restoreGState()
        // Dark scrim from below the computer so the content (white text) stays readable
        // and the ground below the scene fades out instead of showing as a flat green slab.
        let nominal = CGFloat(scene.H) * SurfaceView.pixelSize
        let colors = [CGColor(gray: 0, alpha: 0), CGColor(gray: 0, alpha: Scrim.mid), CGColor(gray: 0, alpha: Scrim.end)] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceGray(), colors: colors,
                                     locations: Scrim.locations(nominal: nominal)) {
            ctx.drawLinearGradient(gradient,
                                   start: CGPoint(x: 0, y: Scrim.top(nominal: nominal)),
                                   end: CGPoint(x: 0, y: Scrim.fadeEnd(nominal: nominal)),
                                   options: [.drawsAfterEndLocation])
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

    /// The bead grid as one image the size of the scene, drawn over it with the same
    /// rect. It used to be a `CGPattern` fill: a pattern (like `draw(byTiling:)`) is
    /// anchored to the context's *base* space — the window's backing store — not to the
    /// view, so on screen the 2 pt tiles landed 1 px off against the 2 pt scene pixels
    /// for some panel heights. The dark ring of every bead then cut through the middle
    /// of the scene pixels instead of framing them, and the whole panel read as darker
    /// after a resize. (`cacheDisplay` renders were always aligned, which is why the
    /// PNG dumps never showed it.) An image placed by rect is positioned in user space,
    /// exactly like the scene image it covers.
    private var beadOverlayCache: (scale: CGFloat, rows: Int, image: CGImage)?

    private func beadOverlay(rows: Int) -> CGImage {
        let scale = window?.backingScaleFactor ?? 2
        if let cached = beadOverlayCache, cached.scale == scale, cached.rows == rows { return cached.image }
        let cell = Int(SurfaceView.pixelSize * scale)
        let cols = Int(Theme.panelWidth / SurfaceView.pixelSize)
        let width = cols * cell, height = rows * cell
        func context(_ w: Int, _ h: Int) -> CGContext {
            CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        }
        // One row of beads, then that strip repeated: far fewer draws than one per cell.
        let strip = context(width, cell)
        strip.interpolationQuality = .default
        for x in 0..<cols {
            strip.draw(SurfaceView.beadTile, in: CGRect(x: x * cell, y: 0, width: cell, height: cell))
        }
        let stripImage = strip.makeImage()!
        let full = context(width, height)
        for y in 0..<rows {
            full.draw(stripImage, in: CGRect(x: 0, y: y * cell, width: width, height: cell))
        }
        let image = full.makeImage()!
        beadOverlayCache = (scale, rows, image)
        return image
    }
}

/// Geometry of the scrim over the scene, anchored to the scene and never to the view's
/// height. It used to end at `bounds.height`, which stretched the 0.5 → 0.32 ramp over
/// whatever the panel happened to measure: every resize — a group collapsing, a route
/// change — moved the end point and so changed the alpha at *every* point below the
/// scene, which reads as the overlay darkening and lightening as the panel grows and
/// shrinks. Past `fadeEnd` the last alpha simply holds (`.drawsAfterEndLocation`).
enum Scrim {
    /// Alpha where the ramp peaks (level with the bottom of the scene) and where it settles.
    static let mid: CGFloat = 0.5
    static let end: CGFloat = 0.32
    /// The scrim starts half way down the scene, so the sky stays clear.
    static func top(nominal: CGFloat) -> CGFloat { nominal * 0.5 }
    /// A fixed distance below the scene, chosen to sit inside the usual panel heights.
    static func fadeEnd(nominal: CGFloat) -> CGFloat { nominal * 2.5 }

    static func locations(nominal: CGFloat) -> [CGFloat] {
        let top = top(nominal: nominal), end = fadeEnd(nominal: nominal)
        return [0, (nominal - top) / (end - top), 1]
    }

    /// The alpha the scrim paints at `y`, for tests and for reasoning about the shape.
    static func alpha(at y: CGFloat, nominal: CGFloat) -> CGFloat {
        let top = top(nominal: nominal), end = fadeEnd(nominal: nominal)
        if y <= top { return 0 }
        if y >= end { return self.end }          // held, which is what makes it height-independent
        if y <= nominal { return mid * (y - top) / (nominal - top) }
        return mid + (self.end - mid) * (y - nominal) / (end - nominal)
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
