import ArgumentParser
import EventKit
import Foundation

struct CalendarEvents: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "events",
        abstract: "List events within a time range."
    )

    @Option(help: "Start datetime (ISO-8601).")
    var start: String

    @Option(help: "End datetime (ISO-8601).")
    var end: String

    @Option(help: "Filter by calendar identifier (repeatable).")
    var calendarId: [String] = []

    @Option(help: "Filter by source identifier (repeatable).")
    var sourceId: [String] = []

    @Flag(help: "Include optional fields like location/notes/url.")
    var includeDetails: Bool = false

    @Option(help: "Limit number of events returned.")
    var limit: Int?

    func run() throws {
        let startDate = try parseISO8601Date(start)
        let endDate = try parseISO8601Date(end)
        guard startDate < endDate else {
            throw SimpleSidecarError(code: "INVALID_ARGUMENTS", message: "--start must be before --end.")
        }

        let store = try makeEventStoreRequiringFullAccess()
        let calendarIdFilter = Set(calendarId)
        let sourceIdFilter = Set(sourceId)

        var calendars = store.calendars(for: .event).filter { !isCalendarHidden($0) }
        if !sourceIdFilter.isEmpty {
            calendars = calendars.filter { sourceIdFilter.contains($0.source.sourceIdentifier) }
        }
        if !calendarIdFilter.isEmpty {
            calendars = calendars.filter { calendarIdFilter.contains($0.calendarIdentifier) }
        }

        if calendars.isEmpty {
            try writeResponseAndExitIfNeeded([
                "ok": true,
                "result": ["events": []]
            ])
            return
        }

        let predicate = store.predicateForEvents(withStart: startDate, end: endDate, calendars: calendars)
        var events = store.events(matching: predicate)
        events.sort { $0.startDate < $1.startDate }

        if let limit, limit > 0, events.count > limit {
            events = Array(events.prefix(limit))
        }

        let items: [[String: Any]] = events.map { ev in
            serializeEvent(ev, includeDetails: includeDetails)
        }

        try writeResponseAndExitIfNeeded([
            "ok": true,
            "result": ["events": items]
        ])
    }
}
