import SwiftUI

/// Completed tasks; tapping the check restores a task (due today).
struct DoneListView: View {
    @Environment(TaskStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Erledigt")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 0)
                IconButton(symbol: "✕", help: "Schließen") { store.goList() }
            }
            .padding(EdgeInsets(top: 5, leading: 14, bottom: 8, trailing: 14))

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(store.done) { task in
                        DoneRow(task: task)
                    }
                    if store.done.isEmpty {
                        Text("Noch nichts erledigt.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 16)
                    }
                }
            }
            .scrollIndicators(.never)
            .frame(maxHeight: Theme.listMaxHeight)
        }
        .padding(.top, 6)
        .padding(.bottom, 4)
    }
}

private struct DoneRow: View {
    @Environment(TaskStore.self) private var store
    let task: DoneTask

    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button { store.restore(task.id) } label: {
                Text("✓")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.onAccent)
                    .frame(width: 18, height: 18)
                    .background(Theme.blue, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .pointerCursor()
            .help("Wieder öffnen")
            .accessibilityLabel("Wieder öffnen")

            VStack(alignment: .leading, spacing: 1) {
                Text(task.title)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .strikethrough()
                    .lineSpacing(2)
                if let completedAt = task.completedAt {
                    Text(German.completed(completedAt))
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.muted2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(hovering ? Theme.rowHoverBackground : .clear)
        .onHover { hovering = $0 }
    }
}
