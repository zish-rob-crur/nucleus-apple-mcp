import ArgumentParser
import EventKit
import Foundation

struct CalendarSources: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sources",
        abstract: "List calendar sources (accounts/providers)."
    )

    @Flag(help: "Include sources with zero visible calendars.")
    var includeEmpty: Bool = false

    func run() throws {
        let store = try makeEventStoreRequiringFullAccess()

        let visibleCalendars = store.calendars(for: .event).filter { !isCalendarHidden($0) }
        var calendarsBySourceId: [String: [EKCalendar]] = [:]
        for cal in visibleCalendars {
            calendarsBySourceId[cal.source.sourceIdentifier, default: []].append(cal)
        }

        var sources: [[String: Any]] = []
        for source in store.sources {
            let calendars = calendarsBySourceId[source.sourceIdentifier] ?? []
            let calendarCount = calendars.count
            if !includeEmpty, calendarCount == 0 {
                continue
            }

            let writableCount = calendars.filter { $0.allowsContentModifications }.count
            sources.append([
                "source_id": source.sourceIdentifier,
                "title": source.title,
                "type": sourceTypeString(source.sourceType),
                "calendar_count": calendarCount,
                "writable_calendar_count": writableCount
            ])
        }

        sources.sort {
            let lt = ($0["title"] as? String) ?? ""
            let rt = ($1["title"] as? String) ?? ""
            return lt.localizedCaseInsensitiveCompare(rt) == .orderedAscending
        }

        try writeResponseAndExitIfNeeded([
            "ok": true,
            "result": ["sources": sources]
        ])
    }

    private func sourceTypeString(_ type: EKSourceType) -> String {
        switch type {
        case .local:
            return "local"
        case .calDAV:
            return "caldav"
        case .exchange:
            return "exchange"
        case .mobileMe:
            return "caldav"
        case .subscribed:
            return "subscribed"
        case .birthdays:
            return "birthdays"
        @unknown default:
            return "unknown"
        }
    }
}
