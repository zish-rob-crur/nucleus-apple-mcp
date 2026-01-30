import ArgumentParser

struct NotesUpdateNote: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "update-note",
        abstract: "Update an existing note."
    )

    @Option(help: "Note identifier.")
    var noteId: String

    @Option(help: "Update note title.")
    var title: String?

    @Flag(help: "Required when using --set-plaintext or --set-markdown.")
    var allowDestructive: Bool = false

    @Option(help: "Replace note content with plaintext (destructive).")
    var setPlaintext: String?

    @Option(help: "Replace note content with Markdown (destructive).")
    var setMarkdown: String?

    @Option(help: "Append plaintext to the end of the note (best-effort).")
    var appendPlaintext: String?

    @Option(help: "Append Markdown to the end of the note (best-effort).")
    var appendMarkdown: String?

    @Option(help: "Add one or more attachments to the note (repeatable).")
    var attachFile: [String] = []

    func run() throws {
        let result = try withProcessLock(name: "notes") {
            try NotesService.updateNote(
                noteId: noteId,
                title: title,
                allowDestructive: allowDestructive,
                setPlaintext: setPlaintext,
                setMarkdown: setMarkdown,
                appendPlaintext: appendPlaintext,
                appendMarkdown: appendMarkdown,
                attachFiles: attachFile
            )
        }

        try writeResponseAndExitIfNeeded([
            "ok": true,
            "result": result
        ])
    }
}

