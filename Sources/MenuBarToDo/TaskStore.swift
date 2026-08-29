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

    /// True while the add/edit form owns the panel — a state that can hold half-typed
    /// input, so only a deliberate cancel (the ✕, Esc: see `handleEscape`) clears it.
    var isForm: Bool { self == .add || isEdit }
}

/// The add/edit form's working copy.
struct Draft {
    var title = ""
    var details = ""
    /// New tasks default to today; nil = no due date (cleared in the calendar popup).
    var due: Day? = .today
    var due2: Day? = nil
    var calendarOpen = false

    var isReady: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

struct TaskGroup: Identifiable {
    let label: DueLabel
    /// The group's day (what a task dropped into it is re-dated to); for "Heute" that
    /// is today even when its first row is a range that started earlier. nil for the
    /// "Kein Datum" group.
    let due: Day?
    let rows: [TodoTask]
    /// "2026-09" for a month bucket (the user can collapse those; the key is what
    /// gets persisted, so "Später im August" doesn't re-collapse next August). nil
    /// for the near-term and undated groups, which always stay open.
    var collapseKey: String? = nil
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
    /// "Erstelle mehrere": keep the add form open after each task instead of returning
    /// to the list. Deliberately not persisted — a forgotten mode would quietly change
    /// what the submit button does days later; `openAdd` starts it off every time.
    var createsMultiple = false
    var filter: TaskFilter = .none
    /// Month groups the user folded up (`TaskGroup.collapseKey`s). Persisted.
    private(set) var collapsedMonths: Set<String> = []

    /// The current calendar day as *observable* state. Date-derived UI (groups,
    /// due labels, filters) reads this instead of Day.today so it re-derives when
    /// the day rolls over while the long-running app is open.
    private(set) var today: Day = .today
    @ObservationIgnored private var dayChangeObserver: NSObjectProtocol?

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
            done = TaskStore.prunedDone(saved.done, today: .today)
            collapsedMonths = saved.collapsedMonths
            if done.count != saved.done.count { persist() }
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
        dayChangeObserver = NotificationCenter.default.addObserver(forName: .NSCalendarDayChanged,
                                                                   object: nil, queue: .main) { [weak self] _ in
            self?.refreshToday()
        }
    }

    deinit {
        if let dayChangeObserver { NotificationCenter.default.removeObserver(dayChangeObserver) }
    }

    /// Re-reads the current day (the notification can be missed during sleep,
    /// so `panelWillOpen` calls this too).
    private func refreshToday() {
        let now = Day.today
        if today != now { today = now }
    }

    // MARK: - Derived

    /// Stable sort by due date (insertion order preserved within a day).
    /// The day a task sorts and groups under. A range that is already running
    /// (start < today ≤ end) belongs to "Heute", not "Überfällig" — the same rule
    /// the "Heute" filter applies — so it anchors on today instead of its start.
    func anchorDay(_ task: TodoTask) -> Day? {
        guard let due = task.due else { return nil }
        if let end = task.due2, due < today, today <= end { return today }
        return due
    }

    /// Dated tasks by day, undated ones last; ties keep the user's order.
    var sortedItems: [TodoTask] {
        items.enumerated()
            .sorted { a, b in
                let da = anchorDay(a.element), db = anchorDay(b.element)
                guard da != db else { return a.offset < b.offset }
                guard let da else { return false }
                guard let db else { return true }
                return da < db
            }
            .map(\.element)
    }

    /// How many open tasks `filter` would show — the "(3)" in the filter menu.
    func count(for filter: TaskFilter) -> Int {
        items.reduce(0) { $0 + (filter.matches($1, today: today) ? 1 : 0) }
    }

    /// What the status-bar badge shows: tasks due today plus overdue ones (the two
    /// filters are disjoint — a running range counts as today, not as overdue).
    var badgeCount: Int { count(for: .overdue) + count(for: .today) }

    /// Sorted items that pass the active filter — what the list shows.
    var filteredItems: [TodoTask] {
        sortedItems.filter { filter.matches($0, today: today) }
    }

