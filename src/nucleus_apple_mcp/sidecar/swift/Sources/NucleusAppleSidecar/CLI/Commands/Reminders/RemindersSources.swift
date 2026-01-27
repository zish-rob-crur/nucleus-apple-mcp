import ArgumentParser
import EventKit
import Foundation

struct RemindersSources: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sources",
        abstract: "List reminder sources (accounts/providers)."
    )

    @Flag(help: "Include sources with zero visible lists.")
    var includeEmpty: Bool = false

    func run() throws {
        let store = try makeEventStoreRequiringRemindersAccess()

        let visibleLists = store.calendars(for: .reminder).filter { !isCalendarHidden($0) }
        var listsBySourceId: [String: [EKCalendar]] = [:]
        for list in visibleLists {
            listsBySourceId[list.source.sourceIdentifier, default: []].append(list)
        }

        var sources: [[String: Any]] = []
        for source in store.sources {
            let lists = listsBySourceId[source.sourceIdentifier] ?? []
            let listCount = lists.count
            if !includeEmpty, listCount == 0 {
                continue
            }

            let writableCount = lists.filter { $0.allowsContentModifications }.count
            sources.append([
                "source_id": source.sourceIdentifier,
                "title": source.title,
                "type": sourceTypeString(source.sourceType),
                "list_count": listCount,
                "writable_list_count": writableCount
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
