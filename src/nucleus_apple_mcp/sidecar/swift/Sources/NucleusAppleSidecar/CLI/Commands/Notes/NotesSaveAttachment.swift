import ArgumentParser

struct NotesSaveAttachment: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "save-attachment",
        abstract: "Export an attachment to a file path."
    )

    @Option(help: "Attachment identifier.")
    var attachmentId: String

    @Option(help: "Output file path.")
    var outputPath: String

    @Flag(help: "Overwrite the output file if it exists.")
    var overwrite: Bool = false

    func run() throws {
        let out = try withProcessLock(name: "notes") {
            try NotesService.saveAttachment(attachmentId: attachmentId, outputPath: outputPath, overwrite: overwrite)
        }

        try writeResponseAndExitIfNeeded([
            "ok": true,
            "result": ["output_path": out]
        ])
    }
}

