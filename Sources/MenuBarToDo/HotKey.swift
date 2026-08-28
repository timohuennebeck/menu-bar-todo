import AppKit
import Carbon.HIToolbox

/// A system-wide keyboard shortcut: virtual key code + modifier flags.
struct KeyCombo: Equatable {
    let keyCode: UInt32
    let modifiers: NSEvent.ModifierFlags
    /// The character on the key, for menu key equivalents and `displayString`. Stored
    /// next to the key code instead of translated from the keyboard layout: both
    /// shortcuts sit on ANSI letter keys, and `RegisterEventHotKey` matches the physical
    /// key anyway.
    let key: String

    /// ⌃⌥T — show/hide the panel.
    static let togglePanel = KeyCombo(keyCode: UInt32(kVK_ANSI_T), modifiers: [.control, .option], key: "T")
    /// ⌃⌥N — open the panel straight into "Task hinzufügen".
    static let addTask = KeyCombo(keyCode: UInt32(kVK_ANSI_N), modifiers: [.control, .option], key: "N")

    /// The modifier mask in Carbon's vocabulary (only the four keys it knows).
    var carbonModifiers: UInt32 {
        var mask: Int = 0
        if modifiers.contains(.control) { mask |= controlKey }
        if modifiers.contains(.option) { mask |= optionKey }
        if modifiers.contains(.shift) { mask |= shiftKey }
        if modifiers.contains(.command) { mask |= cmdKey }
        return UInt32(mask)
    }

    /// "⌃⌥N" — the symbols in the order macOS menus use (⌃ ⌥ ⇧ ⌘).
    var displayString: String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        return text + key
    }
}

/// Registers system-wide hotkeys via Carbon's `RegisterEventHotKey`: works while
/// the app is in the background, needs no Accessibility permission, and swallows
/// the keystroke so it doesn't also reach the frontmost app.
/// (`NSEvent.addGlobalMonitorForEvents` would need Input Monitoring and only observes.)
final class GlobalHotKeys {
    private struct Registration {
        let ref: EventHotKeyRef
        let action: () -> Void
    }

    private static let signature: OSType = 0x4D42_5444 // 'MBTD'
    private var registrations: [UInt32: Registration] = [:]
    private var handlerRef: EventHandlerRef?
    private var nextID: UInt32 = 1

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData -> OSStatus in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let err = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                        nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard err == noErr else { return err }
            let hotKeys = Unmanaged<GlobalHotKeys>.fromOpaque(userData).takeUnretainedValue()
            return hotKeys.fire(hotKeyID) ? noErr : OSStatus(eventNotHandledErr)
        }, 1, &spec, selfPtr, &handlerRef)
        if status != noErr {
            NSLog("MenuBarToDo: could not install the hotkey event handler (OSStatus \(status)); shortcuts are disabled")
        }
    }

    deinit {
        for registration in registrations.values { UnregisterEventHotKey(registration.ref) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }

    /// Registers `combo`. A refusal is logged and skipped; the app stays usable without
    /// shortcuts. Note the system only refuses a combination another *Carbon* hotkey
    /// holds (e.g. a second instance of this app) — a plain menu shortcut in the
    /// frontmost app registers fine and is simply shadowed.
    func register(_ combo: KeyCombo, action: @escaping () -> Void) {
        guard handlerRef != nil else { return }
        let id = EventHotKeyID(signature: GlobalHotKeys.signature, id: nextID)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(combo.keyCode, combo.carbonModifiers, id,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            NSLog("MenuBarToDo: could not register \(combo.displayString) (OSStatus \(status)) — held by another hotkey")
            return
        }
        registrations[nextID] = Registration(ref: ref, action: action)
        nextID += 1
    }

    private func fire(_ id: EventHotKeyID) -> Bool {
        guard id.signature == GlobalHotKeys.signature, let registration = registrations[id.id] else { return false }
        // Carbon delivers hotkey events on the main run loop; the actions drive AppKit.
        MainActor.assumeIsolated { registration.action() }
        return true
    }
}
