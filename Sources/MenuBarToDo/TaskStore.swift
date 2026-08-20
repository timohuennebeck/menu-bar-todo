import Foundation
import Observation

enum Route: Equatable {
    case list
    case add
    case edit(UUID)
    case done

    var isEdit: Bool {
        if case .edit = self { return true }
        return false
    }
}

/// The add/edit form's working copy.
struct Draft {
    var title = ""
    var details = ""
    var due: Day = .today
    var due2: Day? = nil
    var calendarOpen = false

    var isReady: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

struct TaskGroup: Identifiable {
    let label: DueLabel
    /// Due date of the first row (used for the Kopfzeile/Rahmen drop-zone styles).
    let due: Day
    let rows: [TodoTask]
    var id: String { label.text }
}

/// An insertion point in the visible list: `index` is a position among
/// `group.rows`, 0 = before the first row … rows.count = after the last row.
struct DropSlot: Equatable {
    let groupID: String
    let index: Int
}

/// The current drop target plus which view reported it, so a view only clears
/// its own hover state (row and group targets are nested).
struct DropHover: Equatable {
    let owner: String
    let slot: DropSlot
}

/// Single source of truth: persisted tasks + transient panel/drag state.
/// Logic is a port of the `Component` class in the .dc.html.
@Observable
final class TaskStore {
    private(set) var items: [TodoTask]
    private(set) var done: [DoneTask]
    var settings = Settings()

    var route: Route = .list
    var draft = Draft()
    var filter: TaskFilter = .none

    // Drag & drop
    var dragID: UUID?
    /// Where the dragged task would land right now (nil when not over a target).
    var dropHover: DropHover?

    private let persistence: Persistence?

    init(persistence: Persistence? = .default) {
        self.persistence = persistence
        switch persistence?.load() {
        case .loaded(let saved):
            items = saved.items
            done = saved.done
        case .failed:
            // The unreadable file was moved aside by load(). Start empty instead of
            // masking the failure with demo data, and write nothing until the user
            // does — so the backup stays the only copy of their data.
            items = []
            done = []
        case .missing, nil:
            let seed = TaskStore.seed()
            items = seed.items
            done = seed.done
            persistence?.save(seed)
        }
    }

    // MARK: - Derived

    /// Stable sort by due date (insertion order preserved within a day).
    var sortedItems: [TodoTask] {
        items.enumerated()
            .sorted { a, b in a.element.due != b.element.due ? a.element.due < b.element.due : a.offset < b.offset }
            .map(\.element)
    }

    /// Sorted items that pass the active filter — what the list shows.
    var filteredItems: [TodoTask] {
        sortedItems.filter { filter.matches($0) }
    }

    var groups: [TaskGroup] {
        var order: [String] = []
        var buckets: [String: (label: DueLabel, due: Day, rows: [TodoTask])] = [:]
        for item in filteredItems {
            let label = DueLabel.make(for: item.due, style: settings.dateFormat)
            if buckets[label.text] == nil {
                buckets[label.text] = (label, item.due, [])
                order.append(label.text)
            }
            buckets[label.text]?.rows.append(item)
        }
        return order.compactMap { key in
            buckets[key].map { TaskGroup(label: $0.label, due: $0.due, rows: $0.rows) }
        }
    }

    var editingTask: TodoTask? {
        if case .edit(let id) = route { return items.first { $0.id == id } }
        return nil
    }

    // MARK: - Navigation

    func panelWillOpen() {
        clearDrag()
    }

    func openAdd() {
        draft = Draft()
        route = .add
    }

    func openEdit(_ task: TodoTask) {
        draft = Draft(title: task.title, details: task.details, due: task.due, due2: task.due2, calendarOpen: false)
        route = .edit(task.id)
    }

    func cancel() {
        draft = Draft()
        route = .list
    }

    func goList() { route = .list }
    func goDone() { route = .done }

    // MARK: - Mutations

    func submitDraft() {
        switch route {
        case .add: addTask()
        case .edit: saveTask()
        default: break
        }
    }

    func addTask() {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        items.append(TodoTask(title: title,
                              details: draft.details.trimmingCharacters(in: .whitespacesAndNewlines),
                              due: draft.due,
                              due2: draft.due2))
        draft = Draft()
        route = .list
        persist()
    }

    func saveTask() {
        guard case .edit(let id) = route else { return }
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].title = title
        items[idx].details = draft.details.trimmingCharacters(in: .whitespacesAndNewlines)
        items[idx].due = draft.due
        items[idx].due2 = draft.due2
        draft = Draft()
        route = .list
        persist()
    }

    func deleteEditingTask() {
        guard case .edit(let id) = route else { return }
        items.removeAll { $0.id == id }
        draft = Draft()
        route = .list
        persist()
    }

