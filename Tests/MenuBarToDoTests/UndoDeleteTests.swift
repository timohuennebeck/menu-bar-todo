import XCTest
@testable import MenuBarToDo

final class UndoDeleteTests: XCTestCase {
    private func makeStore() -> TaskStore { TaskStore(persistence: nil) }

    func testDeleteOffersAnUndoAndRestoresInPlace() {
        let store = makeStore()
        let before = store.items.map(\.id)
        let victim = store.sortedItems[1]
        let index = store.items.firstIndex { $0.id == victim.id }!

        store.openEdit(victim)
        store.deleteEditingTask()
        XCTAssertFalse(store.items.contains { $0.id == victim.id })
        XCTAssertEqual(store.undoableDeleteTitle, victim.title, "the footer names what went")

        store.undoDelete()
        XCTAssertEqual(store.items.map(\.id), before, "restored at its old position")
        XCTAssertNil(store.undoableDeleteTitle, "the offer is spent")
    }

    /// Undo is for the last delete only — any other change drops the offer, so a stale
    /// "Rückgängig" can never reappear a task minutes later.
    func testTheOfferIsDroppedByTheNextChange() {
        let store = makeStore()
        store.openEdit(store.sortedItems[0])
        store.deleteEditingTask()
        XCTAssertNotNil(store.undoableDeleteTitle)

        store.openAdd()
        store.draft.title = "Neu"
        store.submitDraft()
        XCTAssertNil(store.undoableDeleteTitle)
    }

    func testUndoWithoutADeleteDoesNothing() {
        let store = makeStore()
        let before = store.items.map(\.id)
        store.undoDelete()
        XCTAssertEqual(store.items.map(\.id), before)
    }
}
