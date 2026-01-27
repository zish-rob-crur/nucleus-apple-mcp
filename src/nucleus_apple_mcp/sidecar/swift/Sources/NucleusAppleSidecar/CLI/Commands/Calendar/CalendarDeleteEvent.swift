import ArgumentParser
import EventKit
import Foundation

struct CalendarDeleteEvent: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "delete-event",
        abstract: "Delete a calendar event."
    )

    enum Span: String, ExpressibleByArgument {
        case this
        case future

        var ekSpan: EKSpan {
            switch self {
            case .this:
                return .thisEvent
            case .future:
                return .futureEvents
            }
        }
    }

    @Option(help: "Event identifier.")
    var eventId: String

    @Option(help: "Delete this or future events (recurrence).")
    var span: Span = .this

    func run() throws {
        let store = try makeEventStoreRequiringFullAccess()
        guard let event = store.event(withIdentifier: eventId) else {
            throw SimpleSidecarError(code: "NOT_FOUND", message: "Event not found: \(eventId)")
        }

        guard event.calendar.allowsContentModifications else {
            throw SimpleSidecarError(code: "NOT_WRITABLE", message: "Event calendar is not writable: \(event.calendar.calendarIdentifier)")
        }

        do {
            try store.remove(event, span: span.ekSpan, commit: true)
        } catch {
            throw SimpleSidecarError(code: "INTERNAL", message: error.localizedDescription)
        }

        try writeResponseAndExitIfNeeded([
            "ok": true,
            "result": [
                "deleted": true,
                "event_id": eventId
            ]
        ])
    }
}
