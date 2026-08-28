import SwiftUI

/// Design tokens: a flat, warm off-white surface with a teal-green accent (after
/// the "Flow" timer app). Text colors use semantic AppKit colors so the panel stays
/// legible in dark mode; accents keep the design's exact values.
enum Theme {
    /// Mint accent (#A8DCCB), readable on the dark ground of the pixel scene. Still
    /// called `blue` at call sites from the original design; `accent` is preferred.
    static let accent = Color(red: 168 / 255, green: 220 / 255, blue: 203 / 255)
    static let blue = accent
    /// Text/icons drawn on top of a filled accent (deep teal, #173D33).
    static let onAccent = Color(red: 23 / 255, green: 61 / 255, blue: 51 / 255)
    /// Soft mint (#BFD3CE) for tinted, inactive accent elements.
    static let accentSoft = Color(red: 191 / 255, green: 211 / 255, blue: 206 / 255)
    static let red = Color(red: 255 / 255, green: 59 / 255, blue: 48 / 255)          // #FF3B30

    static let ink = Color(nsColor: .labelColor)                                     // #1D1D1F
    static let ink2 = Color(nsColor: .labelColor).opacity(0.85)                      // #3A3A3C
    static let muted = Color(nsColor: .secondaryLabelColor)                          // #86868B
    static let muted2 = Color(nsColor: .tertiaryLabelColor)                          // #A1A1A6
    static let line = Color.primary.opacity(0.22)                                    // #C7C7CC
    static let fieldBackground = Color.primary.opacity(0.05)
    static let chipBackground = Color.primary.opacity(0.055)
    static let hoverBackground = Color.primary.opacity(0.07)
    static let rowHoverBackground = Color.primary.opacity(0.045)
    static let surface = Color(nsColor: surfaceNSColor)
    /// Opaque panel background: Flow's off-white (#F2F1F0) in light mode, a matching
    /// warm dark gray in dark mode.
    static let surfaceNSColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? surfaceDarkNSColor
            : NSColor(red: 242 / 255, green: 241 / 255, blue: 240 / 255, alpha: 1)
    }
    /// The dark variant on its own, for the AppKit views under the panel's content.
    /// PanelView forces `colorScheme: .dark`, but a plain NSView resolves a dynamic
    /// colour against the *system* appearance — so in light mode `surfaceNSColor`
    /// hands back near-white, which is not a colour this panel ever wants to paint.
    static let surfaceDarkNSColor = NSColor(red: 30 / 255, green: 30 / 255, blue: 29 / 255, alpha: 1)

    static func tone(_ tone: DueTone) -> Color {
        switch tone {
        case .overdue: return red
        case .today: return blue
        case .neutral: return muted
        }
    }

    /// Panel width from the design.
    static let panelWidth: CGFloat = 330
    static let listMaxHeight: CGFloat = 410
    static let calendarMaxHeight: CGFloat = 196

    /// Height of the pixel-art band above the content: just enough to keep the
    /// computer fully in view (see SurfaceView).
    static let sceneBand: CGFloat = 150
}

// MARK: - Cursors (the design's `cursor: pointer` / `cursor: grab`)

extension View {
    /// Pointing-hand cursor while hovering, for anything clickable. `enabled: false`
    /// leaves the arrow (for views that are only sometimes clickable).
    func pointerCursor(enabled: Bool = true) -> some View {
        modifier(CursorModifier(kind: .pointer, enabled: enabled))
    }
    /// Open-hand cursor for drag handles.
    func grabCursor() -> some View { modifier(CursorModifier(kind: .grab)) }
}

private struct CursorModifier: ViewModifier {
    enum Kind { case pointer, grab }
    let kind: Kind
    var enabled = true
    @State private var hovering = false

    func body(content: Content) -> some View {
        if !enabled {
            content
        } else if #available(macOS 15, *) {
            content.pointerStyle(kind == .pointer ? .link : .grabIdle)
        } else {
            // macOS 14 fallback: set the cursor by hand and restore it when the
            // view leaves the screen mid-hover (e.g. a button that re-renders the panel).
            content
                .onHover { inside in
                    hovering = inside
                    (inside ? cursor : NSCursor.arrow).set()
                }
                .onDisappear { if hovering { NSCursor.arrow.set() } }
        }
    }

    private var cursor: NSCursor { kind == .pointer ? .pointingHand : .openHand }
}

// MARK: - Shared small components

