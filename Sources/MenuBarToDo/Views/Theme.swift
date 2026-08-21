import SwiftUI

/// Design tokens from the .dc.html. Text colors use semantic AppKit colors so
/// the panel stays legible in dark mode; accents keep the design's exact values.
enum Theme {
    static let blue = Color(red: 10 / 255, green: 132 / 255, blue: 255 / 255)        // #0A84FF
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
    static let surface = Color(nsColor: .windowBackgroundColor)

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

/// 22×22 "✕"-style icon button with the design's hover treatment.
struct IconButton: View {
    let symbol: String
    let help: String
    var tint: Color = Theme.muted
    var hoverTint: Color = Theme.ink
    var hoverBackground: Color = Theme.hoverBackground
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(symbol)
                .font(.system(size: 12))
                .foregroundStyle(hovering ? hoverTint : tint)
                .frame(width: 22, height: 22)
                .background(hovering ? hoverBackground : .clear, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Text-only footer link ("+ Task hinzufügen", "Erledigt (2)").
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
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(Theme.blue, in: RoundedRectangle(cornerRadius: 9))
                .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .pointerCursor()
        // Not just dimmed: a hit-testable "disabled" button with a pointer cursor
        // that swallows the click reads as broken.
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
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
        case .selected: return .white
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