    var groups: [TaskGroup] {
        var order: [String] = []
        var buckets: [String: (label: DueLabel, due: Day?, rows: [TodoTask])] = [:]
        for item in filteredItems {
            let anchor = anchorDay(item)
            let label = anchor.map { DueLabel.make(for: $0, style: settings.dateFormat, today: today) } ?? .undated
            if buckets[label.text] == nil {
                buckets[label.text] = (label, anchor, [])
                order.append(label.text)
            }
            buckets[label.text]?.rows.append(item)
        }
        return order.compactMap { key in
            buckets[key].map {
                TaskGroup(label: $0.label, due: $0.due, rows: $0.rows,
                          collapseKey: $0.due.flatMap { DueLabel.monthKey(for: $0, today: today) })
            }
        }
    }

    // MARK: - Collapsible month groups

    func isCollapsed(_ group: TaskGroup) -> Bool {
        group.collapseKey.map(collapsedMonths.contains) ?? false
    }

    /// Folds a month group up / open. Near-term groups have no key and ignore this.
    func toggleCollapsed(_ group: TaskGroup) {
        guard let key = group.collapseKey else { return }
        if collapsedMonths.remove(key) == nil { collapsedMonths.insert(key) }
        persist()
    }

    /// Keys that still name a month with open tasks — the rest is forgotten on save,
    /// so the file doesn't accumulate months that came and went. Checked against all
    /// items, not the filtered list: a filter must not wipe the state of hidden groups.
    private var liveCollapseKeys: Set<String> {
        Set(items.compactMap { anchorDay($0) }.compactMap { DueLabel.monthKey(for: $0, today: today) })
    }

    var editingTask: TodoTask? {
        if case .edit(let id) = route { return items.first { $0.id == id } }
        return nil
    }

    // MARK: - Navigation

    func panelWillOpen() {
        refreshToday()
        clearDrag()
    }

