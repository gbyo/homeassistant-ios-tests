import Foundation

/// Reads the timestamps Home Assistant writes into `media_position_updated_at`.
///
/// Core writes a timezone-aware `datetime` with `isoformat()`, such as `2026-09-06T12:00:00+00:00`
/// (a template's `str()` puts a space where the `T` goes). This accepts exactly that family:
///
///     YYYY-MM-DD ("T" | " ") hh:mm:ss [ "." 1–9 digits ] ( "Z" | ("+" | "-") hh:mm )
///
/// and nothing looser: no missing offset, no out-of-range fields.
///
/// Parsed by hand because Foundation does not give that strictness. `Date.ISO8601FormatStyle` accepts
/// trailing whitespace, unpadded fields and `+0000`-style offsets, and rolls out-of-range fields into a
/// different instant (`2026-02-29` becomes March 1st); `ISO8601DateFormatter` loses sub-millisecond
/// precision. This parser is stateless, so any number of callers can use it at once, and it keeps the
/// RemoteMedia extension lightweight.
enum RemoteMediaTimestamp {
    /// Seconds since 1970-01-01 UTC, or `nil` unless `text` matches the grammar above exactly.
    static func unixSeconds(from text: String) -> TimeInterval? {
        var cursor = Cursor(bytes: Array(text.utf8))
        guard let year = cursor.digits(4), cursor.skip("-"),
              let month = cursor.digits(2), cursor.skip("-"),
              let day = cursor.digits(2), cursor.skip("T") || cursor.skip(" "),
              let hour = cursor.digits(2), cursor.skip(":"),
              let minute = cursor.digits(2), cursor.skip(":"),
              let second = cursor.digits(2) else { return nil }

        var fraction: TimeInterval = 0
        if cursor.skip(".") {
            guard let digits = cursor.fraction() else { return nil }
            fraction = TimeInterval(digits.value) / pow(10, TimeInterval(digits.count))
        }

        let offset: Int
        if cursor.skip("Z") {
            offset = 0
        } else {
            let sign: Int
            if cursor.skip("+") {
                sign = 1
            } else if cursor.skip("-") {
                sign = -1
            } else {
                return nil
            }
            guard let offsetHour = cursor.digits(2), cursor.skip(":"),
                  let offsetMinute = cursor.digits(2),
                  offsetHour < 24, offsetMinute < 60 else { return nil }
            offset = sign * (offsetHour * 3600 + offsetMinute * 60)
        }

        guard cursor.isAtEnd,
              year >= 1, (1 ... 12).contains(month), (1 ... daysIn(month: month, year: year)).contains(day),
              hour < 24, minute < 60, second < 60 else { return nil }

        // Exact integer seconds first; the fraction is added last, so a present-day timestamp keeps
        // the microsecond precision `isoformat()` writes (a `Double` near 1.8e9 resolves ~0.24µs).
        let days = daysSinceUnixEpoch(year: year, month: month, day: day)
        return TimeInterval(days * 86400 + hour * 3600 + minute * 60 + second - offset) + fraction
    }

    private static func daysIn(month: Int, year: Int) -> Int {
        switch month {
        case 2: return year.isMultiple(of: 4) && (!year.isMultiple(of: 100) || year.isMultiple(of: 400)) ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    /// The proleptic Gregorian day number of a civil date, counted from 1970-01-01. Howard Hinnant's
    /// `days_from_civil`: https://howardhinnant.github.io/date_algorithms.html#days_from_civil
    private static func daysSinceUnixEpoch(year: Int, month: Int, day: Int) -> Int {
        let year = month <= 2 ? year - 1 : year
        let era = (year >= 0 ? year : year - 399) / 400
        let yearOfEra = year - era * 400
        let dayOfYear = (153 * ((month + 9) % 12) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    private struct Cursor {
        let bytes: [UInt8]
        var index = 0

        var isAtEnd: Bool { index == bytes.count }

        mutating func skip(_ character: Unicode.Scalar) -> Bool {
            guard index < bytes.count, bytes[index] == UInt8(ascii: character) else { return false }
            index += 1
            return true
        }

        /// Exactly `count` ASCII digits.
        mutating func digits(_ count: Int) -> Int? {
            guard index + count <= bytes.count else { return nil }
            var value = 0
            for byte in bytes[index ..< index + count] {
                guard let digit = Self.digit(byte) else { return nil }
                value = value * 10 + digit
            }
            index += count
            return value
        }

        /// One to nine ASCII digits, and how many there were.
        mutating func fraction() -> (value: Int, count: Int)? {
            var value = 0
            var count = 0
            while index < bytes.count, let digit = Self.digit(bytes[index]) {
                guard count < 9 else { return nil }
                value = value * 10 + digit
                count += 1
                index += 1
            }
            return count == 0 ? nil : (value, count)
        }

        private static func digit(_ byte: UInt8) -> Int? {
            (UInt8(ascii: "0") ... UInt8(ascii: "9")).contains(byte) ? Int(byte - UInt8(ascii: "0")) : nil
        }
    }
}
