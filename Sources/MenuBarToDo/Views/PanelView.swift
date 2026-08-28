import SwiftUI

/// Root of the popover: switches between list / add / edit / done and
/// always shows the footer.
struct PanelView: View {
    @Environment(TaskStore.self) private var store
    @Environment(PanelSettings.self) private var settings
    /// Width and list cap when the resize drag started; the drag offset is applied to these.
    @State private var resizeStart: (width: CGFloat, height: CGFloat)?
    /// Reports the panel's rendered size on every change (including each frame of
    /// a layout animation) so the popover window can follow it exactly.
    var onSizeChange: ((CGSize) -> Void)? = nil
    /// Closes the panel window. Nil in the preview window, which has no panel to close
    /// (and where the corner ✕ would be a dead control), so the button is dropped there.
    var onClose: (() -> Void)? = nil

    /// Whether the scene band shows the add button. It appears exactly where the footer
    /// link used to: never over a form, where it would be a no-op (.add) or would throw
    /// away what is being edited (.edit).
    nonisolated static func showsAddButton(for route: Route) -> Bool {
        switch route {
        case .list, .done: return true
        case .add, .edit: return false
        }
    }

    var body: some View {
        // The root adopts *exactly* the size the hosting view proposes, content pinned to
        // the top. The window follows the reported size one runloop turn later (see
        // PanelWindowController.resize), so for that one layout pass the content can be
        // taller than the window, e.g. when the calendar opens. Without `minHeight: 0` a
        // flexible frame grows to its child instead, and NSHostingView *centers* an
        // oversized root — the header would slide up out of view for that pass. Clamped,
        // the overflow is simply clipped at the bottom until the window catches up.
        //
        // Consequence: the hosting controller's sizeThatFits can't measure the content
        // any more (it returns whatever height is proposed); PanelWindowController.show()
        // forces a layout pass and reads the reported size instead.
        panel
            .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
    }

    /// The most the list may take for a panel with `room` between its top and the
    /// bottom of its screen: the room minus the chrome above and below the list.
    static func availableListHeight(room: CGFloat) -> CGFloat {
        room - PanelWindowController.edgeInset - Theme.sceneBand - PanelView.chromeBelowScene
    }

    /// Height of everything below the scene band that isn't the list (list header +
    /// footer, generous), used only to keep the resized panel on screen.
    static let chromeBelowScene: CGFloat = 90

    private func grip(_ edge: ResizeGripArea.Edge) -> some View {
        ResizeGripArea(edge: edge, onDrag: { offset, room in
            let start = resizeStart ?? (settings.panelWidth, settings.listMaxHeight)
            resizeStart = start
            if edge != .bottom {
                settings.panelWidth = PanelSettings.clampWidth(
                    start.width + offset.width, available: room.width - PanelWindowController.edgeInset)
            }
            if edge != .left {
                settings.listMaxHeight = PanelSettings.clampListHeight(
                    start.height + offset.height, available: PanelView.availableListHeight(room: room.height))
            }
        }, onDragEnded: { resizeStart = nil })
        .help("Zum Vergrößern ziehen")
    }

    private var panel: some View {
        VStack(spacing: 0) {
            switch store.route {
            case .list:
                if store.items.isEmpty {
                    EmptyStateView()
                } else {
                    ListHeaderView()
                    if store.filteredItems.isEmpty {
                        FilteredEmptyView(filter: store.filter)
                    } else {
                        TaskListView()
                    }
                }
            case .add:
                TaskFormView(mode: .add)
            case .edit:
                TaskFormView(mode: .edit)
            case .done:
                DoneListView()
            }
            FooterView()
        }
        // Content sits directly on the animated pixel landscape (SurfaceView), below the
        // scene on its dark ground — hence always light-on-dark, whatever the system theme.
        .padding(.top, Theme.sceneBand)
        // The landscape strip doubles as the grip for dragging the panel around.
        .overlay(alignment: .top) {
            WindowDragArea()
                .frame(height: Theme.sceneBand)
                .help("Zum Verschieben ziehen")
        }
        // Content action on the left, window chrome on the right. After the drag grip,
        // so it takes the click instead of starting a drag.
        .overlay(alignment: .topLeading) {
            if PanelView.showsAddButton(for: store.route) {
                IconButton(systemImage: "plus", help: "Task hinzufügen", onScene: true) {
                    store.openAdd()
                }
                .padding(8)
            }
        }
        // After the drag grip, so these get the click instead of starting a drag.
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 4) {
                PinButton()
                if let onClose {
                    // Closes the window whatever the pin says — the same door as the
                    // status item and ⌃⌘T. The ✕ in the form/done header means "cancel,
                    // back to the list" and is a different button.
                    IconButton(systemImage: "xmark", help: "Fenster schließen",
                               onScene: true, action: onClose)
                }
            }
            .padding(8)
        }
        // Resize grips: bottom edge = more rows before the list scrolls, left edge =
        // wider, the corner between them = both. Last, so they win over what is under them.
        .overlay(alignment: .bottom) {
            grip(.bottom).frame(height: ResizeGripArea.thickness)
        }
        .overlay(alignment: .leading) {
            grip(.left).frame(width: ResizeGripArea.thickness)
        }
        .overlay(alignment: .bottomLeading) {
            grip(.bottomLeft).frame(width: ResizeGripArea.cornerSize, height: ResizeGripArea.cornerSize)
        }
        .environment(\.colorScheme, .dark)
        .frame(width: settings.panelWidth)
        .fixedSize(horizontal: false, vertical: true)
        // Clicking any non-interactive area (labels, padding, background) ends text editing,
        // like blurring an input on the web, and collapses the calendar — it is a popup and
        // a click outside it dismisses it. Buttons/rows/fields in front still win the tap;
        // the calendar card swallows taps inside itself so they don't land here.
        .background(
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    NSApp.keyWindow?.makeFirstResponder(nil)
                    store.closeCalendar()
                }
        )
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { onSizeChange?(geo.size) }
                    .onChange(of: geo.size) { _, new in onSizeChange?(new) }
            }
        )
    }
}