/// Treatment for the controls that sit directly on the pixel landscape — the pin,
/// the header ✕ and the filter. The scene behind them is busy and changes with the
/// hour, so unlike the buttons inside cards they cannot borrow contrast from their
/// background: the chip is always drawn, not just on hover. Same 6 pt radius as the
/// hover chips elsewhere.
enum SceneChip {
    static let shape = RoundedRectangle(cornerRadius: 6)
    static func background(hovering: Bool) -> Color { .black.opacity(hovering ? 0.55 : 0.38) }
    static func glyph(hovering: Bool) -> Color { hovering ? .white : .white.opacity(0.85) }
}

/// 22×22 "✕"-style icon button with the design's hover treatment.
struct IconButton: View {
    /// SF Symbol name, preferred over `symbol`: SwiftUI centres a Text's *line box*
    /// (ascender→descender), not the glyph's ink, so a character that leaves the
    /// descender space empty renders visibly high — "✕" at 12 pt sat 0.35 pt above
    /// centre. SF Symbols are optically centred, and match the pin and filter next
    /// to them. Sized to the pin's 11 pt semibold.
    var systemImage: String? = nil
    /// Literal character, for glyphs with no good SF Symbol (the calendar's ↺).
    var symbol: String = ""
    let help: String
    /// Set for the buttons that sit on the landscape rather than in a card; they get
    /// SceneChip's always-on dark backing instead of the muted hover-only style.
    var onScene = false
    var tint: Color = Theme.muted
    var hoverTint: Color = Theme.ink
    var hoverBackground: Color = Theme.hoverBackground
    /// Overrides the glyph colour in either style, hovering or not (the armed trash).
    var glyph: Color? = nil
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            label
                .foregroundStyle(glyphColor)
                .frame(width: 22, height: 22)
                .background(backgroundColor, in: SceneChip.shape)
                .contentShape(SceneChip.shape)
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }

    @ViewBuilder private var label: some View {
        if let systemImage {
            Image(systemName: systemImage).font(.system(size: 11, weight: .semibold))
        } else {
            Text(symbol).font(.system(size: 12))
        }
    }

    private var glyphColor: Color {
        if let glyph { return glyph }
        return onScene ? SceneChip.glyph(hovering: hovering) : (hovering ? hoverTint : tint)
    }

    private var backgroundColor: Color {
        onScene ? SceneChip.background(hovering: hovering) : (hovering ? hoverBackground : .clear)
    }
}

/// Text-only footer link ("+ Aufgabe hinzufügen", "Erledigt (2)").
struct LinkButton: View {
    enum Kind { case accent, danger, muted }

    let title: String
    var kind: Kind = .accent
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: kind == .muted ? .medium : .semibold))
                .foregroundStyle(color)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .onHover { hovering = $0 }
    }

    private var color: Color {
        switch kind {
        case .accent: return Theme.blue
        case .danger: return Theme.red
        case .muted: return hovering ? Theme.ink : Theme.muted
        }
    }
}

/// Full-width blue call-to-action; dimmed while the form isn't ready.
struct PrimaryButton: View {
    let title: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                // Disabled is its own look, not the enabled one at 40 %: the label is dark
                // green on mint, and faded over the dark ground it simply vanished.
                .foregroundStyle(enabled ? Theme.onAccent : .white.opacity(0.55))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(enabled ? Theme.blue : Theme.blue.opacity(0.22), in: RoundedRectangle(cornerRadius: 9))
                .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        // A disabled button that still offers a pointer cursor reads as broken.
        .pointerCursor(enabled: enabled)
        .disabled(!enabled)
        .animation(.easeOut(duration: 0.12), value: enabled)
        .padding(.top, 2)
    }
}

/// Pill chip ("Heute", "Morgen", date pill).
struct Chip: View {
    enum Style { case neutral, selected, accent }

    let title: String
    var style: Style = .neutral
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(foreground)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(background, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .onHover { hovering = $0 }
    }

    private var foreground: Color {
        switch style {
        case .neutral: return Theme.ink2
        case .selected: return Theme.onAccent
        case .accent: return Theme.blue
        }
    }

    private var background: Color {
        switch style {
        case .neutral: return Theme.chipBackground
        case .selected: return Theme.blue
        case .accent: return Theme.blue.opacity(hovering ? 0.18 : 0.10)
        }
    }
}

/// Blue dot + 2pt line used as the drag insertion indicator.
struct InsertionLine: View {
    var body: some View {
        HStack(spacing: 0) {
            Circle().fill(Theme.blue).frame(width: 6, height: 6)
            Capsule().fill(Theme.blue).frame(height: 2)
        }
        .padding(.leading, 6)
        .padding(.trailing, 12)
        .allowsHitTesting(false)
    }
}

/// Section label style: 10.5pt bold, tracked, uppercase.
struct SectionLabel: View {
    let text: String
    var color: Color = Theme.muted

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .bold))
            .kerning(0.7)
            .foregroundStyle(color)
    }
}
