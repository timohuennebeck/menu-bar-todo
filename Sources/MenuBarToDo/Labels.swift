import Foundation

/// German date labels, ported 1:1 from the design's `fmt` / `rangeText`.
enum German {
    /// Indexed by Foundation weekday (1 = Sunday).
    static let weekdaysShort = ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"]
    static let monthsShort = ["Jan", "Feb", "März", "Apr", "Mai", "Juni", "Juli", "Aug", "Sept", "Okt", "Nov", "Dez"]
    static let monthsLong = ["Januar", "Februar", "März", "April", "Mai", "Juni",
                             "Juli", "August", "September", "Oktober", "November", "Dezember"]
    /// Calendar header, Monday first.
    static let calendarHeader = ["MO", "DI", "MI", "DO", "FR", "SA", "SO"]

    static func weekday(_ d: Day) -> String { weekdaysShort[d.weekday - 1] }
    static func monthShort(_ d: Day) -> String { monthsShort[d.month - 1] }

    /// "20. Aug"; the year is appended once it differs from the current one
    /// ("20. Aug 2027"). Besides being clearer, this keeps two days a year apart
    /// from sharing a due label — the label text is the list's grouping key, and
    /// a merged group would silently re-date tasks dragged inside it.
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

    /// "Mi, 20. Aug 2026"
    static func long(_ d: Day) -> String {
        "\(weekday(d)), \(d.dayOfMonth). \(monthShort(d)) \(d.year)"
    }

    /// "Erstellt am 20. Aug" — the year is added once it differs from the current one.
    static func created(_ d: Day, today: Day = .today) -> String {
        "Erstellt am " + absolute(d, today: today)
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

    /// Mirrors the design: overdue → "Überfällig" (red), today → "Heute" (blue),
    /// tomorrow → "Morgen", within a week → weekday ("Fr."), else absolute date.
    /// In absolute mode everything is "20. Aug", only the colors remain.
    static func make(for day: Day, style: DateFormatStyle) -> DueLabel {
        let dd = day.days(since: .today)
        let abs = style == .absolute
        let absText = German.absolute(day)
        if dd < 0 { return DueLabel(text: abs ? absText : "Überfällig", tone: .overdue) }
        if dd == 0 { return DueLabel(text: abs ? absText : "Heute", tone: .today) }
        if dd == 1, !abs { return DueLabel(text: "Morgen", tone: .neutral) }
        if dd < 7, !abs { return DueLabel(text: German.weekday(day) + ".", tone: .neutral) }
        return DueLabel(text: absText, tone: .neutral)
    }
}
