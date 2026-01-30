import ArgumentParser

struct NotesGetNote: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "get-note",
        abstract: "Fetch a note with optional content and attachments."
    )

    @Option(help: "Note identifier.")
    var noteId: String

    @Flag(help: "Include plaintext content.")
    var includePlaintext: Bool = true

    @Flag(help: "Include body HTML.")
    var includeBodyHtml: Bool = false

    @Flag(help: "Include attachments.")
    var includeAttachments: Bool = true

    func run() throws {
        let result = try withProcessLock(name: "notes") {
            try NotesService.getNote(
                noteId: noteId,
                includePlaintext: includePlaintext,
                includeBodyHTML: includeBodyHtml,
                includeAttachments: includeAttachments
            )
        }

        try writeResponseAndExitIfNeeded([
            "ok": true,
            "result": result
        ])
    }
}

