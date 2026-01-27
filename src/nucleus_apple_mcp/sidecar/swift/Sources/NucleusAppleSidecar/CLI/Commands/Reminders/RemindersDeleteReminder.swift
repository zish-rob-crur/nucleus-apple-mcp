import ArgumentParser
import EventKit
import Foundation

struct RemindersDeleteReminder: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "delete-reminder",
        abstract: "Delete a reminder."
    )

    @Option(help: "Reminder identifier.")
    var reminderId: String

    func run() throws {
        let store = try makeEventStoreRequiringRemindersAccess()
        guard let item = store.calendarItem(withIdentifier: reminderId) as? EKReminder else {
            throw SimpleSidecarError(code: "NOT_FOUND", message: "Reminder not found: \(reminderId)")
        }

        guard item.calendar.allowsContentModifications else {
            throw SimpleSidecarError(code: "NOT_WRITABLE", message: "Reminder list is not writable: \(item.calendar.calendarIdentifier)")
        }

        do {
            try store.remove(item, commit: true)
        } catch {
            throw SimpleSidecarError(code: "INTERNAL", message: error.localizedDescription)
        }

        try writeResponseAndExitIfNeeded([
            "ok": true,
            "result": [
                "deleted": true,
                "reminder_id": reminderId
            ]
        ])
    }
}
