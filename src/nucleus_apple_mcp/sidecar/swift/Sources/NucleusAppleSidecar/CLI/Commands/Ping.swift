import ArgumentParser

struct Ping: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Health check."
    )

    func run() throws {
        try writeResponseAndExitIfNeeded(["ok": true, "result": ["pong": true]])
    }
}

