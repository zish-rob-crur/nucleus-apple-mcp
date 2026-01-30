import ArgumentParser

struct NotesAddAttachment: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "add-attachment",
        abstract: "Add attachment(s) to a note from local file paths."
    )

    @Option(help: "Note identifier.")
    var noteId: String

    @Option(help: "Local file path to attach (repeatable).")
    var attachFile: [String] = []

    func run() throws {
        let attachments = try withProcessLock(name: "notes") {
            try NotesService.addAttachments(noteId: noteId, filePaths: attachFile)
        }

        try writeResponseAndExitIfNeeded([
            "ok": true,
            "result": ["attachments": attachments]
        ])
    }
}

