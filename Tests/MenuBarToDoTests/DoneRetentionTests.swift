import XCTest
@testable import MenuBarToDo

final class DoneRetentionTests: XCTestCase {
    private func done(_ title: String, daysAgo: Int?) -> DoneTask {
        DoneTask(id: UUID(), title: title, completedAt: daysAgo.map { Day.today.adding(-$0) })
    }

    func testKeepsRecentAndDropsOldDoneTasks() {
        let today = Day.today
        let kept = TaskStore.prunedDone([done("today", daysAgo: 0),
                                         done("13 days", daysAgo: 13),
                                         done("14 days", daysAgo: 14),
                                         done("30 days", daysAgo: 30)], today: today)
        XCTAssertEqual(kept.map(\.title), ["today", "13 days"])
    }

    /// Legacy files have done tasks without a completion date; never throw those away.
    func testKeepsDoneTasksWithoutACompletionDate() {
        let kept = TaskStore.prunedDone([done("legacy", daysAgo: nil)], today: .today)
        XCTAssertEqual(kept.map(\.title), ["legacy"])
    }

    func testRetentionIsFourteenDays() {
        XCTAssertEqual(TaskStore.doneRetentionDays, 14)
    }

    func testLoadingPrunesAndSaves() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("retention-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("tasks.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let persistence = Persistence(url: url)
        persistence.save(Snapshot(items: [], done: [done("old", daysAgo: 20), done("new", daysAgo: 2)]))

        let store = TaskStore(persistence: persistence)
        XCTAssertEqual(store.done.map(\.title), ["new"])
        guard case .loaded(let saved) = persistence.load() else { return XCTFail("nothing saved") }
        XCTAssertEqual(saved.done.map(\.title), ["new"], "the pruned list is written back")
    }

    /// A Mac that never restarts still prunes: opening the done view does it too.
    func testOpeningTheDoneViewPrunes() {
        let store = TaskStore(persistence: nil)
        store.replaceDoneForTesting([done("old", daysAgo: 15), done("new", daysAgo: 1)])
        store.goDone()
        XCTAssertEqual(store.done.map(\.title), ["new"])
    }
}