    func openAdd() {
        draft = Draft()
        createsMultiple = false
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
    func goDone() {
        pruneDone()
        route = .done
    }

    /// Esc inside the panel. The form and the done list are pages *on top of* the list,
    /// so Esc leaves the page it is on first; only on the list itself is there nothing
    /// left to leave and the panel closes (PanelWindowController). Returns whether the
    /// key was dealt with here.
    func handleEscape() -> Bool {
        switch route {
        case .add, .edit:
            cancel()
            return true
        case .done:
            goList()
            return true
        case .list:
            return false
        }
    }

    // MARK: - Done retention

    /// Completed tasks are kept this many days, then dropped — the done list is a
    /// recent history, not an archive. The done view says so under its header.
    static let doneRetentionDays = 14

    /// `done` without the tasks completed `doneRetentionDays` or more days before
    /// `today`. Tasks without a completion date (legacy files) are kept.
    static func prunedDone(_ done: [DoneTask], today: Day) -> [DoneTask] {
        done.filter { task in
            guard let completedAt = task.completedAt else { return true }
            return today.days(since: completedAt) < doneRetentionDays
        }
    }

    /// Applied on load and whenever the done view opens, so a long-running app
    /// prunes too. Saves only if something went.
    private func pruneDone() {
        let pruned = TaskStore.prunedDone(done, today: .today)
        guard pruned.count != done.count else { return }
        done = pruned
        persist()
    }

    /// Test hook: `done` is read-only outside the store.
    func replaceDoneForTesting(_ tasks: [DoneTask]) { done = tasks }

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
        if createsMultiple {
            // Only the text clears: a batch is usually several things for the same day,
            // so re-picking the date every time would be the tedious part.
            draft = Draft(title: "", details: "", due: draft.due, due2: draft.due2)
        } else {
            draft = Draft()
            route = .list
        }
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

    /// Fired the moment a task is ticked off, so the scene can cheer. Restoring one
    /// from the done list is not a check-off and does not fire it.
    var onTaskCompleted: (() -> Void)?

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
        // Inside the double-click guard, and deliberately not behind the sound setting:
        // that switch is about sound, not about whether the scene reacts.
        onTaskCompleted?()
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

    /// Completes every task whose check-off animation is still playing. Called on
    /// quit: the user already saw the checkmark and heard the chime, so the
    /// completion must not be lost with the pending timers.
    func flushPendingCompletions() {
        for id in completingIDs { complete(id) }
        completingIDs.removeAll()
        fadingIDs.removeAll()
        collapsingIDs.removeAll()
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

        // Landing next to a task of another day re-dates the moved task to that day
        // (the neighbor's *anchor*: next to a running range that is today, not the
        // range's start; nil in "Kein Datum"). Same day → the dates stay, so a running
        // range stays a range.
        var moved = dragged
        let target = anchorDay(anchor)
        if anchorDay(moved) != target {
            moved.due = target
            moved.due2 = nil
        }
        var rest = items.filter { $0.id != dragID }
        guard let anchorIndex = rest.firstIndex(where: { $0.id == anchor.id }) else { return }
        rest.insert(moved, at: insertBefore ? anchorIndex : anchorIndex + 1)
        items = rest
        persist()
    }

    // MARK: - Draft helpers

    /// Calendar tap: first tap sets the start, a later tap after it sets the end.
    func selectCalendarDay(_ day: Day) {
        // Nothing can fall due before today. The cell is disabled too; this is the
        // guard behind it, so the rule holds however the day arrives.
        guard day >= today else { return }
        if let start = draft.due, draft.due2 == nil, day > start {
            draft.due2 = day
        } else {
            draft.due = day
            draft.due2 = nil
        }
    }

    func clearRange() { draft.due2 = nil }

    /// "Kein Datum" in the calendar popup: the task gets no due date at all.
    func clearDue() {
        draft.due = nil
        draft.due2 = nil
        draft.calendarOpen = false
    }
    /// Quick-pick: one exact day, replacing any range, and the calendar has had its say.
    func setDue(_ day: Day) {
        draft.due = day
        draft.due2 = nil
        draft.calendarOpen = false
    }

    func toggleCalendar() { draft.calendarOpen.toggle() }

    /// Collapses the calendar; called for any click outside it (panel background,
    /// focusing a text field). A no-op while closed so it doesn't churn the form.
    func closeCalendar() {
        if draft.calendarOpen { draft.calendarOpen = false }
    }

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
        case "range":
            // A running range, a range ahead, and an undated task — every due-line shape.
            items.insert(TodoTask(title: "Messe-Vorbereitung", due: Day.today.adding(-1), due2: Day.today.adding(4)), at: 0)
            items.append(TodoTask(title: "Urlaub", details: "Bergwandern", due: Day.today.adding(8), due2: Day.today.adding(14)))
            items.append(TodoTask(title: "Ideen für Q4 sammeln"))
        case "long":
            // Enough rows to hit the list cap and scroll (for the resize grip).
            for i in 1...20 {
                items.append(TodoTask(title: "Aufgabe \(i)", due: Day.today.adding(i % 5)))
            }
        case "long-title":
            items.removeAll()
            items.append(TodoTask(title: "Steuerunterlagen für das vergangene Geschäftsjahr zusammenstellen und beim Finanzamt einreichen, inklusive aller Belege",
                                  details: "Erst die Belege sortieren, dann das Formular ausfüllen, danach alles zusammen einreichen und die Bestätigung ablegen.",
                                  due: Day.today))
        case "undated":
            items.append(TodoTask(title: "Ideen für Q4 sammeln"))
            items.append(TodoTask(title: "Keller aufräumen", details: "Irgendwann im Herbst"))
            items.removeAll { $0.due != nil } // leaves just the "Kein Datum" group
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
        collapsedMonths.formIntersection(liveCollapseKeys)
        persistence?.save(Snapshot(items: items, done: done, collapsedMonths: collapsedMonths))
    }

    static func seed() -> Snapshot {
        let t = Day.today
        return Snapshot(
            items: [
                TodoTask(title: "Steuerunterlagen einreichen", due: t.adding(-1), createdAt: t.adding(-4)),
                TodoTask(title: "Design-Review vorbereiten", details: "Feedback aus Figma einarbeiten", due: t, createdAt: t.adding(-2)),
                TodoTask(title: "Zahnarzttermin bestätigen", due: t.adding(1), createdAt: t.adding(-1)),
                TodoTask(title: "Wochenbericht schreiben", details: "Zahlen aus dem Dashboard exportieren", due: t.adding(2), createdAt: t),
                TodoTask(title: "Geschenk für Lena besorgen", due: t.adding(6), createdAt: t),
                TodoTask(title: "Versicherung kündigen", due: t.adding(9), createdAt: t),
                TodoTask(title: "Reisepass verlängern", details: "Termin beim Bürgeramt buchen", due: t.adding(12), createdAt: t)
            ],
            done: [
                DoneTask(id: UUID(), title: "Miete überweisen", createdAt: t.adding(-6), completedAt: t.adding(-1)),
                DoneTask(id: UUID(), title: "Flug einchecken", createdAt: t.adding(-3), completedAt: t)
            ]
        )
    }
}
