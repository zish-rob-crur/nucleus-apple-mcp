import ArgumentParser
import EventKit
import Foundation

struct RemindersUpdateReminder: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "update-reminder",
        abstract: "Update an existing reminder."
    )

    @Option(help: "Reminder identifier.")
    var reminderId: String

    @Option(help: "Move the reminder to another list (list must be writable).")
    var listId: String?

    @Option(help: "Reminder title.")
    var title: String?

    @Option(help: "Start date/time (ISO-8601 datetime or YYYY-MM-DD).")
    var start: String?

    @Flag(help: "Clear start.")
    var clearStart: Bool = false

    @Option(help: "Due date/time (ISO-8601 datetime or YYYY-MM-DD).")
    var due: String?

    @Flag(help: "Clear due.")
    var clearDue: Bool = false

    @Option(help: "Reminder notes.")
    var notes: String?

    @Flag(help: "Clear notes.")
    var clearNotes: Bool = false

    @Option(help: "Reminder url.")
    var url: String?

    @Flag(help: "Clear url.")
    var clearUrl: Bool = false

    @Option(help: "Priority (0-9; 0 means none).")
    var priority: Int?

    @Flag(help: "Clear priority (reset to 0).")
    var clearPriority: Bool = false

    @Option(help: "Set completion status (true/false).")
    var completed: Bool?

    func run() throws {
        let hasChanges =
            listId != nil
                || title != nil
                || start != nil
                || clearStart
                || due != nil
                || clearDue
                || notes != nil
                || clearNotes
                || url != nil
                || clearUrl
                || priority != nil
                || clearPriority
                || completed != nil

        if !hasChanges {
            throw SimpleSidecarError(code: "INVALID_ARGUMENTS", message: "No fields to update.")
        }

        if clearStart, start != nil {
            throw SimpleSidecarError(code: "INVALID_ARGUMENTS", message: "Cannot use --start with --clear-start.")
        }
        if clearDue, due != nil {
            throw SimpleSidecarError(code: "INVALID_ARGUMENTS", message: "Cannot use --due with --clear-due.")
        }
        if clearNotes, notes != nil {
            throw SimpleSidecarError(code: "INVALID_ARGUMENTS", message: "Cannot use --notes with --clear-notes.")
        }
        if clearUrl, url != nil {
            throw SimpleSidecarError(code: "INVALID_ARGUMENTS", message: "Cannot use --url with --clear-url.")
        }
        if clearPriority, priority != nil {
            throw SimpleSidecarError(code: "INVALID_ARGUMENTS", message: "Cannot use --priority with --clear-priority.")
        }
        if let priority, !(0...9).contains(priority) {
            throw SimpleSidecarError(code: "INVALID_ARGUMENTS", message: "Invalid priority (0-9): \(priority)")
        }

        let store = try makeEventStoreRequiringRemindersAccess()
        guard let item = store.calendarItem(withIdentifier: reminderId) as? EKReminder else {
            throw SimpleSidecarError(code: "NOT_FOUND", message: "Reminder not found: \(reminderId)")
        }

        guard item.calendar.allowsContentModifications else {
            throw SimpleSidecarError(code: "NOT_WRITABLE", message: "Reminder list is not writable: \(item.calendar.calendarIdentifier)")
        }

        if let listId {
            guard let list = store.calendar(withIdentifier: listId) else {
                throw SimpleSidecarError(code: "NOT_FOUND", message: "List not found: \(listId)")
            }
            guard list.allowsContentModifications else {
                throw SimpleSidecarError(code: "NOT_WRITABLE", message: "List is not writable: \(listId)")
            }
            item.calendar = list
        }

        if let title {
            item.title = title
        }

        if clearStart {
            item.startDateComponents = nil
        } else if let start {
            item.startDateComponents = try parseReminderDateComponents(start)
        }

        if clearDue {
            item.dueDateComponents = nil
        } else if let due {
            item.dueDateComponents = try parseReminderDateComponents(due)
        }

        if clearNotes {
            item.notes = nil
        } else if let notes {
            item.notes = notes
        }

        if clearUrl {
            item.url = nil
        } else if let url {
            guard let parsed = URL(string: url) else {
                throw SimpleSidecarError(code: "INVALID_ARGUMENTS", message: "Invalid URL: \(url)")
            }
            item.url = parsed
        }

        if clearPriority {
            item.priority = 0
        } else if let priority {
            item.priority = priority
        }

        if let completed {
            if completed {
                item.isCompleted = true
                item.completionDate = Date()
            } else {
                item.isCompleted = false
                item.completionDate = nil
            }
        }

        do {
            try store.save(item, commit: true)
        } catch {
            throw SimpleSidecarError(code: "INTERNAL", message: error.localizedDescription)
        }

        try writeResponseAndExitIfNeeded([
            "ok": true,
            "result": ["reminder": serializeReminder(item)]
        ])
    }
}