/// Keeps the panel open when focus moves elsewhere. It lives on the pixel
/// landscape rather than in a content row so it is there in every route — list,
/// form, done list and the empty state.
///
/// That spot is whatever the scene paints there — bright sky by day, dark by night —
/// so it wears the shared SceneChip backing: a plain white glyph vanished against
/// the daytime sky.
struct PinButton: View {
    @Environment(PanelSettings.self) private var settings
    @State private var hovering = false

    var body: some View {
        Button { settings.isPinned.toggle() } label: {
            Image(systemName: settings.isPinned ? "pin.fill" : "pin")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(settings.isPinned ? .white : SceneChip.glyph(hovering: hovering))
                .frame(width: 22, height: 22)
                .background(SceneChip.background(hovering: hovering), in: SceneChip.shape)
                .contentShape(SceneChip.shape)
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .onHover { hovering = $0 }
        .help(settings.isPinned
              ? "Angeheftet — bleibt offen (Esc oder ⌃⌘T schließt)"
              : "Anheften, damit das Fenster offen bleibt")
        .accessibilityLabel("Anheften")
        .accessibilityAddTraits(settings.isPinned ? [.isSelected] : [])
    }
}

/// Count + filter menu above the list.
struct ListHeaderView: View {
    @Environment(TaskStore.self) private var store
    @State private var hovering = false

    var body: some View {
        @Bindable var store = store
        HStack(spacing: 8) {
            Text(countText)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Theme.muted)
            Spacer(minLength: 0)
            Menu {
                Picker("Filter", selection: $store.filter) {
                    ForEach(TaskFilter.allCases) { f in
                        Text("\(f.rawValue) (\(store.count(for: f)))").tag(f)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                Image(systemName: store.filter.isActive
                      ? "line.3.horizontal.decrease.circle.fill"
                      : "line.3.horizontal.decrease.circle")
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 24, height: 22)
                    .background(SceneChip.background(hovering: hovering), in: SceneChip.shape)
                    .contentShape(SceneChip.shape)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .foregroundStyle(iconColor)
            .tint(iconColor)
            .fixedSize()
            .pointerCursor()
            .onHover { hovering = $0 }
            .help("Filtern")
            .accessibilityLabel("Filter: \(store.filter.rawValue)")
        }
        .padding(EdgeInsets(top: 10, leading: 14, bottom: 0, trailing: 10))
    }

    private var iconColor: Color {
        store.filter.isActive ? Theme.accent : SceneChip.glyph(hovering: hovering)
    }

    private var countText: String {
        let n = store.filteredItems.count
        let base = "\(n) offen"
        return store.filter.isActive ? "\(base) · \(store.filter.rawValue)" : base
    }
}

/// Shown when the filter hides every open task.
struct FilteredEmptyView: View {
    @Environment(TaskStore.self) private var store
    let filter: TaskFilter

    var body: some View {
        VStack(spacing: 8) {
            VStack(spacing: 3) {
                Text("Keine Einträge für „\(filter.rawValue)“")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text(store.items.count == 1
                     ? "1 offener Task ist ausgeblendet."
                     : "\(store.items.count) offene Tasks sind ausgeblendet.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.muted)
            }
            Chip(title: "Filter entfernen", style: .accent) { store.filter = .none }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .padding(.horizontal, 20)
    }
}

struct EmptyStateView: View {
    @Environment(TaskStore.self) private var store

    var body: some View {
        // With no tasks there is nothing else to click, so the zero state carries its own
        // call to action rather than sending the user hunting for the band's + icon.
        VStack(spacing: 10) {
            VStack(spacing: 3) {
                Text("Inbox 0, To-Do-Edition")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text("Keine offenen Tasks.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.muted)
            }
            Chip(title: "Task hinzufügen", style: .accent) { store.openAdd() }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .padding(.horizontal, 20)
    }
}

struct FooterView: View {
    @Environment(TaskStore.self) private var store

    var body: some View {
        HStack {
            switch store.route {
            case .edit:
                LinkButton(title: "Task löschen", kind: .danger) { store.deleteEditingTask() }
            case .add, .list, .done:
                // Adding moved to the scene band's +; the footer carries only the
                // destructive link and the way over to the done list.
                EmptyView()
            }
            Spacer(minLength: 0)
            LinkButton(title: "Erledigt (\(store.done.count))", kind: .muted) { store.goDone() }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}
