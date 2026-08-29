import SwiftUI
import UniformTypeIdentifiers

/// Open tasks grouped by due label, with drag & drop between groups/rows.
///
/// Drag & drop is deliberately *not* attached to every row: `.onDrag`/`.onDrop`
/// wrap their view in AppKit-backed views that ignore SwiftUI clipping and
/// scaling, which broke the row collapse animation. Instead there is one drop
/// target for the whole list; rows and groups publish their frames and the
/// target slot is computed from the pointer position. The drag source is the
/// grip handle (with a row-shaped preview).
struct TaskListView: View {
    @Environment(TaskStore.self) private var store
    @Environment(PanelSettings.self) private var settings
    @State private var frames = FrameRegistry()
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(store.groups) { group in
                    GroupView(group: group)
                }
            }
            .padding(.top, 6)
            .padding(.bottom, 4)
            .coordinateSpace(name: FrameRegistry.space)
            .onPreferenceChange(GroupFramesKey.self) { frames.groups = $0 }
            .onPreferenceChange(RowFramesKey.self) { frames.rows = $0 }
            .onDrop(of: [UTType.plainText], delegate: ListDropDelegate(store: store, frames: frames))
            .scrollFadeContent(height: $contentHeight)
        }
        .scrollFade(contentHeight: contentHeight)
        // No scroll indicator: with "always show scroll bars" it pops in/out while a row
        // collapses and steals width from the rows. The list still scrolls (wheel/trackpad).
        .scrollIndicators(.never)
        .frame(maxHeight: settings.listMaxHeight)
    }
}

private struct GroupView: View {
    @Environment(TaskStore.self) private var store
    let group: TaskGroup

    @State private var headerHeight: CGFloat = 0

    private var active: Bool { store.isGroupActive(group) }
    /// A collapsed group has no visible rows, so any hover over it is "the end".
    private var showsEndIndicator: Bool { store.showsGroupIndicator(group) || (collapsed && active) }
    /// Month buckets fold up on a header click; near-term groups don't.
    private var collapsible: Bool { group.collapseKey != nil }
    private var collapsed: Bool { store.isCollapsed(group) }
    /// Every row is fading/collapsing → the header goes with them so the group leaves as one.
    private var fading: Bool { group.rows.allSatisfy { store.isFading($0.id) } }
    private var collapsing: Bool { group.rows.allSatisfy { store.isCollapsing($0.id) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header (incl. the group's top padding) collapses together with its last row.
            // Label only, no divider line — but full width, so the whole strip is the
            // click target of a month group.
            SectionLabel(text: collapsed ? "\(group.label.text) (\(group.rows.count))" : group.label.text,
                         color: Theme.tone(group.label.tone))
                .fixedSize()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(EdgeInsets(top: 8, leading: 14, bottom: 4, trailing: 14))
            .contentShape(Rectangle())
            .onTapGesture {
                guard collapsible else { return }
                withAnimation(.easeOut(duration: 0.2)) { store.toggleCollapsed(group) }
            }
            .pointerCursor(enabled: collapsible) // the only hint that a month header is clickable
            .opacity(fading ? 0 : 1)
            .animation(.easeOut(duration: TaskStore.fadeDuration), value: fading)
            .fixedSize(horizontal: false, vertical: true)
            .measureHeight($headerHeight)
            .collapsible(collapsing, naturalHeight: headerHeight)

            if !collapsed {
                ForEach(Array(group.rows.enumerated()), id: \.element.id) { index, task in
                    RowView(task: task, index: index, group: group)
                }
            }

            // Group's bottom padding, collapsible as well so nothing is left to jump.
            Color.clear
                .frame(height: 2)
                .collapsible(collapsing, naturalHeight: 2)
        }
        .overlay(alignment: .bottom) {
            if showsEndIndicator {
                InsertionLine().padding(.trailing, 6)
            }
        }
        .zIndex(showsEndIndicator ? 1 : 0)
        .padding(.horizontal, 8)
        .animation(.easeOut(duration: 0.12), value: active)
        .reportFrame { GroupFramesKey.self } value: { [GroupFrame(id: group.id, frame: $0)] }
    }
}

private struct RowView: View {
    @Environment(TaskStore.self) private var store
    let task: TodoTask
    let index: Int
    let group: TaskGroup

    @State private var checkHovering = false
    @State private var height: CGFloat = 0

    /// True between the click on the check and the row's removal (the "done" animation).
    private var completing: Bool { store.isCompleting(task.id) }
    /// Second phase: the row fades out.
    private var fading: Bool { store.isFading(task.id) }
    /// Final phase: the (invisible) row shrinks to 0 pt before it is removed.
    private var collapsing: Bool { store.isCollapsing(task.id) }

