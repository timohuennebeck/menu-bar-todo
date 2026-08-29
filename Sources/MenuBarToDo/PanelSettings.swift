import Observation
import Foundation

extension Notification.Name {
    /// The panel's landscape was switched; SurfaceView rebuilds on it.
    static let panelSceneChanged = Notification.Name("MenuBarToDo.panelSceneChanged")
}

/// Panel chrome the user controls, persisted like the dragged position is.
/// Deliberately not part of TaskStore: that is task data, and preview runs null
/// out its persistence — the pin is a window preference and should survive them.
@Observable
final class PanelSettings {
    private static let pinnedKey = "panelPinned"
    private static let listHeightKey = "panelListMaxHeight"
    private static let widthKey = "panelWidth"
    private static let sceneKey = "panelScene"
    /// Wider than this a to-do list only gets long lines; also keeps the scene sane.
    static let maxWidth: CGFloat = 600
    /// About three rows with details: shorter and the list is a peephole. The design's 410 is the
    /// default, not the floor, so the panel can also be made *shorter* than it ships.
    static let minListHeight: CGFloat = 290

    /// While pinned the panel stays open when focus moves elsewhere; only the
    /// status item, ⌃⌘T and Esc still close it (see PanelWindowController.dismisses).
    var isPinned: Bool {
        didSet { defaults.set(isPinned, forKey: PanelSettings.pinnedKey) }
    }

    /// How tall the task/done list may grow before it scrolls. The panel's height
    /// follows its content, so this cap — not a window height — is what the resize
    /// grip at the bottom edge drags (see ResizeGripArea): short lists stay short,
    /// long ones get the extra rows. Between `minListHeight` and the screen.
    var listMaxHeight: CGFloat {
        didSet { defaults.set(Double(listMaxHeight), forKey: PanelSettings.listHeightKey) }
    }

    /// Panel width. The panel hangs from its top-right corner, so the resize grip on
    /// the *left* edge drags this and the anchor stays put. Never below the design width.
    var panelWidth: CGFloat {
        didSet { defaults.set(Double(panelWidth), forKey: PanelSettings.widthKey) }
    }

    /// Clamps a dragged width between the design width and the smaller of `maxWidth`
    /// and the room left on screen; the design width wins if even that is less.
    static func clampWidth(_ width: CGFloat, available: CGFloat) -> CGFloat {
        max(Theme.panelWidth, min(width, maxWidth, available))
    }

    /// Clamps a dragged list height between `minListHeight` and the room left on
    /// screen. `available` is the most the list may take; if even that is less than
    /// the minimum (tiny screen, panel dragged near the bottom), the minimum wins.
    static func clampListHeight(_ height: CGFloat, available: CGFloat) -> CGFloat {
        max(minListHeight, min(height, available))
    }

    /// Which landscape the panel shows. `nil` follows the clock: meadow by day,
    /// golden hour in the evening, night after that.
    var scene: PixelScene.Kind? {
        didSet {
            if let scene { defaults.set(scene.rawValue, forKey: PanelSettings.sceneKey) }
            else { defaults.removeObject(forKey: PanelSettings.sceneKey) }
            // The landscape is an AppKit view under the SwiftUI content, not part of
            // this observation graph, so it is told rather than seen.
            NotificationCenter.default.post(name: .panelSceneChanged, object: nil)
        }
    }

    /// Steps the scene on by one. `hour` is what the clock would be showing.
    func cycleScene(hour: Int = Calendar.current.component(.hour, from: Date())) {
        scene = PanelSettings.scene(after: scene, clock: PixelScene.kind(forHour: hour))
    }

    /// The switcher's ring, rotated so it begins *after* the scene `clock` is showing:
    /// `nil` → the next landscape → … → the clock's own one → `nil` again.
    ///
    /// Rotating rather than skipping is what makes both ends work. Stepping off "follow
    /// the clock" straight onto the scene the clock already shows looked like a dead
    /// button; simply skipping that entry instead put it out of reach for the rest of
    /// the day (no way to pin the meadow at 9 a.m.). This way the first click always
    /// changes the picture and every landscape still comes round.
    static func scene(after current: PixelScene.Kind?, clock: PixelScene.Kind) -> PixelScene.Kind? {
        let all = PixelScene.Kind.pickable
        // In the evening and at night the clock's scene isn't in the ring at all, so
        // there is nothing to rotate past — the ring simply starts at the front.
        let start = all.firstIndex(of: clock).map { $0 + 1 } ?? 0
        let ring: [PixelScene.Kind?] = (0..<all.count).map { all[(start + $0) % all.count] } + [nil]
        let i = ring.firstIndex(of: current) ?? ring.count - 1
        return ring[(i + 1) % ring.count]
    }

    /// The stored choice, readable without a settings instance: the scene view rebuilds
    /// itself from the defaults (like it reads the hour) rather than being handed this object.
    static func storedScene(defaults: UserDefaults = .standard) -> PixelScene.Kind? {
        defaults.string(forKey: sceneKey).flatMap(PixelScene.Kind.init(rawValue:))
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isPinned = defaults.bool(forKey: PanelSettings.pinnedKey)
        let stored = defaults.object(forKey: PanelSettings.listHeightKey) as? Double
        listMaxHeight = stored.map { max(PanelSettings.minListHeight, CGFloat($0)) } ?? Theme.listMaxHeight
        let storedWidth = defaults.object(forKey: PanelSettings.widthKey) as? Double ?? 0
        panelWidth = max(Theme.panelWidth, CGFloat(storedWidth))
        scene = PanelSettings.storedScene(defaults: defaults)
    }
}
