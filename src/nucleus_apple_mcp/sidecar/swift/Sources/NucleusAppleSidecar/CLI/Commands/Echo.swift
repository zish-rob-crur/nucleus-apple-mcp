import ArgumentParser
import Foundation

struct Echo: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Echoes back the JSON payload."
    )

    @Option(help: "JSON payload string (optional).")
    var payload: String?

    func run() throws {
        let value: Any
        if let payload {
            let data = Data(payload.utf8)
            value = try JSONSerialization.jsonObject(with: data, options: [])
        } else {
            value = NSNull()
        }

        try writeResponseAndExitIfNeeded(["ok": true, "result": value])
    }
}

