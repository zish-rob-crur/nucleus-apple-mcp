import EventKit
import Foundation

func makeEventStoreRequiringFullAccess() throws -> EKEventStore {
    let store = EKEventStore()
    let status = EKEventStore.authorizationStatus(for: .event)

    switch status {
    case .authorized:
        return store
    case .fullAccess:
        return store
    case .notDetermined:
        let semaphore = DispatchSemaphore(value: 0)
        var granted = false
        var requestError: Error?

        if #available(macOS 14.0, *) {
            store.requestFullAccessToEvents { ok, error in
                granted = ok
                requestError = error
                semaphore.signal()
            }
        } else {
            store.requestAccess(to: .event) { ok, error in
                granted = ok
                requestError = error
                semaphore.signal()
            }
        }

        semaphore.wait()

        if let requestError {
            throw SimpleSidecarError(code: "NOT_AUTHORIZED", message: requestError.localizedDescription)
        }
        if granted {
            return store
        }
        throw SimpleSidecarError(
            code: "NOT_AUTHORIZED",
            message: "Calendar access not granted. Enable it in System Settings → Privacy & Security → Calendars."
        )
    case .denied, .restricted:
        throw SimpleSidecarError(
            code: "NOT_AUTHORIZED",
            message: "Calendar access denied. Enable it in System Settings → Privacy & Security → Calendars."
        )
    case .writeOnly:
        throw SimpleSidecarError(
            code: "NOT_AUTHORIZED",
            message: "Write-only Calendar access is not sufficient for read operations."
        )
    @unknown default:
        throw SimpleSidecarError(code: "NOT_AUTHORIZED", message: "Unsupported Calendar authorization status.")
    }
}

func makeEventStoreRequiringRemindersAccess() throws -> EKEventStore {
    let store = EKEventStore()
    let status = EKEventStore.authorizationStatus(for: .reminder)

    switch status {
    case .authorized:
        return store
    case .fullAccess:
        return store
    case .notDetermined:
        let semaphore = DispatchSemaphore(value: 0)
        var granted = false
        var requestError: Error?

        if #available(macOS 14.0, *) {
            store.requestFullAccessToReminders { ok, error in
                granted = ok
                requestError = error
                semaphore.signal()
            }
        } else {
            store.requestAccess(to: .reminder) { ok, error in
                granted = ok
                requestError = error
                semaphore.signal()
            }
        }

        semaphore.wait()

        if let requestError {
            throw SimpleSidecarError(code: "NOT_AUTHORIZED", message: requestError.localizedDescription)
        }
        if granted {
            return store
        }
        throw SimpleSidecarError(
            code: "NOT_AUTHORIZED",
            message: "Reminders access not granted. Enable it in System Settings → Privacy & Security → Reminders."
        )
    case .denied, .restricted:
        throw SimpleSidecarError(
            code: "NOT_AUTHORIZED",
            message: "Reminders access denied. Enable it in System Settings → Privacy & Security → Reminders."
        )
    case .writeOnly:
        throw SimpleSidecarError(
            code: "NOT_AUTHORIZED",
            message: "Write-only Reminders access is not sufficient for read operations."
        )
    @unknown default:
        throw SimpleSidecarError(code: "NOT_AUTHORIZED", message: "Unsupported Reminders authorization status.")
    }
}
