import ArgumentParser
import EventKit
import Foundation

struct RemindersLists: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "lists",
        abstract: "List reminder lists."
    )

    @Option(help: "Filter by source identifier (repeatable).")
    var sourceId: [String] = []

    @Flag(help: "Include hidden lists.")
    var includeHidden: Bool = false

    func run() throws {
        let store = try makeEventStoreRequiringRemindersAccess()
        let sourceFilter = Set(sourceId)

        var lists = store.calendars(for: .reminder)
        if !sourceFilter.isEmpty {
            lists = lists.filter { sourceFilter.contains($0.source.sourceIdentifier) }
        }
        if !includeHidden {
            lists = lists.filter { !isCalendarHidden($0) }
        }

        let items: [[String: Any]] = lists
            .sorted { lhs, rhs in
                let l = lhs.title
                let r = rhs.title
                return l.localizedCaseInsensitiveCompare(r) == .orderedAscending
            }
            .map { list in
                [
                    "list_id": list.calendarIdentifier,
                    "source_id": list.source.sourceIdentifier,
                    "title": list.title,
                    "type": listTypeString(list.type),
                    "color": hexColor(from: list.cgColor),
                    "is_writable": list.allowsContentModifications,
                    "is_hidden": isCalendarHidden(list)
                ]
            }

        try writeResponseAndExitIfNeeded([
            "ok": true,
            "result": ["lists": items]
        ])
    }

    private func listTypeString(_ type: EKCalendarType) -> String {
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
