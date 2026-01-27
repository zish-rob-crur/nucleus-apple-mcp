import Darwin
import Foundation

func makeErrorResponse(code: String = "INTERNAL", message: String) -> [String: Any] {
    [
        "ok": false,
        "error": [
            "code": code,
            "message": message
        ]
    ]
}

func writeResponseAndExitIfNeeded(_ response: [String: Any]) throws {
    try writeStdoutJSON(response)
    if (response["ok"] as? Bool) == false {
        Darwin.exit(1)
    }
}
