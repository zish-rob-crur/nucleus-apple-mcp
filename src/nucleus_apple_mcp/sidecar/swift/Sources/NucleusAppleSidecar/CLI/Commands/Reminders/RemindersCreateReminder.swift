import ArgumentParser
import EventKit
import Foundation

struct RemindersCreateReminder: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "create-reminder",
        abstract: "Create a reminder."
    )

    @Option(help: "List identifier.")
    var listId: String

    @Option(help: "Reminder title.")
    var title: String

    @Option(help: "Start date/time (ISO-8601 datetime or YYYY-MM-DD).")
    var start: String?

    @Option(help: "Due date/time (ISO-8601 datetime or YYYY-MM-DD).")
    var due: String?

    @Option(help: "Reminder notes.")
    var notes: String?

    @Option(help: "Reminder url.")
    var url: String?

    @Option(help: "Priority (0-9; 0 means none).")
    var priority: Int = 0

    func run() throws {
        guard (0...9).contains(priority) else {
            throw SimpleSidecarError(code: "INVALID_ARGUMENTS", message: "Invalid priority (0-9): \(priority)")
        }

        let store = try makeEventStoreRequiringRemindersAccess()
        guard let list = store.calendar(withIdentifier: listId) else {
            throw SimpleSidecarError(code: "NOT_FOUND", message: "List not found: \(listId)")
        }
        guard list.allowsContentModifications else {
            throw SimpleSidecarError(code: "NOT_WRITABLE", message: "List is not writable: \(listId)")
        }

        let reminder = EKReminder(eventStore: store)
        reminder.calendar = list
        reminder.title = title
        reminder.priority = priority

        if let start {
            reminder.startDateComponents = try parseReminderDateComponents(start)
        }
        if let due {
            reminder.dueDateComponents = try parseReminderDateComponents(due)
        }
        if let notes {
            reminder.notes = notes
        }
        if let url {
            guard let parsed = URL(string: url) else {
                throw SimpleSidecarError(code: "INVALID_ARGUMENTS", message: "Invalid URL: \(url)")
            }
            reminder.url = parsed
        }

        do {
            try store.save(reminder, commit: true)
        } catch {
            throw SimpleSidecarError(code: "INTERNAL", message: error.localizedDescription)
        }

        try writeResponseAndExitIfNeeded([
            "ok": true,
            "result": ["reminder": serializeReminder(reminder)]
        ])
    }
}
