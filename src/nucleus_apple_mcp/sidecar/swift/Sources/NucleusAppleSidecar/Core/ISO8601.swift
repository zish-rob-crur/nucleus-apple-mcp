import Foundation

private let _iso8601WithFractional: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    f.timeZone = .current
    return f
}()

private let _iso8601: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    f.timeZone = .current
    return f
}()

func parseISO8601Date(_ value: String) throws -> Date {
    if let date = _iso8601WithFractional.date(from: value) ?? _iso8601.date(from: value) {
        return date
    }
    throw SimpleSidecarError(code: "INVALID_ARGUMENTS", message: "Invalid ISO-8601 datetime: \(value)")
}

func formatISO8601Date(_ date: Date) -> String {
    _iso8601.string(from: date)
}

