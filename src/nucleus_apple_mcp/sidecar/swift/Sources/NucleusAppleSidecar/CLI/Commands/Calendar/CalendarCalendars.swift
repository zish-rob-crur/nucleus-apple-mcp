import ArgumentParser
import EventKit
import Foundation

struct CalendarCalendars: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "calendars",
        abstract: "List event calendars."
    )

    @Option(help: "Filter by source identifier (repeatable).")
    var sourceId: [String] = []

    @Flag(help: "Include hidden calendars.")
    var includeHidden: Bool = false

    func run() throws {
        let store = try makeEventStoreRequiringFullAccess()
        let sourceFilter = Set(sourceId)

        var calendars = store.calendars(for: .event)
        if !sourceFilter.isEmpty {
            calendars = calendars.filter { sourceFilter.contains($0.source.sourceIdentifier) }
        }
        if !includeHidden {
            calendars = calendars.filter { !isCalendarHidden($0) }
        }

        let items: [[String: Any]] = calendars
            .sorted { lhs, rhs in
                let l = lhs.title
                let r = rhs.title
                return l.localizedCaseInsensitiveCompare(r) == .orderedAscending
            }
            .map { cal in
                [
                    "calendar_id": cal.calendarIdentifier,
                    "source_id": cal.source.sourceIdentifier,
                    "title": cal.title,
                    "type": calendarTypeString(cal.type),
                    "color": hexColor(from: cal.cgColor),
                    "is_writable": cal.allowsContentModifications,
                    "is_hidden": isCalendarHidden(cal)
                ]
            }

        try writeResponseAndExitIfNeeded([
            "ok": true,
            "result": ["calendars": items]
        ])
    }

    private func calendarTypeString(_ type: EKCalendarType) -> String {
        switch type {
        case .local:
            return "local"
        case .calDAV:
            return "caldav"
        case .exchange:
            return "exchange"
        case .subscription:
            return "subscription"
        case .birthday:
            return "birthday"
        @unknown default:
            return "unknown"
        }
    }
}
