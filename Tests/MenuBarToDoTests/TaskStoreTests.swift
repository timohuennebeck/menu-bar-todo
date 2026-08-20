import XCTest
@testable import MenuBarToDo

final class LabelTests: XCTestCase {
    func testRelativeLabels() {
        let t = Day.today
        XCTAssertEqual(DueLabel.make(for: t.adding(-1), style: .relative), DueLabel(text: "Überfällig", tone: .overdue))
        XCTAssertEqual(DueLabel.make(for: t, style: .relative), DueLabel(text: "Heute", tone: .today))
        XCTAssertEqual(DueLabel.make(for: t.adding(1), style: .relative), DueLabel(text: "Morgen", tone: .neutral))
        let in3 = t.adding(3)
        XCTAssertEqual(DueLabel.make(for: in3, style: .relative).text, German.weekday(in3) + ".")
        let in10 = t.adding(10)
        XCTAssertEqual(DueLabel.make(for: in10, style: .relative).text, German.absolute(in10))
    }

    func testAbsoluteLabelsKeepTone() {
        let t = Day.today
        let overdue = DueLabel.make(for: t.adding(-2), style: .absolute)
        XCTAssertEqual(overdue.text, German.absolute(t.adding(-2)))
        XCTAssertEqual(overdue.tone, .overdue)
        XCTAssertEqual(DueLabel.make(for: t.adding(1), style: .absolute).text, German.absolute(t.adding(1)))
    }

    func testRangeText() {
        let t = Day.today
        XCTAssertEqual(German.rangeText(t, nil), "Heute")
        XCTAssertEqual(German.rangeText(t.adding(1), nil), "Morgen")
        XCTAssertEqual(German.rangeText(t, t), "Heute")
        // Same month → "3. – 9. Sept"; different month → "28. Aug – 3. Sept".
        let a = Day(date(2026, 9, 3)), b = Day(date(2026, 9, 9)), c = Day(date(2026, 8, 28))
        XCTAssertEqual(German.rangeText(a, b), "3. – 9. Sept")
        XCTAssertEqual(German.rangeText(c, a), "28. Aug – 3. Sept")
    }

    func testDayRoundTripsThroughJSON() throws {
        let day = Day(date(2026, 12, 31))
        let data = try JSONEncoder().encode(day)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "\"2026-12-31\"")
        XCTAssertEqual(try JSONDecoder().decode(Day.self, from: data), day)
    }

    func testCreatedLabel() {
        let t = Day(date(2026, 8, 20))
        XCTAssertEqual(German.created(Day(date(2026, 8, 18)), today: t), "Erstellt am 18. Aug")
        XCTAssertEqual(German.created(Day(date(2025, 12, 30)), today: t), "Erstellt am 30. Dez 2025")
        XCTAssertEqual(German.completed(Day(date(2026, 8, 20)), today: t), "Erledigt am 20. Aug")
    }

    func testLegacyJSONWithoutCreatedAtStillLoads() throws {
        let json = """
        {"items":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","title":"Alt","details":"","due":"2026-08-01","due2":null}],
         "done":[{"id":"7F9619FF-8B86-D011-B42D-00C04FC964FF","title":"Fertig"}]}
        """
        let snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(json.utf8))
        XCTAssertEqual(snapshot.items.first?.createdAt, .today)
        XCTAssertNil(snapshot.done.first?.createdAt)
        XCTAssertNil(snapshot.done.first?.completedAt)
    }

    func testMondayFirstLeadingBlanks() {
        // 1 Aug 2026 is a Saturday → 5 blanks in a Monday-first grid.
        let first = Day(date(2026, 8, 1))
        XCTAssertEqual((first.weekday + 5) % 7, 5)
        XCTAssertEqual(first.daysInMonth, 31)
    }
}

final class TaskStoreTests: XCTestCase {
    private func makeStore() -> TaskStore { TaskStore(persistence: nil) }

    func testSeedIsGroupedAndSortedByDue() {
        let store = makeStore()
        let labels = store.groups.map(\.label.text)
        XCTAssertEqual(labels.first, "Überfällig")
        XCTAssertEqual(labels[1], "Heute")
        XCTAssertEqual(labels[2], "Morgen")
        XCTAssertEqual(store.sortedItems.map(\.due), store.sortedItems.map(\.due).sorted())
    }

