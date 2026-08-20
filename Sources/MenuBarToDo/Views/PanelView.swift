import SwiftUI

/// Root of the popover: switches between list / add / edit / done and
/// always shows the footer.
struct PanelView: View {
    @Environment(TaskStore.self) private var store
    /// Reports the panel's rendered size on every change (including each frame of
    /// a layout animation) so the popover window can follow it exactly.
    var onSizeChange: ((CGSize) -> Void)? = nil

    var body: some View {
        // Outer VStack + Spacer keeps the panel top-aligned if the window is momentarily
        // taller than the content, without making the root greedy for sizeThatFits.
        VStack(spacing: 0) {
            panel
            Spacer(minLength: 0)
        }
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
        .frame(width: Theme.panelWidth)
        .fixedSize(horizontal: false, vertical: true)
        // Clicking any non-interactive area (labels, padding, background) ends text editing,
        // like blurring an input on the web. Buttons/rows/fields in front still win the tap.
        .background(
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { NSApp.keyWindow?.makeFirstResponder(nil) }
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
                        Text(f.rawValue).tag(f)
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
            if store.route.isEdit {
                LinkButton(title: "Task löschen", kind: .danger) { store.deleteEditingTask() }
            } else {
                LinkButton(title: "+ Task hinzufügen") { store.openAdd() }
            }
            Spacer(minLength: 0)
            LinkButton(title: "Erledigt (\(store.done.count))", kind: .muted) { store.goDone() }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}
