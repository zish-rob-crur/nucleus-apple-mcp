import ArgumentParser

struct NotesCreateNote: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "create-note",
        abstract: "Create a new note."
    )

    @Option(help: "Folder identifier. If omitted, uses the default account + default folder.")
    var folderId: String?

    @Option(help: "Note title.")
    var title: String?

    @Option(help: "Plaintext content (converted to HTML).")
    var plaintext: String?

    @Option(help: "Markdown content (converted to HTML).")
    var markdown: String?

    @Option(help: "Add one or more attachments after note creation (repeatable).")
    var attachFile: [String] = []

    func run() throws {
        let result = try withProcessLock(name: "notes") {
            try NotesService.createNote(
                folderId: folderId,
                title: title,
                plaintext: plaintext,
                markdown: markdown,
                attachFiles: attachFile
            )
        }

        try writeResponseAndExitIfNeeded([
            "ok": true,
            "result": result
        ])
    }
}

