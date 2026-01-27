import EventKit
import Foundation

func serializeReminder(_ reminder: EKReminder) -> [String: Any] {
    [
        "reminder_id": reminder.calendarItemIdentifier,
        "list_id": reminder.calendar.calendarIdentifier,
        "title": reminder.title ?? "",
        "start": formatReminderDateValue(reminder.startDateComponents),
        "due": formatReminderDateValue(reminder.dueDateComponents),
        "is_completed": reminder.isCompleted,
        "notes": reminder.notes as Any? ?? NSNull(),
        "url": reminder.url?.absoluteString as Any? ?? NSNull(),
        "priority": reminder.priority
    ]
}