    func testAddRequiresTitleAndReturnsToList() {
        let store = makeStore()
        let before = store.items.count
        store.openAdd()
        store.draft.title = "   "
        store.addTask()
        XCTAssertEqual(store.items.count, before)
        XCTAssertEqual(store.route, .add)

        store.draft.title = "  Neuer Task "
        store.draft.details = " Details "
        store.draft.due = Day.today.adding(2)
        store.addTask()
        XCTAssertEqual(store.items.count, before + 1)
        XCTAssertEqual(store.items.last?.title, "Neuer Task")
        XCTAssertEqual(store.items.last?.details, "Details")
        XCTAssertEqual(store.items.last?.due, Day.today.adding(2))
        XCTAssertEqual(store.route, .list)
        XCTAssertEqual(store.draft.title, "")
    }

    func testEditSaveAndDelete() {
        let store = makeStore()
        let task = store.sortedItems[0]
        store.openEdit(task)
        XCTAssertEqual(store.draft.title, task.title)
        store.draft.title = "Umbenannt"
        store.draft.due2 = Day.today.adding(5)
        store.saveTask()
        let saved = store.items.first { $0.id == task.id }
        XCTAssertEqual(saved?.title, "Umbenannt")
        XCTAssertEqual(saved?.due2, Day.today.adding(5))

        store.openEdit(saved!)
        store.deleteEditingTask()
        XCTAssertNil(store.items.first { $0.id == task.id })
        XCTAssertEqual(store.route, .list)
    }

    func testCompleteAndRestore() {
        let store = makeStore()
        let task = store.sortedItems[1] // "Design-Review vorbereiten" — has a description
        XCTAssertFalse(task.details.isEmpty, "test needs a task with a description")
        let doneBefore = store.done.count
        store.complete(task.id)
        XCTAssertNil(store.items.first { $0.id == task.id })
        XCTAssertEqual(store.done.first?.id, task.id, "completed task goes to the top of Erledigt")
        XCTAssertEqual(store.done.first?.completedAt, .today)
        XCTAssertEqual(store.done.count, doneBefore + 1)

        store.restore(task.id)
        XCTAssertEqual(store.done.count, doneBefore)
        let restored = store.items.first { $0.id == task.id }
        XCTAssertEqual(restored?.due, .today, "restored tasks are due today")
        XCTAssertEqual(restored?.details, task.details, "description survives complete → restore")
        XCTAssertEqual(restored?.createdAt, task.createdAt, "creation date survives complete → restore")
    }

    /// Visible order of titles per group, i.e. what the user sees.
    private func visible(_ store: TaskStore) -> [[String]] {
        store.groups.map { $0.rows.map(\.title) }
    }

