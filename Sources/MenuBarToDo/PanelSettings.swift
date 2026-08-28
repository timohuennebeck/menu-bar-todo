import Observation
import Foundation

/// Panel chrome the user controls, persisted like the dragged position is.
/// Deliberately not part of TaskStore: that is task data, and preview runs null
/// out its persistence — the pin is a window preference and should survive them.
@Observable
final class PanelSettings {
    private static let pinnedKey = "panelPinned"
    private static let listHeightKey = "panelListMaxHeight"

    /// While pinned the panel stays open when focus moves elsewhere; only the
    /// status item, ⌃⌘T and Esc still close it (see PanelWindowController.dismisses).
    var isPinned: Bool {
        didSet { defaults.set(isPinned, forKey: PanelSettings.pinnedKey) }
    }

    /// How tall the task/done list may grow before it scrolls. The panel's height
    /// follows its content, so this cap — not a window height — is what the resize
    /// grip at the bottom edge drags (see ResizeGripArea): short lists stay short,
    /// long ones get the extra rows. Never below the design's cap.
    var listMaxHeight: CGFloat {
        didSet { defaults.set(Double(listMaxHeight), forKey: PanelSettings.listHeightKey) }
    }

    /// Clamps a dragged list height between the design cap and the room left on
    /// screen. `available` is the most the list may take; if even that is less than
    /// the cap (tiny screen, panel dragged near the bottom), the cap wins.
    static func clampListHeight(_ height: CGFloat, available: CGFloat) -> CGFloat {
        max(Theme.listMaxHeight, min(height, available))
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isPinned = defaults.bool(forKey: PanelSettings.pinnedKey)
        let stored = defaults.object(forKey: PanelSettings.listHeightKey) as? Double ?? 0
        listMaxHeight = max(Theme.listMaxHeight, CGFloat(stored))
    }
}