    var body: some View {
        let due = DueLabel.row(for: task.due, task.due2, style: store.settings.dateFormat, today: store.today)
        // The circle carries the same tone as the due line under it: red when the task
        // is overdue, mint when it is today's, grey for everything further out.
        let ring = Theme.tone(due.tone)
        HStack(alignment: .top, spacing: 8) {
            DragHandle(task: task)
                .opacity(completing ? 0 : 1)
                // A zero-opacity view still hit-tests; don't let the invisible grip
                // start a drag on a row that is about to be removed.
                .allowsHitTesting(!completing)

            Button(action: complete) {
                ZStack {
                    // Outline while open (always, so the check reads on the busy scene);
                    // hidden once checked so only the solid disc remains (an outline on top
                    // of the disc would read as a darker ring). Hover tints the inside.
                    // The disc and tick stay mint whatever the tone — ticking a task off
                    // is the same good moment whether it was overdue or not.
                    Circle()
                        .fill(ring.opacity(checkHovering ? 0.18 : 0))
                    Circle()
                        .strokeBorder(ring, lineWidth: 1.5)
                        .opacity(completing ? 0 : 1)
                    Circle()
                        .fill(Theme.blue)
                        .scaleEffect(completing ? 1 : 0.2)
                        .opacity(completing ? 1 : 0)
                    Text("✓")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.onAccent)
                        .scaleEffect(completing ? 1 : 0.4)
                        .opacity(completing ? 1 : 0)
                }
                .frame(width: 18, height: 18)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .pointerCursor()
            .onHover { checkHovering = $0 }
            .help("Als erledigt markieren")
            .accessibilityLabel("Als erledigt markieren")

            // Title / description (if any) / due line — always ends with the due line.
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(completing ? Theme.muted : Theme.ink)
                    .strikethrough(completing, color: Theme.muted)
                    .lineSpacing(2)
                    // A pasted paragraph would otherwise stretch one row over the
                    // whole panel; the full text is in the edit form.
                    .lineLimit(2)
                if store.settings.showDescriptions, !task.details.isEmpty {
                    Text(task.details)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.muted)
                        .lineSpacing(2)
                        .lineLimit(2)
                }
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.system(size: 10, weight: .medium))
                    Text(due.text)
                        .font(.system(size: 11.5))
                }
                .foregroundStyle(Theme.tone(due.tone))
                .padding(.top, 1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(EdgeInsets(top: 8, leading: 6, bottom: 8, trailing: 14))
        .contentShape(Rectangle())
        .pointerCursor()
        .onTapGesture { if !completing { store.openEdit(task) } }
        .opacity(store.dragID == task.id && store.dropHover != nil ? 0.45 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.6), value: completing)
        // Fade-out step of the check-off, before the row collapses.
        .opacity(fading ? 0 : 1)
        .animation(.easeOut(duration: TaskStore.fadeDuration), value: fading)
        .overlay(alignment: .top) {
            if store.showsRowLine(at: index, in: group) {
                InsertionLine()
            }
        }
        // Keep the natural height stable even while the outer frame collapses it.
        .fixedSize(horizontal: false, vertical: true)
        .measureHeight($height)
        .collapsible(collapsing, naturalHeight: height)
        .reportFrame { RowFramesKey.self } value: { [RowFrame(groupID: group.id, index: index, frame: $0)] }
    }

    /// Show the checked state first, move the task to "Erledigt" a moment later.
    private func complete() {
        store.beginComplete(task.id)
    }
}

/// 2×3 dot grip — the drag source for reordering.
private struct DragHandle: View {
    @Environment(TaskStore.self) private var store
    let task: TodoTask

    var body: some View {
        GripDots()
            .frame(height: 18)
            .padding(.horizontal, 3)
            .contentShape(Rectangle())
            .grabCursor()
            .help("Zum Verschieben ziehen")
            .onDrag {
                store.beginDrag(task.id)
                return NSItemProvider(object: task.id.uuidString as NSString)
            } preview: {
                DragPreview()
            }
    }
}

/// The grip's 2×3 dots, shared by the row handle and the drag preview.
private struct GripDots: View {
    var body: some View {
        VStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 3) {
                    Circle().fill(Theme.line).frame(width: 3, height: 3)
                    Circle().fill(Theme.line).frame(width: 3, height: 3)
                }
            }
        }
    }
}

/// Nothing follows the pointer while dragging. A drag image hangs *outside* the window,
/// so anything with substance to it — the row-wide card with the task title this used to
/// be, or the grip on a chip — is carried across the desktop for the whole drag. The list
/// already says everything: the source row dims and the insertion line marks where it
/// lands. An empty preview would fall back to AppKit's own snapshot of the grip, so this
/// is a transparent point instead.
private struct DragPreview: View {
    var body: some View {
        Color.clear.frame(width: 1, height: 1)
    }
}

