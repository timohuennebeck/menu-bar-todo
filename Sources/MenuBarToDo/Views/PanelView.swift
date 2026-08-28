import SwiftUI

/// Root of the popover: switches between list / add / edit / done and
/// always shows the footer.
struct PanelView: View {
    @Environment(TaskStore.self) private var store
    /// Reports the panel's rendered size on every change (including each frame of
    /// a layout animation) so the popover window can follow it exactly.
    var onSizeChange: ((CGSize) -> Void)? = nil

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
        .environment(\.colorScheme, .dark)
        .frame(width: Theme.panelWidth)
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
                    .background(hovering ? Theme.hoverBackground : .clear, in: RoundedRectangle(cornerRadius: 6))
                    .contentShape(RoundedRectangle(cornerRadius: 6))
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
        store.filter.isActive ? Theme.blue : (hovering ? Theme.ink : Theme.muted)
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
    var body: some View {
        VStack(spacing: 3) {
            Text("Inbox 0, To-Do-Edition")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Text("Keine offenen Tasks.")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.muted)
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
            case .add:
                // The form's own submit button already says "Task hinzufügen"; a second
                // one in the footer would be a duplicate that just reopens the same form.
                EmptyView()
            case .list, .done:
                LinkButton(title: "+ Task hinzufügen") { store.openAdd() }
            }
            Spacer(minLength: 0)
            LinkButton(title: "Erledigt (\(store.done.count))", kind: .muted) { store.goDone() }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}
