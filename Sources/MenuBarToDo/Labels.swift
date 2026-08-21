import Foundation

/// German date labels, ported 1:1 from the design's `fmt` / `rangeText`.
enum German {
    /// Indexed by Foundation weekday (1 = Sunday).
    static let weekdaysShort = ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"]
    static let weekdaysLong = ["Sonntag", "Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag"]
    static let monthsShort = ["Jan", "Feb", "März", "Apr", "Mai", "Juni", "Juli", "Aug", "Sept", "Okt", "Nov", "Dez"]
    static let monthsLong = ["Januar", "Februar", "März", "April", "Mai", "Juni",
                             "Juli", "August", "September", "Oktober", "November", "Dezember"]
    /// Calendar header, Monday first.
    static let calendarHeader = ["MO", "DI", "MI", "DO", "FR", "SA", "SO"]

    static func weekday(_ d: Day) -> String { weekdaysShort[d.weekday - 1] }
    static func weekdayLong(_ d: Day) -> String { weekdaysLong[d.weekday - 1] }
    static func monthShort(_ d: Day) -> String { monthsShort[d.month - 1] }

    /// "20. Aug"; the year is appended once it differs from the current one
    /// ("20. Aug 2027").
    static func absolute(_ d: Day, today: Day = .today) -> String {
        let base = "\(d.dayOfMonth). \(monthShort(d))"
        return d.year == today.year ? base : "\(base) \(d.year)"
    }

    /// "Heute" / "Morgen" / "27. Aug" for a single day, "3. – 9. Sept" or
    /// "28. Aug – 3. Sept" for a range.
    static func rangeText(_ a: Day, _ b: Day?) -> String {
        guard let b, b != a else {
            switch a.days(since: .today) {
            case 0: return "Heute"
            case 1: return "Morgen"
            default: return absolute(a)
            }
        }
        let sameMonth = a.month == b.month && a.year == b.year
        let start = sameMonth ? "\(a.dayOfMonth)." : absolute(a)
        return "\(start) – \(absolute(b))"
    }

    /// Calendar hint once a range is picked: "7 Tage · bis So, 9. Sept" — the chip
    /// already shows both dates, so this adds the length and the end's weekday instead.
    static func rangeSummary(_ a: Day, _ b: Day, today: Day = .today) -> String {
        let days = b.days(since: a) + 1 // inclusive: 3.–9. is seven days
        return "\(days) Tage · \(rangeEnd(b, today: today))"
    }

    /// "bis So, 9. Sept"
    static func rangeEnd(_ end: Day, today: Day = .today) -> String {
        "bis \(weekday(end)), \(absolute(end, today: today))"
    }

    /// Concrete dates for a row's due line: "Do, 21. Aug", "Mo, 24. – So, 30. Aug",
    /// "Fr, 28. Aug – Do, 3. Sept", or "Kein Fälligkeitsdatum". (`DueLabel.row` wraps
    /// this with the relative words — Heute, Morgen, Freitag — for near single days.)
    static func dueDates(_ due: Day?, _ due2: Day?, today: Day = .today) -> String {
        guard let due else { return "Kein Fälligkeitsdatum" }
        let start = "\(weekday(due)), \(due.dayOfMonth)."
        guard let end = due2, end != due else { return "\(weekday(due)), \(absolute(due, today: today))" }
        let sameMonth = due.month == end.month && due.year == end.year
        let from = sameMonth ? start : "\(weekday(due)), \(absolute(due, today: today))"
        return "\(from) – \(weekday(end)), \(absolute(end, today: today))"
    }

    /// Group header for a day beyond the coming week: "Später im August" for the rest
    /// of the current month, then "September", and "Januar 2027" once the year differs
    /// (so August of next year never merges with this August's group).
    static func monthGroup(_ d: Day, today: Day = .today) -> String {
        let month = monthsLong[d.month - 1]
        if d.year != today.year { return "\(month) \(d.year)" }
        return d.month == today.month ? "Später im \(month)" : month
    }