    /// Tasks currently playing their check-off animation (still in `items`).
    private(set) var completingIDs: Set<UUID> = []
    /// Subset of `completingIDs` that is fading out.
    private(set) var fadingIDs: Set<UUID> = []
    /// Subset of `fadingIDs` whose row is collapsing to zero height right now.
    private(set) var collapsingIDs: Set<UUID> = []
    /// `MENUBAR_TODO_SLOWMO=5` stretches the check-off animation 5× (debugging captures).
    static let animationScale: Double = {
        Double(ProcessInfo.processInfo.environment["MENUBAR_TODO_SLOWMO"] ?? "") ?? 1
    }()
    /// How long the checked state stays visible before the row fades.
    static let completionDelay: TimeInterval = 0.6 * animationScale
    /// Duration of the fade-out that precedes the collapse.
    static let fadeDuration: TimeInterval = 0.2 * animationScale
    /// Duration of the row's height collapse.
    static let collapseDuration: TimeInterval = 0.25 * animationScale

    func isCompleting(_ id: UUID) -> Bool { completingIDs.contains(id) }
    func isFading(_ id: UUID) -> Bool { fadingIDs.contains(id) }
    func isCollapsing(_ id: UUID) -> Bool { collapsingIDs.contains(id) }

    /// Check-off in four steps: checked state (+ chime) now → row fades out after
    /// `delay` → row collapses to 0 pt → task moves to "Erledigt" once invisible, so
    /// the removal itself changes nothing on screen. Safe against double clicks.
    func beginComplete(_ id: UUID, delay: TimeInterval = TaskStore.completionDelay, sound: Bool = true) {
        guard !completingIDs.contains(id), items.contains(where: { $0.id == id }) else { return }
        completingIDs.insert(id)
        if sound, settings.completionSound { CompletionSound.shared.play() }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.fadingIDs.insert(id)
            DispatchQueue.main.asyncAfter(deadline: .now() + TaskStore.fadeDuration) { [weak self] in
                guard let self else { return }
                self.collapsingIDs.insert(id)
                DispatchQueue.main.asyncAfter(deadline: .now() + TaskStore.collapseDuration + 0.05) { [weak self] in
                    guard let self else { return }
                    self.complete(id)
                    self.collapsingIDs.remove(id)
                    self.fadingIDs.remove(id)
                    self.completingIDs.remove(id)
                }
            }
        }
    }

    func complete(_ id: UUID) {
        guard let task = items.first(where: { $0.id == id }) else { return }
        items.removeAll { $0.id == id }
        done.insert(DoneTask(id: task.id, title: task.title, details: task.details,
                             createdAt: task.createdAt, completedAt: .today), at: 0)
        persist()
    }

    func restore(_ id: UUID) {
        guard let task = done.first(where: { $0.id == id }) else { return }
        done.removeAll { $0.id == id }
        items.append(TodoTask(id: task.id, title: task.title, details: task.details ?? "",
                              due: .today, createdAt: task.createdAt ?? .today))
        persist()
    }

    /// Moves `dragID` to `slot`. The task takes the due date of the row it lands
    /// next to and is placed directly before/after that row in the backing array,
    /// so after the stable (due, order) sort it shows up exactly where the
    /// insertion line was drawn — also inside multi-day groups like "Überfällig".
    func move(_ dragID: UUID, to slot: DropSlot) {
        defer { clearDrag() }
        guard let dragged = items.first(where: { $0.id == dragID }),
              let group = groups.first(where: { $0.id == slot.groupID }) else { return }

        // Slot indices count the dragged row if it sits in this group; drop it from the picture.
        var index = slot.index
        if let own = group.rows.firstIndex(where: { $0.id == dragID }), slot.index > own { index -= 1 }
        let neighbors = group.rows.filter { $0.id != dragID }
        guard !neighbors.isEmpty else { return } // the group only contained the dragged task
        index = min(max(index, 0), neighbors.count)

        let insertBefore = index < neighbors.count
        let anchor = insertBefore ? neighbors[index] : neighbors[neighbors.count - 1]

        var moved = dragged
        if moved.due != anchor.due {
            moved.due = anchor.due
            moved.due2 = nil
        }
        var rest = items.filter { $0.id != dragID }
        guard let anchorIndex = rest.firstIndex(where: { $0.id == anchor.id }) else { return }
        rest.insert(moved, at: insertBefore ? anchorIndex : anchorIndex + 1)
        items = rest
        persist()
    }

    // MARK: - Draft helpers

    func selectDue(_ day: Day) {
        draft.due = day
        draft.due2 = nil
    }

    /// Calendar tap: first tap sets the start, a later tap after it sets the end.
    func selectCalendarDay(_ day: Day) {
        if draft.due2 == nil, day > draft.due {
            draft.due2 = day
        } else {
            draft.due = day
            draft.due2 = nil
        }
    }

    func clearRange() { draft.due2 = nil }
    func toggleCalendar() { draft.calendarOpen.toggle() }

    // MARK: - Drag state

    func beginDrag(_ id: UUID) {
        dragID = id
        dropHover = nil
    }

    func clearDrag() {
        dragID = nil
        dropHover = nil
    }

    /// Reports a hover target. With `onlyIfFree`, a target won't override one
    /// reported by a different owner (used by groups so a hovered row wins).
    func setHover(owner: String, slot: DropSlot, onlyIfFree: Bool = false) {
        if onlyIfFree, let current = dropHover, current.owner != owner { return }
        let hover = DropHover(owner: owner, slot: slot)
        if dropHover != hover { dropHover = hover }
    }

    func clearHover(owner: String) {
        if dropHover?.owner == owner { dropHover = nil }
    }

    /// The slot to preview — nil when not dragging or when dropping wouldn't move anything.
    var activeSlot: DropSlot? {
        guard dragID != nil, let hover = dropHover, !isNoOp(hover.slot) else { return nil }
        return hover.slot
    }

    /// A slot directly above or below the dragged row leaves the list unchanged.
    private func isNoOp(_ slot: DropSlot) -> Bool {
        guard let dragID,
              let group = groups.first(where: { $0.id == slot.groupID }),
              let own = group.rows.firstIndex(where: { $0.id == dragID }) else { return false }
        return slot.index == own || slot.index == own + 1
    }

    func isGroupActive(_ group: TaskGroup) -> Bool {
        dragID != nil && dropHover?.slot.groupID == group.id
    }

    /// Line / slot after the group's last row.
    func showsGroupIndicator(_ group: TaskGroup) -> Bool {
        activeSlot == DropSlot(groupID: group.id, index: group.rows.count)
    }

    /// Line above the row at `index`.
    func showsRowLine(at index: Int, in group: TaskGroup) -> Bool {
        activeSlot == DropSlot(groupID: group.id, index: index)
    }

    // MARK: - Debug

    /// Jumps straight to a view; used by the preview window (see AppDelegate).
    func applyDebugRoute(_ name: String?) {
        switch name {
        case "add":
            openAdd()
        case "calendar":
            openAdd()
            draft.title = "Urlaub planen"
            draft.due = Day.today.adding(3)
            draft.due2 = Day.today.adding(9)
            draft.calendarOpen = true
        case "edit":
            if let first = sortedItems.first { openEdit(first) }
        case "done":
            goDone()
        case "empty":
            items.removeAll()
        case "filter":
            filter = .today
        case "filter-empty":
            filter = .today
            items.removeAll { filter.matches($0) }
        case "complete-anim":
            // Check off the first task one second after launch (for frame captures).
            if let first = sortedItems.first {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    self?.beginComplete(first.id, sound: false)
                }
            }
        case "drag-group", "drag-row":
            // Freeze a mid-drag state: first task dragged over the second group / its first row.
            guard let dragged = sortedItems.first, groups.count > 1 else { return }
            let target = groups[1]
            dragID = dragged.id
            dropHover = DropHover(owner: "debug",
                                  slot: DropSlot(groupID: target.id, index: name == "drag-row" ? 0 : target.rows.count))
        default:
            break
        }
    }

    // MARK: - Persistence / seed

    private func persist() {
        persistence?.save(Snapshot(items: items, done: done))
    }

    static func seed() -> Snapshot {
        let t = Day.today
        return Snapshot(
            items: [
                TodoTask(title: "Steuerunterlagen einreichen", due: t.adding(-1), createdAt: t.adding(-4)),
                TodoTask(title: "Design-Review vorbereiten", details: "Feedback aus Figma einarbeiten", due: t, createdAt: t.adding(-2)),
                TodoTask(title: "Zahnarzttermin bestätigen", due: t.adding(1), createdAt: t.adding(-1)),
                TodoTask(title: "Wochenbericht schreiben", details: "Zahlen aus dem Dashboard exportieren", due: t.adding(2), createdAt: t),
                TodoTask(title: "Geschenk für Lena besorgen", due: t.adding(6), createdAt: t)
            ],
            done: [
                DoneTask(id: UUID(), title: "Miete überweisen", createdAt: t.adding(-6), completedAt: t.adding(-1)),
                DoneTask(id: UUID(), title: "Flug einchecken", createdAt: t.adding(-3), completedAt: t)
            ]
        )
    }
}
