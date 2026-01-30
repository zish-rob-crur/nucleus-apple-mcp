import ArgumentParser

struct NotesDeleteNote: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "delete-note",
        abstract: "Delete a note."
    )

    @Option(help: "Note identifier.")
    var noteId: String

    func run() throws {
        let deleted = try withProcessLock(name: "notes") {
            try NotesService.deleteNote(noteId: noteId)
        }

        try writeResponseAndExitIfNeeded([
            "ok": true,
            "result": ["deleted_note_id": deleted]
        ])
    }
}

