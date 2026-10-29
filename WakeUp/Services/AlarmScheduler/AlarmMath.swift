import Foundation

/// Pure date logic for the primary alarm, kept separate so it can be unit tested.
enum AlarmMath {
    /// The next time the alarm should ring strictly after `date`.
    /// A missing local time on a daylight-saving jump moves to the next valid time,
    /// and a repeated hour uses its first occurrence.
    static func nextFire(hour: Int, minute: Int, days: Set<Weekday>, after date: Date, calendar: Calendar = .current) -> Date? {
        guard let next = rawNextFire(hour: hour, minute: minute, days: days, after: date, calendar: calendar) else { return nil }
        // When clocks fall back, the same wall-clock time happens twice. If `date` was the first one,
        // skip the repeat so the alarm doesn't ring again an hour later.
        let wall: (Date) -> DateComponents = { calendar.dateComponents([.year, .month, .day, .hour, .minute], from: $0) }
        if next.timeIntervalSince(date) <= 2 * 3600, wall(next) == wall(date) {
            return rawNextFire(hour: hour, minute: minute, days: days, after: next, calendar: calendar)
        }
        return next
    }

    private static func rawNextFire(hour: Int, minute: Int, days: Set<Weekday>, after date: Date, calendar: Calendar) -> Date? {
        var base = DateComponents()
        base.hour = hour
        base.minute = minute
        base.second = 0
        if days.isEmpty {
            return calendar.nextDate(after: date, matching: base, matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward)
        }
        return days.compactMap { day -> Date? in
            var c = base
            c.weekday = day.rawValue
            return calendar.nextDate(after: date, matching: c, matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward)
        }.min()
    }

    static func nextFire(_ config: AlarmConfig, after date: Date = Date(), calendar: Calendar = .current) -> Date? {
        nextFire(hour: config.hour, minute: config.minute, days: config.repeatDays, after: date, calendar: calendar)
    }

    /// The next `count` occurrences. A one-time alarm has at most one.
    static func upcoming(_ count: Int, _ config: AlarmConfig, after date: Date = Date(), calendar: Calendar = .current) -> [Date] {
        var result: [Date] = []
        var cursor = date
        while result.count < count, let next = nextFire(config, after: cursor, calendar: calendar) {
            result.append(next)
            if config.repeatDays.isEmpty { break }
            cursor = next
        }
        return result
    }

    /// "8 h 5 min", rounded up to the next whole minute.
    static func countdown(from now: Date, to target: Date) -> String {
        let minutes = max(0, Int((target.timeIntervalSince(now) / 60).rounded(.up)))
        let days = minutes / 1440
        let hours = (minutes % 1440) / 60
        let mins = minutes % 60
        if days > 0 { return "\(days) d \(hours) h" }
        if hours > 0 { return "\(hours) h \(mins) min" }
        return "\(mins) min"
    }
}

enum TimeText {
    static func uses24Hour(_ format: TimeFormat, locale: Locale = .current) -> Bool {
        switch format {
        case .twelve: false
        case .twentyFour: true
        case .system: !(DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale) ?? "").contains("a")
        }
    }

    static func parts(hour: Int, minute: Int, format: TimeFormat) -> (time: String, period: String?) {
        if uses24Hour(format) { return (String(format: "%02d:%02d", hour, minute), nil) }
        let h = hour % 12 == 0 ? 12 : hour % 12
        let calendar = Calendar.current
        return (String(format: "%d:%02d", h, minute), hour < 12 ? calendar.amSymbol : calendar.pmSymbol)
    }

    static func string(hour: Int, minute: Int, format: TimeFormat) -> String {
        let p = parts(hour: hour, minute: minute, format: format)
        return p.period.map { "\(p.time) \($0)" } ?? p.time
    }

    static func string(_ date: Date, format: TimeFormat) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return string(hour: c.hour ?? 0, minute: c.minute ?? 0, format: format)
    }

    static func dayAndTime(_ date: Date, format: TimeFormat, now: Date = Date()) -> String {
        let calendar = Calendar.current
        let day: String
        if calendar.isDate(date, inSameDayAs: now) {
            day = "Today"
        } else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            day = "Tomorrow"
        } else {
            day = date.formatted(.dateTime.weekday(.wide))
        }
        return "\(day), \(string(date, format: format))"
    }
}

enum Greeting {
    static func text(name: String, enabled: Bool, date: Date = Date()) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        let base = hour < 5 ? "Good night" : hour < 12 ? "Good morning" : hour < 17 ? "Good afternoon" : "Good evening"
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return enabled && !trimmed.isEmpty ? "\(base), \(trimmed)." : "\(base)."
    }

    static let messages = [
        "Water first, phone later.",
        "Open a window and take one slow breath.",
        "You don't have to feel ready to begin.",
        "Small start, good day.",
        "Stand up, stretch, then decide.",
        "Daylight helps. Find some.",
        "Be kind to yourself this morning.",
    ]

    static func message(for date: Date = Date()) -> String {
        let day = Calendar.current.ordinality(of: .day, in: .year, for: date) ?? 0
        return messages[day % messages.count]
    }
}