    /// "Mi, 20. Aug 2026"
    static func long(_ d: Day) -> String {
        "\(weekday(d)), \(d.dayOfMonth). \(monthShort(d)) \(d.year)"
    }

    /// "Erledigt am 20. Aug"
    static func completed(_ d: Day, today: Day = .today) -> String {
        "Erledigt am " + absolute(d, today: today)
    }
}

/// Tone of a due-date label; views map this to colors.
enum DueTone {
    case overdue, today, neutral
}

struct DueLabel: Equatable {
    let text: String
    let tone: DueTone

    /// Group header for tasks without a due date; they list last.
    static let undated = DueLabel(text: "Kein Datum", tone: .neutral)

    /// Mirrors the design: overdue → "Überfällig" (red), today → "Heute" (blue),
    /// tomorrow → "Morgen", within a week → weekday ("Fr."). Anything further out is
    /// bucketed by month ("Später im August", "September", "Januar 2027") — one group
    /// per date would bury a long horizon under headers that just repeat the row's
    /// due line. In absolute mode the week reads "20. Aug", only the colors remain;
    /// the month buckets are the same.
    static func make(for day: Day, style: DateFormatStyle, today: Day = .today) -> DueLabel {
        let dd = day.days(since: today)
        let abs = style == .absolute
        let absText = German.absolute(day, today: today)
        if dd < 0 { return DueLabel(text: abs ? absText : "Überfällig", tone: .overdue) }
        if dd == 0 { return DueLabel(text: abs ? absText : "Heute", tone: .today) }
        if monthKey(for: day, today: today) != nil {
            return DueLabel(text: German.monthGroup(day, today: today), tone: .neutral)
        }
        if abs { return DueLabel(text: absText, tone: .neutral) }
        if dd == 1 { return DueLabel(text: "Morgen", tone: .neutral) }
        return DueLabel(text: German.weekday(day) + ".", tone: .neutral)
    }

    /// Days this far out (and further) are grouped by month instead of by day.
    static let monthHorizon = 7

    /// "2026-09" when `day` falls into a month bucket, nil while it still gets its
    /// own near-term group. This is the identity a collapsed group is remembered by.
    static func monthKey(for day: Day, today: Day = .today) -> String? {
        guard day.days(since: today) >= monthHorizon else { return nil }
        return String(format: "%04d-%02d", day.year, day.month)
    }

    /// The due line under a list row, Todoist-style: "Gestern" / "Heute" / "Morgen", the
    /// full weekday ("Freitag") for the six days after tomorrow, otherwise the date
    /// ("Do, 21. Aug"). Ranges always show their dates; no date → "Kein Fälligkeitsdatum".
    /// The tone matches the group headers: overdue red, today blue, else neutral.
    static func row(for due: Day?, _ due2: Day?, style: DateFormatStyle, today: Day = .today) -> DueLabel {
        guard let due else { return DueLabel(text: German.dueDates(nil, nil, today: today), tone: .neutral) }
        let dates = German.dueDates(due, due2, today: today)
        if let end = due2, end != due {
            let tone: DueTone = end < today ? .overdue : (due <= today ? .today : .neutral)
            return DueLabel(text: dates, tone: tone)
        }
        let dd = due.days(since: today)
        let tone: DueTone = dd < 0 ? .overdue : dd == 0 ? .today : .neutral
        guard style == .relative else { return DueLabel(text: dates, tone: tone) }
        switch dd {
        case -1: return DueLabel(text: "Gestern", tone: tone)
        case 0: return DueLabel(text: "Heute", tone: tone)
        case 1: return DueLabel(text: "Morgen", tone: tone)
        case 2...6: return DueLabel(text: German.weekdayLong(due), tone: tone)
        default: return DueLabel(text: dates, tone: tone)
        }
    }
}
