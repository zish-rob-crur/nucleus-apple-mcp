import EventKit
import Foundation

func availabilityString(_ availability: EKEventAvailability) -> String {
    switch availability {
    case .busy:
        return "busy"
    case .free:
        return "free"
    case .tentative:
        return "tentative"
    case .unavailable:
        return "unavailable"
    case .notSupported:
        return "unknown"
    @unknown default:
        return "unknown"
    }
}

func parseAvailability(_ value: String) throws -> EKEventAvailability {
    switch value {
    case "busy":
        return .busy
    case "free":
        return .free
    case "tentative":
        return .tentative
    case "unavailable":
        return .unavailable
    default:
        throw SimpleSidecarError(code: "INVALID_ARGUMENTS", message: "Invalid availability: \(value)")
    }
}

func serializeEvent(_ ev: EKEvent, includeDetails: Bool) -> [String: Any] {
    var obj: [String: Any] = [
        "event_id": ev.eventIdentifier ?? ev.calendarItemIdentifier,
        "calendar_id": ev.calendar.calendarIdentifier,
        "title": ev.title ?? "",
        "start": formatISO8601Date(ev.startDate),
        "end": formatISO8601Date(ev.endDate),
        "is_all_day": ev.isAllDay
    ]

    if includeDetails {
        obj["location"] = ev.location as Any? ?? NSNull()
        obj["notes"] = ev.notes as Any? ?? NSNull()
        obj["url"] = ev.url?.absoluteString as Any? ?? NSNull()
        obj["availability"] = availabilityString(ev.availability)
    }

    return obj
}
