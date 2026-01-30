import ArgumentParser

struct NotesAttachments: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "attachments",
        abstract: "List attachments for a note."
    )

    @Option(help: "Note identifier.")
    var noteId: String

    @Flag(help: "Include shared attachments.")
    var includeShared: Bool = false

    func run() throws {
        let attachments = try withProcessLock(name: "notes") {
            try NotesService.listAttachments(noteId: noteId, includeShared: includeShared)
        }

        try writeResponseAndExitIfNeeded([
            "ok": true,
            "result": ["attachments": attachments]
        ])
    }
}

