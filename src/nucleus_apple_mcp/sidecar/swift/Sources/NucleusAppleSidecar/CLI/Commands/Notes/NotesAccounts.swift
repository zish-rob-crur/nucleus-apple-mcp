import ArgumentParser

struct NotesAccounts: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "accounts",
        abstract: "List Notes accounts."
    )

    func run() throws {
        let accounts = try withProcessLock(name: "notes") {
            try NotesService.listAccounts()
        }

        try writeResponseAndExitIfNeeded([
            "ok": true,
            "result": ["accounts": accounts]
        ])
    }
}