// MARK: - Drop target

/// One drop target for the whole list. The pointer position is mapped to a
/// `DropSlot` using the frames rows and groups publish: the pointer above a
/// row's midpoint → slot before it, below → slot after it; a group's header →
/// its first slot, its bottom padding → its last slot. The insertion line is
/// drawn at that slot and the drop uses the very same slot.
private struct ListDropDelegate: DropDelegate {
    static let owner = "list"
    let store: TaskStore
    let frames: FrameRegistry

    func validateDrop(info: DropInfo) -> Bool { store.dragID != nil }

    func dropEntered(info: DropInfo) { report(info) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        report(info)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        store.clearHover(owner: ListDropDelegate.owner)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let id = store.dragID, let slot = frames.slot(at: info.location) else {
            // Don't leave the session's drag state armed after a failed drop —
            // a stale dragID would accept the next unrelated plain-text drag
            // and move this task wherever that lands.
            store.clearDrag()
            return false
        }
        store.move(id, to: slot)
        return true
    }

    private func report(_ info: DropInfo) {
        if let slot = frames.slot(at: info.location) {
            store.setHover(owner: ListDropDelegate.owner, slot: slot)
        }
    }
}

/// Latest frames of groups and rows in the list's coordinate space.
private final class FrameRegistry {
    static let space = "list"
    var groups: [GroupFrame] = []
    var rows: [RowFrame] = []

    func slot(at point: CGPoint) -> DropSlot? {
        guard !groups.isEmpty else { return nil }
        let group = groups.first { $0.frame.minY <= point.y && point.y < $0.frame.maxY }
            ?? groups.min { abs($0.frame.midY - point.y) < abs($1.frame.midY - point.y) }
        guard let group else { return nil }
        let groupRows = rows.filter { $0.groupID == group.id }
        // Rows whose midpoint is above the pointer are kept before the dragged task.
        let index = groupRows.filter { $0.frame.midY <= point.y }.count
        return DropSlot(groupID: group.id, index: index)
    }
}

struct GroupFrame: Equatable {
    let id: String
    let frame: CGRect
}

struct RowFrame: Equatable {
    let groupID: String
    let index: Int
    let frame: CGRect
}

private struct GroupFramesKey: PreferenceKey {
    static let defaultValue: [GroupFrame] = []
    static func reduce(value: inout [GroupFrame], nextValue: () -> [GroupFrame]) { value += nextValue() }
}

private struct RowFramesKey: PreferenceKey {
    static let defaultValue: [RowFrame] = []
    static func reduce(value: inout [RowFrame], nextValue: () -> [RowFrame]) { value += nextValue() }
}

// MARK: - Helpers

private extension View {
    /// Writes the view's rendered height into `height` (natural height for the collapse).
    func measureHeight(_ height: Binding<CGFloat>) -> some View {
        background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { height.wrappedValue = geo.size.height }
                    .onChange(of: geo.size.height) { _, new in height.wrappedValue = new }
            }
        )
    }

    /// Publishes the view's frame in the list coordinate space through `key`.
    func reportFrame<K: PreferenceKey>(_ key: () -> K.Type, value: @escaping (CGRect) -> K.Value) -> some View {
        let keyType = key()
        return background(
            GeometryReader { geo in
                Color.clear.preference(key: keyType, value: value(geo.frame(in: .named(FrameRegistry.space))))
            }
        )
    }

    /// Animates the view's height from its natural height to 0 when `collapsed` turns
    /// true. Implemented as an `Animatable` modifier so SwiftUI re-runs *layout* with
    /// the interpolated fraction on every frame (a plain animated `.frame(height:)`
    /// jumped straight to the final layout). Everything underneath — and the panel
    /// window, which follows the reported size — reflows with it.
    func collapsible(_ collapsed: Bool, naturalHeight: CGFloat) -> some View {
        modifier(Collapse(fraction: collapsed ? 0 : 1, naturalHeight: naturalHeight))
            .animation(.easeOut(duration: TaskStore.collapseDuration), value: collapsed)
    }
}

/// Height collapse driven by an animatable fraction (1 = natural height, 0 = gone).
/// The content is squashed from the top on the same fraction so it always fits its
/// frame and never overlaps the views below.
private struct Collapse: ViewModifier, Animatable {
    var fraction: CGFloat
    let naturalHeight: CGFloat

    var animatableData: CGFloat {
        get { fraction }
        set { fraction = newValue }
    }

    func body(content: Content) -> some View {
        let f = min(max(fraction, 0), 1)
        content
            .scaleEffect(x: 1, y: max(f, 0.001), anchor: .top)
            .frame(height: naturalHeight > 0 ? naturalHeight * f : nil, alignment: .top)
            .clipped()
    }
}
