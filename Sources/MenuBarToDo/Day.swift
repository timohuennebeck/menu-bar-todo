import Foundation

/// A calendar day in the user's current time zone, normalized to the start of
/// the day. Encoded as "yyyy-MM-dd" so the JSON stays readable.
///
/// All calendar math uses a fixed *Gregorian* calendar: the stored strings, the
/// German month/weekday tables (12 entries) and the calendar grid must always
/// agree, regardless of the calendar selected in System Settings. (With e.g. the
/// Hebrew calendar, `Calendar.current` yields `month == 13` in leap years, which
/// would index past the label tables.) The time zone is re-read on every access
/// so a zone change mid-session is picked up immediately.
struct Day: Hashable, Comparable, Codable {
    let date: Date

    /// Gregorian, in the live current time zone.
    static var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        return cal
    }

    init(_ date: Date) {
        self.date = Day.calendar.startOfDay(for: date)
    }

    static var today: Day { Day(Date()) }

    static func < (lhs: Day, rhs: Day) -> Bool { lhs.date < rhs.date }

    func adding(_ days: Int) -> Day {
        Day(Day.calendar.date(byAdding: .day, value: days, to: date) ?? date)
    }

    /// Signed number of days from `other` to `self`.
    func days(since other: Day) -> Int {
        Day.calendar.dateComponents([.day], from: other.date, to: date).day ?? 0
    }

    var dayOfMonth: Int { Day.calendar.component(.day, from: date) }
    /// 1-based month.
    var month: Int { Day.calendar.component(.month, from: date) }
    var year: Int { Day.calendar.component(.year, from: date) }
    /// 1 = Sunday … 7 = Saturday (Foundation convention).
    var weekday: Int { Day.calendar.component(.weekday, from: date) }

    /// First day of the month that is `offset` months after this day's month.
    func firstOfMonth(offset: Int) -> Day {
        let cal = Day.calendar
        var comps = cal.dateComponents([.year, .month], from: date)
        comps.day = 1
        let first = cal.date(from: comps) ?? date
        return Day(cal.date(byAdding: .month, value: offset, to: first) ?? first)
    }

    var daysInMonth: Int {
        Day.calendar.range(of: .day, in: .month, for: date)?.count ?? 30
    }

    // MARK: Codable

    /// Formatted from Gregorian components in the *live* time zone. (A cached
    /// DateFormatter would freeze the zone at first use, so a day created after
    /// a zone change could encode as the previous/next nominal day.)
    var isoString: String {
        String(format: "%04d-%02d-%02d", year, month, dayOfMonth)
    }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        let invalid = DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                        debugDescription: "Invalid day string: \(raw)"))
        let parts = raw.split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { throw invalid }
        let comps = DateComponents(year: y, month: m, day: d)
        guard comps.isValidDate(in: Day.calendar),
              let parsed = Day.calendar.date(from: comps) else { throw invalid }
        self.init(parsed)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(isoString)
    }
}
