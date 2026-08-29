import Foundation

struct TodoTask: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var details: String
    /// nil = no due date ("Kein Fälligkeitsdatum"); such tasks list last.
    var due: Day?
    /// Optional end of a date range ("Zeitraum"); only meaningful with a `due`.
    var due2: Day?
    /// Shown as "Erstellt am …" when the task has no description.
    var createdAt: Day

    init(id: UUID = UUID(), title: String, details: String = "", due: Day? = nil, due2: Day? = nil, createdAt: Day = .today) {
        self.id = id
        self.title = title
        self.details = details
        self.due = due
        self.due2 = due2
        self.createdAt = createdAt
    }

    // Files written before `createdAt` existed still load: missing → today.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        details = try c.decodeIfPresent(String.self, forKey: .details) ?? ""
        // decodeIfPresent: the synthesized encoder drops the key entirely for an
        // undated task, and a plain decode would throw — one "Kein Datum" task made
        // the whole file unreadable on the next launch.
        due = try c.decodeIfPresent(Day.self, forKey: .due)
        due2 = try c.decodeIfPresent(Day.self, forKey: .due2)
        createdAt = try c.decodeIfPresent(Day.self, forKey: .createdAt) ?? .today
    }
}

struct DoneTask: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    /// Kept so restoring a task brings its description back (nil for legacy files).
    var details: String? = nil
    /// Kept so restoring a task brings its original creation date back.
    var createdAt: Day?
    /// Shown as "Erledigt am …" in the done list (nil only for legacy files).
    var completedAt: Day?
}

/// What gets written to disk.
struct Snapshot: Codable {
    var items: [TodoTask]
    var done: [DoneTask]
    /// Month groups the user folded up, as `TaskGroup.collapseKey`s.
    var collapsedMonths: Set<String> = []

    init(items: [TodoTask], done: [DoneTask], collapsedMonths: Set<String> = []) {
        self.items = items
        self.done = done
        self.collapsedMonths = collapsedMonths
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decode([TodoTask].self, forKey: .items)
        done = try c.decode([DoneTask].self, forKey: .done)
        collapsedMonths = try c.decodeIfPresent(Set<String>.self, forKey: .collapsedMonths) ?? []
    }
}

/// JSON file persistence in ~/Library/Application Support/MenuBarToDo/tasks.json.
struct Persistence {
    /// Outcome of `load()`: a missing file (genuine first launch) must be treated
    /// differently from an existing file that can't be read — seeding over the
    /// latter would destroy the user's (possibly recoverable) data.
    enum LoadResult {
        case loaded(Snapshot)
        case missing
        /// File exists but couldn't be read/decoded; it was moved aside first.
        case failed
    }

    let url: URL

    static var `default`: Persistence {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("MenuBarToDo", isDirectory: true)
        return Persistence(url: dir.appendingPathComponent("tasks.json"))
    }

    func load() -> LoadResult {
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        do {
            let data = try Data(contentsOf: url)
            return .loaded(try JSONDecoder().decode(Snapshot.self, from: data))
        } catch {
            NSLog("MenuBarToDo: could not load \(url.path): \(error)")
            backUpUnreadableFile()
            return .failed
        }
    }

    /// Moves the unreadable file aside so no later save can overwrite it.
    private func backUpUnreadableFile() {
        let backup = url.deletingPathExtension()
            .appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970)).json")
        do {
            try FileManager.default.moveItem(at: url, to: backup)
            NSLog("MenuBarToDo: moved unreadable file to \(backup.path)")
        } catch {
            NSLog("MenuBarToDo: could not back up unreadable file: \(error)")
        }
    }

    func save(_ snapshot: Snapshot) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(snapshot).write(to: url, options: .atomic)
        } catch {
            NSLog("MenuBarToDo: could not save \(url.path): \(error)")
        }
    }
}

// MARK: - Design-time props from the .dc.html, kept as runtime settings.

enum DateFormatStyle: String {
    case relative = "Relativ"
    case absolute = "Absolut"
}

enum DropZoneStyle: String {
    case insertionLine = "Einfügelinie"
    case dashedFrame = "Gestrichelter Rahmen"
    case header = "Kopfzeile"
    case emptySlot = "Leerer Slot"
}

/// List filter chosen from the filter menu above the list.
enum TaskFilter: String, CaseIterable, Identifiable {
    case none = "Kein Filter"
    case overdue = "Überfällig"
    case today = "Heute"
    case dated = "Datum vorhanden"

    var id: String { rawValue }
    var isActive: Bool { self != .none }

    /// Range tasks (due…due2) count as "Heute" while today lies inside the range
    /// and only become overdue once the whole range is in the past.
    func matches(_ task: TodoTask, today: Day = .today) -> Bool {
        guard let start = task.due else { return self == .none }
        let end = task.due2 ?? start
        switch self {
        case .none, .dated: return true
        case .overdue: return end < today
        case .today: return start <= today && today <= end
        }
    }
}

struct Settings {
    var dateFormat: DateFormatStyle = .relative
    var showDescriptions = true
    var dropZoneStyle: DropZoneStyle = .insertionLine
    /// Play the chime when a task is checked off.
    var completionSound = true
}
