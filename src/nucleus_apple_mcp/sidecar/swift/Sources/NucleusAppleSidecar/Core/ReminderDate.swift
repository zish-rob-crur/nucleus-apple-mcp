import Foundation

func parseReminderDateComponents(_ value: String) throws -> DateComponents {
    if isYYYYMMDD(value) {
        return try parseYYYYMMDDComponents(value)
    }

    let date = try parseISO8601Date(value)
    var comps = Calendar.current.dateComponents(in: TimeZone.current, from: date)
    comps.timeZone = TimeZone.current
    return comps
}

func parseReminderFilterBoundaryDate(_ value: String, isEnd: Bool) throws -> Date {
    if isYYYYMMDD(value) {
        let comps = try parseYYYYMMDDComponents(value)
        guard let date = Calendar.current.date(from: comps) else {
            throw SimpleSidecarError(code: "INVALID_ARGUMENTS", message: "Invalid date: \(value)")
        }
        if isEnd {
            guard let next = Calendar.current.date(byAdding: .day, value: 1, to: date) else {
                throw SimpleSidecarError(code: "INTERNAL", message: "Failed to compute end boundary for: \(value)")
            }
            return next
        }
        return date
    }

    return try parseISO8601Date(value)
}

func reminderComponentsToDate(_ comps: DateComponents?) -> Date? {
    guard var comps else { return nil }
    if comps.timeZone == nil {
        comps.timeZone = TimeZone.current
    }
    return Calendar.current.date(from: comps)
}

func formatReminderDateValue(_ comps: DateComponents?) -> Any {
    guard let comps else { return NSNull() }
    guard let year = comps.year, let month = comps.month, let day = comps.day else { return NSNull() }

    let hasTime = comps.hour != nil || comps.minute != nil || comps.second != nil
    if !hasTime {
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    guard let date = reminderComponentsToDate(comps) else { return NSNull() }
    return formatISO8601Date(date)
}

private func isYYYYMMDD(_ value: String) -> Bool {
    let bytes = Array(value.utf8)
    guard bytes.count == 10 else { return false }

    func isDigit(_ b: UInt8) -> Bool { b >= 48 && b <= 57 }
    for i in [0, 1, 2, 3, 5, 6, 8, 9] {
        if !isDigit(bytes[i]) { return false }
    }
    return bytes[4] == 45 && bytes[7] == 45
}

private func parseYYYYMMDDComponents(_ value: String) throws -> DateComponents {
    let parts = value.split(separator: "-")
    guard parts.count == 3,
          let year = Int(parts[0]),
          let month = Int(parts[1]),
          let day = Int(parts[2])
    else {
        throw SimpleSidecarError(code: "INVALID_ARGUMENTS", message: "Invalid date: \(value)")
    }

    var comps = DateComponents()
    comps.year = year
    comps.month = month
    comps.day = day
    comps.timeZone = TimeZone.current

    guard Calendar.current.date(from: comps) != nil else {
        throw SimpleSidecarError(code: "INVALID_ARGUMENTS", message: "Invalid date: \(value)")
    }
    return comps
}
