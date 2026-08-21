import SwiftUI

/// Scrollable 5-month calendar with single-day or range selection.
struct CalendarView: View {
    @Environment(TaskStore.self) private var store

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(German.calendarHeader, id: \.self) { w in
                    Text(w)
                        .font(.system(size: 10, weight: .bold))
                        .kerning(0.4)
                        .foregroundStyle(Theme.muted2)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(EdgeInsets(top: 11, leading: 10, bottom: 5, trailing: 10))

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(months, id: \.first) { month in
                            VStack(alignment: .leading, spacing: 0) {
                                Text(German.monthsLong[month.first.month - 1].uppercased() + " \(month.first.year)")
                                    .font(.system(size: 10.5, weight: .bold))
                                    .kerning(0.7)
                                    .foregroundStyle(Theme.ink2)
                                    .padding(EdgeInsets(top: 2, leading: 2, bottom: 6, trailing: 2))
                                LazyVGrid(columns: columns, spacing: 2) {
                                    ForEach(0..<month.leadingBlanks, id: \.self) { _ in
                                        Color.clear.frame(width: 28, height: 28)
                                    }
                                    ForEach(month.days, id: \.self) { day in
                                        DayCell(day: day)
                                    }
                                }
                            }
                            .padding(.top, 6)
                            .padding(.bottom, 2)
                        }
                    }
                }
                .scrollIndicators(.never)
                .frame(maxHeight: Theme.calendarMaxHeight)
                // Land on the selection's month, not blindly on the current one.
                .onAppear { proxy.scrollTo((store.draft.due ?? .today).firstOfMonth(offset: 0), anchor: .top) }
            }
            .padding(EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10))

            HStack(spacing: 8) {
                Text(rangeHint)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted2)
                Spacer(minLength: 0)
                if store.draft.due != nil {
                    LinkButton(title: "Kein Datum", kind: .muted) { store.clearDue() }
                }
                if store.draft.due2 != nil {
                    IconButton(symbol: "↺", help: "Zurücksetzen",
                               tint: Theme.blue, hoverTint: Theme.blue,
                               hoverBackground: Theme.blue.opacity(0.12)) {
                        store.clearRange()
                    }
                }
            }
            .padding(EdgeInsets(top: 6, leading: 12, bottom: 11, trailing: 12))
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
        // Taps on the card's own chrome (weekday row, month label, gaps between days)
        // must not fall through to the panel background, which would collapse the
        // calendar. Day cells and buttons sit in front and still win.
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onTapGesture {}
        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
    }

    private var rangeHint: String {
        guard let start = store.draft.due else { return "Kein Fälligkeitsdatum" }
        if let end = store.draft.due2 {
            return German.rangeSummary(start, end, today: store.today)
        }
        return "Enddatum wählen"
    }

    private struct Month {
        let first: Day
        let leadingBlanks: Int
        let days: [Day]
    }

    /// Months shown, Monday-first: normally the current month plus the next four,
    /// widened so the current selection is always present — editing an overdue
    /// task must show (and let the user re-pick) its actual due date, and a range
    /// ending beyond the default window must stay reachable.
    private var months: [Month] {
        let selection = store.draft.due ?? .today
        let start = min(selection, .today).firstOfMonth(offset: 0)
        let end = max(Day.today.firstOfMonth(offset: 4),
                      (store.draft.due2 ?? selection).firstOfMonth(offset: 0))
        let span = Day.calendar.dateComponents([.month], from: start.date, to: end.date).month ?? 4
        return (0...max(span, 0)).map { offset in
            let first = start.firstOfMonth(offset: offset)
            let lead = (first.weekday + 5) % 7 // Foundation Sunday=1 → Monday-first index
            let days = (0..<first.daysInMonth).map { first.adding($0) }
            return Month(first: first, leadingBlanks: lead, days: days)
        }
    }
}

private struct DayCell: View {
    @Environment(TaskStore.self) private var store
    let day: Day

    var body: some View {
        let draft = store.draft
        let selected = day == draft.due || day == draft.due2
        let inRange: Bool = {
            guard let start = draft.due, let end = draft.due2 else { return false }
            return day > start && day < end
        }()
        let isToday = day == .today
        let isPast = day < .today

        Button { store.selectCalendarDay(day) } label: {
            Text("\(day.dayOfMonth)")
                .font(.system(size: 12.5, weight: selected ? .bold : .medium))
                .foregroundStyle(selected ? .white : inRange ? Theme.blue : isPast ? Theme.line : Theme.ink)
                .frame(width: 28, height: 28)
                .background(selected ? Theme.blue : inRange ? Theme.blue.opacity(0.13) : .clear, in: Circle())
                .overlay(Circle().strokeBorder(isToday && !selected ? Theme.line : .clear, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .accessibilityLabel(German.long(day))
    }
}
