import ArgumentParser
import EventKit
import Foundation

struct CalendarUpdateEvent: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "update-event",
        abstract: "Update an existing calendar event."
    )

    enum Span: String, ExpressibleByArgument {
        case this
        case future

        var ekSpan: EKSpan {
            switch self {
            case .this:
                return .thisEvent
            case .future:
                return .futureEvents
            }
        }
    }

    enum Availability: String, ExpressibleByArgument {
        case busy
        case free
        case tentative
        case unavailable
    }

    @Option(help: "Event identifier.")
    var eventId: String

    @Option(help: "Apply changes to this or future events (recurrence).")
    var span: Span = .this

    @Option(help: "Move the event to another calendar (calendar must be writable).")
    var calendarId: String?

    @Option(help: "Event title.")
    var title: String?

    @Option(help: "Start datetime (ISO-8601).")
    var start: String?

    @Option(help: "End datetime (ISO-8601).")
    var end: String?

    @Option(help: "Explicitly set all-day status (true/false).")
    var isAllDay: Bool?

    @Option(help: "Event location.")
    var location: String?

    @Flag(help: "Clear location.")
    var clearLocation: Bool = false

    @Option(help: "Event notes.")
    var notes: String?

    @Flag(help: "Clear notes.")
    var clearNotes: Bool = false

    @Option(help: "Event url.")
    var url: String?

    @Flag(help: "Clear url.")
    var clearUrl: Bool = false

    @Option(help: "Event availability.")
    var availability: Availability?

    @Flag(help: "Clear availability (reset to unknown).")
    var clearAvailability: Bool = false

    func run() throws {
        let hasChanges =
            calendarId != nil
                || title != nil
                || start != nil
                || end != nil
                || isAllDay != nil
                || location != nil
                || clearLocation
                || notes != nil
                || clearNotes
                || url != nil
                || clearUrl
                || availability != nil
                || clearAvailability

        if !hasChanges {
            throw SimpleSidecarError(code: "INVALID_ARGUMENTS", message: "No fields to update.")
        }

        if clearLocation, location != nil {
            throw SimpleSidecarError(code: "INVALID_ARGUMENTS", message: "Cannot use --location with --clear-location.")
        }
        if clearNotes, notes != nil {
            throw SimpleSidecarError(code: "INVALID_ARGUMENTS", message: "Cannot use --notes with --clear-notes.")
        }
        if clearUrl, url != nil {
            throw SimpleSidecarError(code: "INVALID_ARGUMENTS", message: "Cannot use --url with --clear-url.")
        }
        if clearAvailability, availability != nil {
            throw SimpleSidecarError(code: "INVALID_ARGUMENTS", message: "Cannot use --availability with --clear-availability.")
        }

        let store = try makeEventStoreRequiringFullAccess()
        guard let event = store.event(withIdentifier: eventId) else {
            throw SimpleSidecarError(code: "NOT_FOUND", message: "Event not found: \(eventId)")
        }

        guard event.calendar.allowsContentModifications else {
            throw SimpleSidecarError(code: "NOT_WRITABLE", message: "Event calendar is not writable: \(event.calendar.calendarIdentifier)")
        }

        if let calendarId {
            guard let calendar = store.calendar(withIdentifier: calendarId) else {
                throw SimpleSidecarError(code: "NOT_FOUND", message: "Calendar not found: \(calendarId)")
            }
            guard calendar.allowsContentModifications else {
                throw SimpleSidecarError(code: "NOT_WRITABLE", message: "Calendar is not writable: \(calendarId)")
            }
            event.calendar = calendar
        }

        if let title {
            event.title = title
        }
        if let start {
            event.startDate = try parseISO8601Date(start)
        }
        if let end {
            event.endDate = try parseISO8601Date(end)
        }
        if let isAllDay {
            event.isAllDay = isAllDay
        }

        if clearLocation {
            event.location = nil
        } else if let location {
            event.location = location
        }

        if clearNotes {
            event.notes = nil
        } else if let notes {
            event.notes = notes
        }

        if clearUrl {
            event.url = nil
        } else if let url {
            guard let parsed = URL(string: url) else {
                throw SimpleSidecarError(code: "INVALID_ARGUMENTS", message: "Invalid URL: \(url)")
            }
            event.url = parsed
        }

        if clearAvailability {
            event.availability = .notSupported
        } else if let availability {
            event.availability = try parseAvailability(availability.rawValue)
        }

        guard event.startDate < event.endDate else {
            throw SimpleSidecarError(code: "INVALID_ARGUMENTS", message: "--start must be before --end.")
        }

        do {
            try store.save(event, span: span.ekSpan, commit: true)
        } catch {
            throw SimpleSidecarError(code: "INTERNAL", message: error.localizedDescription)
        }

        try writeResponseAndExitIfNeeded([
            "ok": true,
            "result": ["event": serializeEvent(event, includeDetails: true)]
        ])
    }
}
