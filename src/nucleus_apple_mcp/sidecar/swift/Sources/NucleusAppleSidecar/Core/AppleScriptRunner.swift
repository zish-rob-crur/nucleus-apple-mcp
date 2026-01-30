import Foundation

func runAppleScript(_ source: String) throws -> NSAppleEventDescriptor {
    guard let script = NSAppleScript(source: source) else {
        throw SimpleSidecarError(code: "INTERNAL", message: "Failed to compile AppleScript.")
    }

    var error: NSDictionary?
    let result = script.executeAndReturnError(&error)
    if let error {
        throw mapAppleScriptError(error)
    }
    return result
}

private func mapAppleScriptError(_ error: NSDictionary) -> SimpleSidecarError {
    let number = (error[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? 0
    let message = (error[NSAppleScript.errorMessage] as? String) ?? "AppleScript error \(number)"

    switch number {
    case -1743:
        return SimpleSidecarError(code: "NOT_AUTHORIZED", message: "Automation permission denied for Notes.app.")
    case -1719, -1728:
        return SimpleSidecarError(code: "NOT_FOUND", message: message)
    case -1700, -1703:
        return SimpleSidecarError(code: "INVALID_ARGUMENTS", message: message)
    default:
        return SimpleSidecarError(code: "INTERNAL", message: message)
    }
}

