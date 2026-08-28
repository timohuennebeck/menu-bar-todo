import Observation
import Foundation

/// Panel chrome the user controls, persisted like the dragged position is.
/// Deliberately not part of TaskStore: that is task data, and preview runs null
/// out its persistence — the pin is a window preference and should survive them.
@Observable
final class PanelSettings {
    private static let pinnedKey = "panelPinned"

    /// While pinned the panel stays open when focus moves elsewhere; only the
    /// status item, ⌃⌘T and Esc still close it (see PanelWindowController.dismisses).
    var isPinned: Bool {
        didSet { defaults.set(isPinned, forKey: PanelSettings.pinnedKey) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isPinned = defaults.bool(forKey: PanelSettings.pinnedKey)
    }
}
