import ArgumentParser

struct NotesCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "notes",
        abstract: "Notes (Apple Events) operations.",
        subcommands: [
            NotesAccounts.self,
            NotesFolders.self,
            NotesNotes.self,
            NotesGetNote.self,
            NotesCreateNote.self,
            NotesUpdateNote.self,
            NotesDeleteNote.self,
            NotesAttachments.self,
            NotesSaveAttachment.self,
            NotesAddAttachment.self
        ]
    )
}

