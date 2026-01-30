import ArgumentParser

struct NotesFolders: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "folders",
        abstract: "List folders."
    )

    @Option(help: "Filter by account identifier (repeatable).")
    var accountId: [String] = []

    @Option(help: "Filter by parent folder identifier.")
    var parentFolderId: String?

    @Flag(help: "When set, returns the entire subtree under the filter.")
    var recursive: Bool = false

    @Flag(help: "Include shared folders.")
    var includeShared: Bool = false

    @Flag(help: "Include the system \"Recently Deleted\" folder (localized).")
    var includeRecentlyDeleted: Bool = false

    func run() throws {
        let folders = try withProcessLock(name: "notes") {
            try NotesService.listFolders(
                accountId: accountId,
                parentFolderId: parentFolderId,
                recursive: recursive,
                includeShared: includeShared,
                includeRecentlyDeleted: includeRecentlyDeleted
            )
        }

        try writeResponseAndExitIfNeeded([
            "ok": true,
            "result": ["folders": folders]
        ])
    }
}