    func testBeginCompleteDelaysRemovalAndIgnoresDoubleClicks() {
        let store = makeStore()
        let task = store.sortedItems[0]
        let before = store.items.count
        store.beginComplete(task.id, delay: 0.05, sound: false)
        store.beginComplete(task.id, delay: 0.05, sound: false) // second click: no-op
        XCTAssertTrue(store.isCompleting(task.id))
        XCTAssertFalse(store.isCollapsing(task.id))
        XCTAssertEqual(store.items.count, before, "row stays while the animation plays")

        let fading = expectation(description: "row fading")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            XCTAssertTrue(store.isFading(task.id))
            XCTAssertFalse(store.isCollapsing(task.id))
            fading.fulfill()
        }
        let collapsing = expectation(description: "row collapsing")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05 + TaskStore.fadeDuration + 0.1) {
            XCTAssertTrue(store.isCollapsing(task.id))
            XCTAssertEqual(store.items.count, before, "still in the list while it shrinks")
            collapsing.fulfill()
        }
        let removed = expectation(description: "task moved to Erledigt")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05 + TaskStore.fadeDuration + TaskStore.collapseDuration + 0.3) {
            XCTAssertFalse(store.isCompleting(task.id))
            XCTAssertFalse(store.isFading(task.id))
            XCTAssertFalse(store.isCollapsing(task.id))
            XCTAssertEqual(store.items.count, before - 1)
            XCTAssertEqual(store.done.filter { $0.id == task.id }.count, 1, "completed exactly once")
            removed.fulfill()
        }
        wait(for: [fading, collapsing, removed], timeout: 3)
    }

    func testMoveToEndOfGroupLandsAfterLastRowAndRedates() {
        let store = makeStore()
        let dragged = store.sortedItems[0]            // Steuerunterlagen (overdue)
        let target = store.groups[1]                  // Heute: [Design-Review]
        store.beginDrag(dragged.id)
        store.move(dragged.id, to: DropSlot(groupID: target.id, index: target.rows.count))
        XCTAssertEqual(store.groups[0].label.text, "Heute", "no overdue group left")
        XCTAssertEqual(visible(store)[0], ["Design-Review vorbereiten", "Steuerunterlagen einreichen"])
        XCTAssertEqual(store.items.first { $0.id == dragged.id }?.due, target.due)
        XCTAssertNil(store.dragID)
    }

    func testMoveToStartOfGroupLandsBeforeFirstRowAndClearsRange() {
        let store = makeStore()
        let dragged = store.sortedItems[0]
        store.openEdit(dragged)
        store.draft.due2 = Day.today.adding(3)
        store.saveTask()
        let target = store.groups[1]
        store.move(dragged.id, to: DropSlot(groupID: target.id, index: 0))
        XCTAssertEqual(visible(store)[0], ["Steuerunterlagen einreichen", "Design-Review vorbereiten"])
        XCTAssertNil(store.items.first { $0.id == dragged.id }?.due2, "changing the day drops the range")
    }

    func testReorderWithinGroupFollowsSlotIndices() {
        let store = makeStore()
        let heute = store.groups[1]
        // Build a 3-row "Heute" group: Design, Steuer, Zahnarzt.
        store.move(store.sortedItems[0].id, to: DropSlot(groupID: heute.id, index: 1))
        store.move(store.groups[1].rows[0].id, to: DropSlot(groupID: heute.id, index: 2))
        XCTAssertEqual(visible(store)[0], ["Design-Review vorbereiten", "Steuerunterlagen einreichen", "Zahnarzttermin bestätigen"])

        let zahnarzt = store.groups[0].rows[2]
        // Slot 0 = before the first row.
        store.move(zahnarzt.id, to: DropSlot(groupID: heute.id, index: 0))
        XCTAssertEqual(visible(store)[0], ["Zahnarzttermin bestätigen", "Design-Review vorbereiten", "Steuerunterlagen einreichen"])
        // Slot 3 = after the last row (indices count the dragged row itself).
        store.move(zahnarzt.id, to: DropSlot(groupID: heute.id, index: 3))
        XCTAssertEqual(visible(store)[0], ["Design-Review vorbereiten", "Steuerunterlagen einreichen", "Zahnarzttermin bestätigen"])
        // Slot 1 for the last row = between the first two.
        store.move(zahnarzt.id, to: DropSlot(groupID: heute.id, index: 1))
        XCTAssertEqual(visible(store)[0], ["Design-Review vorbereiten", "Zahnarzttermin bestätigen", "Steuerunterlagen einreichen"])
    }

    func testDropInsideMultiDayGroupLandsWhereTheLineWas() {
        let store = makeStore()
        store.openAdd()
        store.draft.title = "Ganz alt"
        store.draft.due = Day.today.adding(-5)
        store.addTask()
        // Überfällig now shows [Ganz alt (-5), Steuerunterlagen (-1)].
        XCTAssertEqual(visible(store)[0], ["Ganz alt", "Steuerunterlagen einreichen"])
        let overdue = store.groups[0]
        let design = store.groups[1].rows[0]

        // Dropping at the end of Überfällig must land after Steuerunterlagen, not in the middle.
        store.move(design.id, to: DropSlot(groupID: overdue.id, index: overdue.rows.count))
        XCTAssertEqual(visible(store)[0], ["Ganz alt", "Steuerunterlagen einreichen", "Design-Review vorbereiten"])
        XCTAssertEqual(store.items.first { $0.id == design.id }?.due, Day.today.adding(-1))

        // Dropping at the very top must land before Ganz alt and take its date.
        store.move(design.id, to: DropSlot(groupID: overdue.id, index: 0))
        XCTAssertEqual(visible(store)[0], ["Design-Review vorbereiten", "Ganz alt", "Steuerunterlagen einreichen"])
        XCTAssertEqual(store.items.first { $0.id == design.id }?.due, Day.today.adding(-5))
    }

    func testDroppingOnAdjacentSlotIsANoOp() {
        let store = makeStore()
        let heute = store.groups[1]
        store.move(store.sortedItems[0].id, to: DropSlot(groupID: heute.id, index: 1))
        let before = store.items
        let second = store.groups[0].rows[1]
        store.move(second.id, to: DropSlot(groupID: heute.id, index: 1)) // directly above itself
        XCTAssertEqual(store.items, before)
        store.move(second.id, to: DropSlot(groupID: heute.id, index: 2)) // directly below itself
        XCTAssertEqual(store.items, before)
    }

    func testHoverOwnershipLetsRowsWinOverGroups() {
        let store = makeStore()
        let heute = store.groups[1]
        store.beginDrag(store.sortedItems[0].id)
        store.setHover(owner: "row:a", slot: DropSlot(groupID: heute.id, index: 0))
        store.setHover(owner: "group:x", slot: DropSlot(groupID: heute.id, index: 1), onlyIfFree: true)
        XCTAssertEqual(store.dropHover?.owner, "row:a", "group must not override a hovered row")
        store.clearHover(owner: "group:x")
        XCTAssertNotNil(store.dropHover, "a view only clears its own hover")
        store.clearHover(owner: "row:a")
        XCTAssertNil(store.dropHover)
        store.setHover(owner: "group:x", slot: DropSlot(groupID: heute.id, index: 1), onlyIfFree: true)
        XCTAssertEqual(store.dropHover?.owner, "group:x")
    }

    func testCalendarSelectionBuildsRanges() {
        let store = makeStore()
        store.openAdd() // due = today, no range
        // As in the design ("Enddatum wählen"): a later day with no range yet becomes the end date.
        let end = Day.today.adding(2)
        store.selectCalendarDay(end)
        XCTAssertEqual(store.draft.due, .today)
        XCTAssertEqual(store.draft.due2, end)
        // Once a range exists, any tap restarts as a single day.
        store.selectCalendarDay(end.adding(4))
        XCTAssertEqual(store.draft.due, end.adding(4))
        XCTAssertNil(store.draft.due2)
        // A day before the current due is always a single-day selection.
        store.selectCalendarDay(Day.today)
        XCTAssertEqual(store.draft.due, .today)
        XCTAssertNil(store.draft.due2)
    }

    func testFilterNarrowsGroups() {
        let store = makeStore()
        XCTAssertEqual(store.filteredItems.count, store.items.count)

        store.filter = .today
        XCTAssertEqual(visible(store), [["Design-Review vorbereiten"]])

        store.filter = .overdue
        XCTAssertEqual(visible(store), [["Steuerunterlagen einreichen"]])

        store.filter = .none
        XCTAssertEqual(store.filteredItems.count, 5)
        XCTAssertEqual(TaskFilter.allCases.map(\.rawValue), ["Kein Filter", "Überfällig", "Heute"])
    }

    func testRangeTasksMatchDaysInsideTheirRange() {
        let t = Day.today
        let range = TodoTask(title: "Messe", due: t.adding(-1), due2: t.adding(1))
        XCTAssertFalse(TaskFilter.overdue.matches(range, today: t), "a running range isn't overdue")
        XCTAssertTrue(TaskFilter.today.matches(range, today: t))

        let past = TodoTask(title: "Vorbei", due: t.adding(-3), due2: t.adding(-2))
        XCTAssertTrue(TaskFilter.overdue.matches(past, today: t))
        XCTAssertFalse(TaskFilter.today.matches(past, today: t))

        let future = TodoTask(title: "Später", due: t.adding(2))
        XCTAssertFalse(TaskFilter.overdue.matches(future, today: t))
        XCTAssertFalse(TaskFilter.today.matches(future, today: t))
        XCTAssertTrue(TaskFilter.none.matches(future, today: t))
    }

    func testDragIndicatorsFollowTheSlot() {
        let store = makeStore()
        let dragged = store.sortedItems[0]            // alone in Überfällig
        let overdue = store.groups[0]
        let heute = store.groups[1]
        store.beginDrag(dragged.id)

        store.setHover(owner: "g", slot: DropSlot(groupID: heute.id, index: heute.rows.count))
        XCTAssertTrue(store.isGroupActive(heute))
        XCTAssertTrue(store.showsGroupIndicator(heute))
        XCTAssertFalse(store.showsRowLine(at: 0, in: heute))

        store.setHover(owner: "r", slot: DropSlot(groupID: heute.id, index: 0))
        XCTAssertFalse(store.showsGroupIndicator(heute))
        XCTAssertTrue(store.showsRowLine(at: 0, in: heute))

        // Slots touching the dragged row itself preview nothing.
        store.setHover(owner: "r", slot: DropSlot(groupID: overdue.id, index: 0))
        XCTAssertNil(store.activeSlot)
        store.setHover(owner: "r", slot: DropSlot(groupID: overdue.id, index: 1))
        XCTAssertNil(store.activeSlot)
        XCTAssertTrue(store.isGroupActive(overdue), "group-level styles still highlight the hovered group")

        store.clearDrag()
        XCTAssertNil(store.activeSlot)
    }
}

private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
    Calendar.current.date(from: DateComponents(year: y, month: m, day: d))!
}
