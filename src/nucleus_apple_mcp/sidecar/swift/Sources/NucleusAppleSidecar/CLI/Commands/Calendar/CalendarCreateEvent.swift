import ArgumentParser
import EventKit
import Foundation

struct CalendarCreateEvent: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "create-event",
        abstract: "Create a calendar event."
    )

    @Option(help: "Calendar identifier.")
    var calendarId: String

    @Option(help: "Event title.")
    var title: String

    @Option(help: "Start datetime (ISO-8601).")
    var start: String

    @Option(help: "End datetime (ISO-8601).")
    var end: String

    @Flag(help: "Create as an all-day event.")
    var allDay: Bool = false

    @Option(help: "Event location.")
    var location: String?

    @Option(help: "Event notes.")
    var notes: String?

    @Option(help: "Event url.")
    var url: String?

    enum Availability: String, ExpressibleByArgument {
        case busy
        case free
        case tentative
        case unavailable
    }

    @Option(help: "Event availability.")
    var availability: Availability?

    func run() throws {
        let startDate = try parseISO8601Date(start)
        let endDate = try parseISO8601Date(end)
        guard startDate < endDate else {
            throw SimpleSidecarError(code: "INVALID_ARGUMENTS", message: "--start must be before --end.")
        }

        let store = try makeEventStoreRequiringFullAccess()

        guard let calendar = store.calendar(withIdentifier: calendarId) else {
            throw SimpleSidecarError(code: "NOT_FOUND", message: "Calendar not found: \(calendarId)")
        }
        guard calendar.allowsContentModifications else {
            throw SimpleSidecarError(code: "NOT_WRITABLE", message: "Calendar is not writable: \(calendarId)")
        }

        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = title
        event.startDate = startDate
        event.endDate = endDate
        event.isAllDay = allDay

        if let location {
            event.location = location
        }
        if let notes {
            event.notes = notes
        }
        if let url {
            guard let parsed = URL(string: url) else {
                throw SimpleSidecarError(code: "INVALID_ARGUMENTS", message: "Invalid URL: \(url)")
            }
            event.url = parsed
        }
        if let availability {
            event.availability = try parseAvailability(availability.rawValue)
        }

        do {
            try store.save(event, span: .thisEvent, commit: true)
        } catch {
            throw SimpleSidecarError(code: "INTERNAL", message: error.localizedDescription)
        }

        try writeResponseAndExitIfNeeded([
            "ok": true,
            "result": ["event": serializeEvent(event, includeDetails: true)]
        ])
    }
}
