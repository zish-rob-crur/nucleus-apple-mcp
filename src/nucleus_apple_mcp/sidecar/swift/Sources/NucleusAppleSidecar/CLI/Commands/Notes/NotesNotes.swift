import ArgumentParser

struct NotesNotes: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "notes",
        abstract: "List notes (metadata-first)."
    )

    @Option(help: "Filter by account identifier (repeatable).")
    var accountId: [String] = []

    @Option(help: "Filter by folder identifier (repeatable).")
    var folderId: [String] = []

    @Option(help: "Case-insensitive substring match against note name or plaintext.")
    var query: String?

    @Flag(help: "Include a plaintext excerpt (may be slower).")
    var includePlaintextExcerpt: Bool = false

    @Option(help: "Plaintext excerpt max length (must be > 0).")
    var plaintextExcerptMaxLen: Int = 200

    @Flag(help: "Include shared notes.")
    var includeShared: Bool = false

    @Flag(help: "Include notes under the system \"Recently Deleted\" folder (localized).")
    var includeRecentlyDeleted: Bool = false

    @Option(help: "Limit number of notes returned (must be > 0).")
    var limit: Int = 200

    func run() throws {
        let notes = try withProcessLock(name: "notes") {
            try NotesService.listNotes(
                accountId: accountId,
                folderId: folderId,
                query: query,
                includePlaintextExcerpt: includePlaintextExcerpt,
                plaintextExcerptMaxLen: plaintextExcerptMaxLen,
                includeShared: includeShared,
                includeRecentlyDeleted: includeRecentlyDeleted,
                limit: limit
            )
        }

        try writeResponseAndExitIfNeeded([
            "ok": true,
            "result": ["notes": notes]
        ])
    }
}

