import ArgumentParser
import EventKit
import Foundation

struct RemindersReminders: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reminders",
        abstract: "List reminders by filters."
    )

    enum Status: String, ExpressibleByArgument {
        case open
        case completed
        case all
    }

    @Option(help: "Filter lower bound for reminder start (start >= start). ISO-8601 datetime or YYYY-MM-DD.")
    var start: String?

    @Option(help: "Filter upper bound for reminder start (start < end). ISO-8601 datetime or YYYY-MM-DD.")
    var end: String?

    @Option(help: "Filter lower bound for reminder due (due >= due-start). ISO-8601 datetime or YYYY-MM-DD.")
    var dueStart: String?

    @Option(help: "Filter upper bound for reminder due (due < due-end). ISO-8601 datetime or YYYY-MM-DD.")
    var dueEnd: String?

    @Option(help: "Filter by list identifier (repeatable).")
    var listId: [String] = []

    @Option(help: "Filter by source identifier (repeatable).")
    var sourceId: [String] = []

    @Option(help: "Filter by completion status (open|completed|all).")
    var status: Status = .open

    @Option(help: "Limit number of reminders returned (> 0).")
    var limit: Int = 200

    func run() throws {
        guard limit > 0 else {
            throw SimpleSidecarError(code: "INVALID_ARGUMENTS", message: "--limit must be > 0.")
        }

        let startLower = try start.map { try parseReminderFilterBoundaryDate($0, isEnd: false) }
        let startUpper = try end.map { try parseReminderFilterBoundaryDate($0, isEnd: true) }
        if let startLower, let startUpper, startLower >= startUpper {
            throw SimpleSidecarError(code: "INVALID_ARGUMENTS", message: "--start must be before --end.")
        }

        let dueLower = try dueStart.map { try parseReminderFilterBoundaryDate($0, isEnd: false) }
        let dueUpper = try dueEnd.map { try parseReminderFilterBoundaryDate($0, isEnd: true) }
        if let dueLower, let dueUpper, dueLower >= dueUpper {
            throw SimpleSidecarError(code: "INVALID_ARGUMENTS", message: "--due-start must be before --due-end.")
        }

        let store = try makeEventStoreRequiringRemindersAccess()
        let listIdFilter = Set(listId)
        let sourceIdFilter = Set(sourceId)

        var lists = store.calendars(for: .reminder).filter { !isCalendarHidden($0) }
        if !sourceIdFilter.isEmpty {
            lists = lists.filter { sourceIdFilter.contains($0.source.sourceIdentifier) }
        }
        if !listIdFilter.isEmpty {
            lists = lists.filter { listIdFilter.contains($0.calendarIdentifier) }
        }

        if lists.isEmpty {
            try writeResponseAndExitIfNeeded([
                "ok": true,
                "result": ["reminders": []]
            ])
            return
        }

        let predicate = store.predicateForReminders(in: lists)
        let reminders = try fetchReminders(store: store, predicate: predicate)
        let filtered = reminders
            .filter { matchesStatus($0) }
            .filter { matchesDateFilters($0, startLower: startLower, startUpper: startUpper, dueLower: dueLower, dueUpper: dueUpper) }

        let sorted = filtered.sorted { lhs, rhs in
            compare(lhs, rhs, status: status) == .orderedAscending
        }

        let items = Array(sorted.prefix(limit)).map { serializeReminder($0) }

        try writeResponseAndExitIfNeeded([
            "ok": true,
            "result": ["reminders": items]
        ])
    }

    private func fetchReminders(store: EKEventStore, predicate: NSPredicate) throws -> [EKReminder] {
        let semaphore = DispatchSemaphore(value: 0)
        var results: [EKReminder] = []

        store.fetchReminders(matching: predicate) { reminders in
            results = reminders ?? []
            semaphore.signal()
        }

        semaphore.wait()
        return results
    }

    private func matchesStatus(_ reminder: EKReminder) -> Bool {
        switch status {
        case .open:
            return !reminder.isCompleted
        case .completed:
            return reminder.isCompleted
        case .all:
            return true
        }
    }

    private func matchesDateFilters(
        _ reminder: EKReminder,
        startLower: Date?,
        startUpper: Date?,
        dueLower: Date?,
        dueUpper: Date?
    ) -> Bool {
        if startLower != nil || startUpper != nil {
            let startDate = reminderComponentsToDate(reminder.startDateComponents)
            if !matchesRange(startDate, lower: startLower, upper: startUpper) {
                return false
            }
        }
        if dueLower != nil || dueUpper != nil {
            let dueDate = reminderComponentsToDate(reminder.dueDateComponents)
            if !matchesRange(dueDate, lower: dueLower, upper: dueUpper) {
                return false
            }
        }
        return true
    }

    private func matchesRange(_ value: Date?, lower: Date?, upper: Date?) -> Bool {
        guard let value else { return false }
        if let lower, value < lower {
            return false
        }
        if let upper, value >= upper {
            return false
        }
        return true
    }

    private func compare(_ lhs: EKReminder, _ rhs: EKReminder, status: Status) -> ComparisonResult {
        if status == .all {
            switch (lhs.isCompleted, rhs.isCompleted) {
            case (false, true):
                return .orderedAscending
            case (true, false):
                return .orderedDescending
            default:
                break
            }
        }

        let lhsDue = reminderComponentsToDate(lhs.dueDateComponents)
        let rhsDue = reminderComponentsToDate(rhs.dueDateComponents)
        if let r = compareOptionalDate(lhsDue, rhsDue) {
            return r
        }

        let lhsStart = reminderComponentsToDate(lhs.startDateComponents)
        let rhsStart = reminderComponentsToDate(rhs.startDateComponents)
        if let r = compareOptionalDate(lhsStart, rhsStart) {
            return r
        }

        let lt = lhs.title ?? ""
        let rt = rhs.title ?? ""
        let titleCompare = lt.localizedCaseInsensitiveCompare(rt)
        if titleCompare != .orderedSame {
            return titleCompare
        }

        let lid = lhs.calendarItemIdentifier
        let rid = rhs.calendarItemIdentifier
        return lid.compare(rid)
    }

    private func compareOptionalDate(_ lhs: Date?, _ rhs: Date?) -> ComparisonResult? {
        switch (lhs, rhs) {
        case (nil, nil):
            return nil
        case (nil, _?):
            return .orderedDescending
        case (_?, nil):
            return .orderedAscending
        case (let l?, let r?):
            if l < r { return .orderedAscending }
            if l > r { return .orderedDescending }
            return nil
        }
    }
}
