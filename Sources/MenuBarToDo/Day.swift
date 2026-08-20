import Foundation

/// A calendar day in the user's current calendar/time zone, normalized to
/// the start of the day. Encoded as "yyyy-MM-dd" so the JSON stays readable.
struct Day: Hashable, Comparable, Codable {
    let date: Date

    init(_ date: Date) {
        self.date = Calendar.current.startOfDay(for: date)
    }

    static var today: Day { Day(Date()) }

    static func < (lhs: Day, rhs: Day) -> Bool { lhs.date < rhs.date }

    func adding(_ days: Int) -> Day {
        Day(Calendar.current.date(byAdding: .day, value: days, to: date) ?? date)
    }

    /// Signed number of days from `other` to `self`.
    func days(since other: Day) -> Int {
        Calendar.current.dateComponents([.day], from: other.date, to: date).day ?? 0
    }

    var dayOfMonth: Int { Calendar.current.component(.day, from: date) }
    /// 1-based month.
    var month: Int { Calendar.current.component(.month, from: date) }
    var year: Int { Calendar.current.component(.year, from: date) }
    /// 1 = Sunday … 7 = Saturday (Foundation convention).
    var weekday: Int { Calendar.current.component(.weekday, from: date) }

    /// First day of the month that is `offset` months after this day's month.
    func firstOfMonth(offset: Int) -> Day {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month], from: date)
        comps.day = 1
        let first = cal.date(from: comps) ?? date
        return Day(cal.date(byAdding: .month, value: offset, to: first) ?? first)
    }

    var daysInMonth: Int {
        Calendar.current.range(of: .day, in: .month, for: date)?.count ?? 30
    }

    // MARK: Codable

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    var isoString: String { Day.formatter.string(from: date) }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let parsed = Day.formatter.date(from: raw) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "Invalid day string: \(raw)"))
        }
        self.init(parsed)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(isoString)
    }
}
