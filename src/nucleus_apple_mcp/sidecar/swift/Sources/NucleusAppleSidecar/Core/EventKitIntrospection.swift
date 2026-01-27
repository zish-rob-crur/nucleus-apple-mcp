import EventKit
import Foundation

func isCalendarHidden(_ calendar: EKCalendar) -> Bool {
    if let value = calendar.value(forKey: "isHidden") as? Bool {
        return value
    }
    if let value = calendar.value(forKey: "hidden") as? Bool {
        return value
    }
    return false
}

