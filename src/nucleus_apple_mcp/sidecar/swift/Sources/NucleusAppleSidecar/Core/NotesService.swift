import Foundation
import ScriptingBridge

struct NotesService {
    static func listAccounts() throws -> [[String: Any]] {
        let app = try notesApp()
        guard let accounts = app.value(forKey: "accounts") as? SBElementArray else {
            try throwIfLastError(app, fallback: SimpleSidecarError(code: "INTERNAL", message: "Failed to list accounts."))
            return []
        }

        return (0..<accounts.count).compactMap { idx in
            guard let acc = accounts.object(at: idx) as? SBObject else {
                return nil
            }

            let accountId = stringValue(acc.value(forKey: "id"))
            let name = stringValue(acc.value(forKey: "name"))
            let upgraded = boolValue(acc.value(forKey: "upgraded"))
            let defaultFolderId: String? = {
                guard let ref = acc.value(forKey: "defaultFolder") as? SBObject,
                      let folder = try? resolveObject(ref, notFoundCode: "INTERNAL"),
                      let folderId = folder.value(forKey: "id") as? String else {
                    return nil
                }
                return folderId
            }()

            return [
                "account_id": accountId,
                "name": name,
                "upgraded": upgraded,
                "default_folder_id": defaultFolderId as Any
            ]
        }
    }

    static func listFolders(
        accountId: [String],
        parentFolderId: String?,
        recursive: Bool,
        includeShared: Bool,
        includeRecentlyDeleted: Bool
    ) throws -> [[String: Any]] {
        let app = try notesApp()

        if let parentFolderId {
            let parent = try resolveFolder(app: app, folderId: parentFolderId)
            return try foldersUnder(
                folder: parent,
                containerType: "folder",
                containerId: parentFolderId,
                recursive: recursive,
                includeShared: includeShared,
                includeRecentlyDeleted: includeRecentlyDeleted
            )
        }

        let accountFilter = Set(accountId)
        guard let accounts = app.value(forKey: "accounts") as? SBElementArray else {
            try throwIfLastError(app, fallback: SimpleSidecarError(code: "INTERNAL", message: "Failed to list accounts."))
            return []
        }

        var out: [[String: Any]] = []
        for idx in 0..<accounts.count {
            guard let acc = accounts.object(at: idx) as? SBObject else {
                continue
            }

            let accId = stringValue(acc.value(forKey: "id"))
            if !accountFilter.isEmpty && !accountFilter.contains(accId) {
                continue
            }

            guard let folders = acc.value(forKey: "folders") as? SBElementArray else {
                continue
            }

            for jdx in 0..<folders.count {
                guard let folder = folders.object(at: jdx) as? SBObject else {
                    continue
                }
                out.append(contentsOf: try folderAndMaybeDescendants(
                    folder: folder,
                    containerType: "account",
                    containerId: accId,
                    recursive: recursive,
                    includeShared: includeShared,
                    includeRecentlyDeleted: includeRecentlyDeleted
                ))
            }
        }

        return out.sorted { lhs, rhs in
            let l = (lhs["name"] as? String) ?? ""
            let r = (rhs["name"] as? String) ?? ""
            let cmp = l.localizedCaseInsensitiveCompare(r)
            if cmp != .orderedSame {
                return cmp == .orderedAscending
            }
            return ((lhs["folder_id"] as? String) ?? "") < ((rhs["folder_id"] as? String) ?? "")
        }
    }

    static func listNotes(
        accountId: [String],
        folderId: [String],
        query: String?,
        includePlaintextExcerpt: Bool,
        plaintextExcerptMaxLen: Int,
        includeShared: Bool,
        includeRecentlyDeleted: Bool,
        limit: Int
    ) throws -> [[String: Any]] {
        let app = try notesApp()
        if plaintextExcerptMaxLen <= 0 {
            throw SimpleSidecarError(code: "INVALID_ARGUMENTS", message: "--plaintext-excerpt-max-len must be > 0")
        }
        if limit <= 0 {
            throw SimpleSidecarError(code: "INVALID_ARGUMENTS", message: "--limit must be > 0")
        }

        let accountFilter = Set(accountId)
        let folderFilter = Set(folderId)
        let folderAccountMap = try buildFolderAccountMap(app: app)

        guard let notes = app.value(forKey: "notes") as? SBElementArray else {
            try throwIfLastError(app, fallback: SimpleSidecarError(code: "INTERNAL", message: "Failed to list notes."))
            return []
        }

        var candidates: [NoteCandidate] = []
        candidates.reserveCapacity(min(notes.count, limit))

        var seen: Set<String> = []
        for idx in 0..<notes.count {
            guard let noteRef = notes.object(at: idx) as? SBObject else {
                continue
            }
            guard let note = try? resolveObject(noteRef, notFoundCode: "INTERNAL") else {
                continue
            }

            let noteId = stringValue(note.value(forKey: "id"))
            if noteId.isEmpty || seen.contains(noteId) {
                continue
            }
            seen.insert(noteId)

            let isPasswordProtected = boolValue(note.value(forKey: "passwordProtected"))
            let isShared = boolValue(note.value(forKey: "shared"))
            if isShared && !includeShared {
                continue
            }

            guard let containerRef = note.value(forKey: "container") as? SBObject,
                  let containerFolder = try? resolveObject(containerRef, notFoundCode: "INTERNAL") else {
                continue
            }
            let containerFolderId = stringValue(containerFolder.value(forKey: "id"))
            let containerFolderName = stringValue(containerFolder.value(forKey: "name"))

            if !includeRecentlyDeleted && isRecentlyDeletedFolderName(containerFolderName) {
                continue
            }

            if !folderFilter.isEmpty && !folderFilter.contains(containerFolderId) {
                continue
            }

            if !accountFilter.isEmpty {
                guard let accId = folderAccountMap[containerFolderId], accountFilter.contains(accId) else {
                    continue
                }
            }

            let name = stringValue(note.value(forKey: "name"))
            let created = (note.value(forKey: "creationDate") as? Date) ?? Date(timeIntervalSince1970: 0)
            let modified = (note.value(forKey: "modificationDate") as? Date) ?? Date(timeIntervalSince1970: 0)

            let attachmentCount: Int = {
                guard let atts = note.value(forKey: "attachments") as? SBElementArray else {
                    return 0
                }
                return atts.count
            }()

            candidates.append(NoteCandidate(
                note: note,
                noteId: noteId,
                folderId: containerFolderId,
                name: name,
                creationDate: created,
                modificationDate: modified,
                isPasswordProtected: isPasswordProtected,
                isShared: isShared,
                attachmentCount: attachmentCount
            ))
        }

        candidates.sort()

        let q = query?.lowercased()
        var out: [[String: Any]] = []
        out.reserveCapacity(min(limit, candidates.count))

        for c in candidates {
            if out.count >= limit {
                break
            }

            var plaintext: String?
            var matched = true

            if let q, !q.isEmpty {
                let nameMatch = c.name.lowercased().contains(q)
                if nameMatch {
                    matched = true
                } else if c.isPasswordProtected {
                    matched = false
                } else {
                    plaintext = stringValue(c.note.value(forKey: "plaintext"))
                    matched = plaintext?.lowercased().contains(q) ?? false
                }
            }

            if !matched {
                continue
            }

            var excerpt: String?
            if includePlaintextExcerpt && !c.isPasswordProtected {
                if plaintext == nil {
                    plaintext = stringValue(c.note.value(forKey: "plaintext"))
                }
                if let plaintext {
                    excerpt = String(plaintext.prefix(plaintextExcerptMaxLen))
                }
            }

            out.append([
                "note_id": c.noteId,
                "folder_id": c.folderId,
                "name": c.name,
                "creation_date": formatISO8601Date(c.creationDate),
                "modification_date": formatISO8601Date(c.modificationDate),
                "is_password_protected": c.isPasswordProtected,
                "is_shared": c.isShared,
                "attachment_count": c.attachmentCount,
                "plaintext_excerpt": excerpt as Any
            ])
        }

        return out
    }

    static func getNote(
        noteId: String,
        includePlaintext: Bool,
        includeBodyHTML: Bool,
        includeAttachments: Bool
    ) throws -> [String: Any] {
        let app = try notesApp()
        let note = try resolveNote(app: app, noteId: noteId)
        if boolValue(note.value(forKey: "passwordProtected")) {
            throw SimpleSidecarError(code: "LOCKED", message: "Note is password protected.")
        }

        return try noteDetail(
            app: app,
            note: note,
            includePlaintext: includePlaintext,
            includeBodyHTML: includeBodyHTML,
            includeAttachments: includeAttachments
        )
    }

    static func createNote(
        folderId: String?,
        title: String?,
        plaintext: String?,
        markdown: String?,
        attachFiles: [String]
    ) throws -> [String: Any] {
        if plaintext != nil && markdown != nil {
            throw SimpleSidecarError(code: "INVALID_ARGUMENTS", message: "Provide at most one of --plaintext and --markdown.")
        }

        let app = try notesApp()
        if let folderId {
            _ = try resolveFolder(app: app, folderId: folderId)
        }

        let noteId = try createNoteAppleScript(folderId: folderId, title: title)
        let note = try resolveNote(app: app, noteId: noteId)

        let bodyHTML: String = {
            if let plaintext {
                return plaintextToHTML(plaintext)
            }
            if let markdown {
                return markdownToSafeHTML(markdown)
            }
            return plaintextToHTML("")
        }()

        note.setValue(bodyHTML, forKey: "body")
        try throwIfLastError(note, fallback: SimpleSidecarError(code: "INTERNAL", message: "Failed to set note body."))

        if let title {
            note.setValue(title, forKey: "name")
            try throwIfLastError(note, fallback: SimpleSidecarError(code: "INTERNAL", message: "Failed to set note title."))
        }

        if !attachFiles.isEmpty {
            try validateAttachFiles(attachFiles)
            _ = try addAttachmentsAppleScript(noteId: noteId, filePaths: attachFiles)
        }

        return try noteDetail(app: app, note: note, includePlaintext: true, includeBodyHTML: false, includeAttachments: true)
    }

    static func updateNote(
        noteId: String,
        title: String?,
        allowDestructive: Bool,
        setPlaintext: String?,
        setMarkdown: String?,
        appendPlaintext: String?,
        appendMarkdown: String?,
        attachFiles: [String]
    ) throws -> [String: Any] {
        let updates = [setPlaintext, setMarkdown, appendPlaintext, appendMarkdown].compactMap { $0 }
        if updates.count > 1 {
            throw SimpleSidecarError(code: "INVALID_ARGUMENTS", message: "Provide at most one content update mode.")
        }
        if setPlaintext != nil || setMarkdown != nil {
            if !allowDestructive {
                throw SimpleSidecarError(code: "INVALID_ARGUMENTS", message: "--allow-destructive is required for --set-* operations.")
            }
        }

        if title == nil && updates.isEmpty && attachFiles.isEmpty {
            throw SimpleSidecarError(code: "INVALID_ARGUMENTS", message: "No updates provided.")
        }

        let app = try notesApp()
        let note = try resolveNote(app: app, noteId: noteId)
        if boolValue(note.value(forKey: "passwordProtected")) {
            throw SimpleSidecarError(code: "LOCKED", message: "Note is password protected.")
        }
        if boolValue(note.value(forKey: "shared")) {
            throw SimpleSidecarError(code: "NOT_WRITABLE", message: "Shared note is read-only.")
        }

        if let title {
            note.setValue(title, forKey: "name")
            try throwIfLastError(note, fallback: SimpleSidecarError(code: "INTERNAL", message: "Failed to set note title."))
        }

        if let setPlaintext {
            note.setValue(plaintextToHTML(setPlaintext), forKey: "body")
            try throwIfLastError(note, fallback: SimpleSidecarError(code: "INTERNAL", message: "Failed to set note body."))
        } else if let setMarkdown {
            note.setValue(markdownToSafeHTML(setMarkdown), forKey: "body")
            try throwIfLastError(note, fallback: SimpleSidecarError(code: "INTERNAL", message: "Failed to set note body."))
        } else if let appendPlaintext {
            let existing = stringValue(note.value(forKey: "body"))
            let addition = plaintextToHTML(appendPlaintext)
            let combined = existing.isEmpty ? addition : (existing + "<br/>" + addition)
            note.setValue(combined, forKey: "body")
            try throwIfLastError(note, fallback: SimpleSidecarError(code: "INTERNAL", message: "Failed to append note body."))
        } else if let appendMarkdown {
            let existing = stringValue(note.value(forKey: "body"))
            let addition = markdownToSafeHTML(appendMarkdown)
            let combined = existing.isEmpty ? addition : (existing + "<br/>" + addition)
            note.setValue(combined, forKey: "body")
            try throwIfLastError(note, fallback: SimpleSidecarError(code: "INTERNAL", message: "Failed to append note body."))
        }

        if !attachFiles.isEmpty {
            try validateAttachFiles(attachFiles)
            _ = try addAttachmentsAppleScript(noteId: noteId, filePaths: attachFiles)
        }

        return try noteDetail(app: app, note: note, includePlaintext: true, includeBodyHTML: false, includeAttachments: true)
    }

    static func deleteNote(noteId: String) throws -> String {
        let app = try notesApp()
        let note = try resolveNote(app: app, noteId: noteId)
        if boolValue(note.value(forKey: "passwordProtected")) {
            throw SimpleSidecarError(code: "LOCKED", message: "Note is password protected.")
        }
        if boolValue(note.value(forKey: "shared")) {
            throw SimpleSidecarError(code: "NOT_WRITABLE", message: "Shared note is read-only.")
        }

        _ = try deleteNoteAppleScript(noteId: noteId)
        return noteId
    }

    static func listAttachments(noteId: String, includeShared: Bool) throws -> [[String: Any]] {
        let app = try notesApp()
        let note = try resolveNote(app: app, noteId: noteId)
        if boolValue(note.value(forKey: "passwordProtected")) {
            throw SimpleSidecarError(code: "LOCKED", message: "Note is password protected.")
        }

        return attachmentsForNote(note: note, noteId: noteId, includeShared: includeShared)
    }

    static func addAttachments(noteId: String, filePaths: [String]) throws -> [[String: Any]] {
        if filePaths.isEmpty {
            throw SimpleSidecarError(code: "INVALID_ARGUMENTS", message: "--attach-file is required.")
        }

        try validateAttachFiles(filePaths)

        let app = try notesApp()
        let note = try resolveNote(app: app, noteId: noteId)
        if boolValue(note.value(forKey: "passwordProtected")) {
            throw SimpleSidecarError(code: "LOCKED", message: "Note is password protected.")
        }
        if boolValue(note.value(forKey: "shared")) {
            throw SimpleSidecarError(code: "NOT_WRITABLE", message: "Shared note is read-only.")
        }

        let newIds = try addAttachmentsAppleScript(noteId: noteId, filePaths: filePaths)
        return newIds.compactMap { aid in
            guard let att = try? resolveAttachment(app: app, attachmentId: aid) else {
                return nil
            }
            return attachmentDict(att, noteId: noteId)
        }
    }

    static func saveAttachment(attachmentId: String, outputPath: String, overwrite: Bool) throws -> String {
        let app = try notesApp()
        _ = try resolveAttachment(app: app, attachmentId: attachmentId)

        let fm = FileManager.default
        if fm.fileExists(atPath: outputPath) {
            if !overwrite {
                throw SimpleSidecarError(code: "INVALID_ARGUMENTS", message: "Output file exists. Use --overwrite.")
            }
            try fm.removeItem(atPath: outputPath)
        }

        _ = try saveAttachmentAppleScript(attachmentId: attachmentId, outputPath: outputPath)
        return outputPath
    }

    // MARK: - Internals

    private static func notesApp() throws -> SBApplication {
        guard let app = SBApplication(bundleIdentifier: "com.apple.Notes") else {
            throw SimpleSidecarError(code: "INTERNAL", message: "Failed to connect to Notes.app.")
        }
        return app
    }

    private static func resolveFolder(app: SBApplication, folderId: String) throws -> SBObject {
        guard let folders = app.value(forKey: "folders") as? SBElementArray else {
            throw SimpleSidecarError(code: "INTERNAL", message: "Failed to access folders.")
        }
        guard let ref = folders.object(withID: folderId) as? SBObject else {
            throw SimpleSidecarError(code: "NOT_FOUND", message: "Folder not found: \(folderId)")
        }
        return try resolveObject(ref, notFoundCode: "NOT_FOUND")
    }

    private static func resolveNote(app: SBApplication, noteId: String) throws -> SBObject {
        guard let notes = app.value(forKey: "notes") as? SBElementArray else {
            throw SimpleSidecarError(code: "INTERNAL", message: "Failed to access notes.")
        }
        guard let ref = notes.object(withID: noteId) as? SBObject else {
            throw SimpleSidecarError(code: "NOT_FOUND", message: "Note not found: \(noteId)")
        }
        return try resolveObject(ref, notFoundCode: "NOT_FOUND")
    }

    private static func resolveAttachment(app: SBApplication, attachmentId: String) throws -> SBObject {
        guard let atts = app.value(forKey: "attachments") as? SBElementArray else {
            throw SimpleSidecarError(code: "INTERNAL", message: "Failed to access attachments.")
        }
        guard let ref = atts.object(withID: attachmentId) as? SBObject else {
            throw SimpleSidecarError(code: "NOT_FOUND", message: "Attachment not found: \(attachmentId)")
        }
        return try resolveObject(ref, notFoundCode: "NOT_FOUND")
    }

    private static func resolveObject(_ ref: SBObject, notFoundCode: String) throws -> SBObject {
        guard let obj = ref.get() as? SBObject else {
            if let err = ref.lastError() {
                throw mapScriptingBridgeError(err, notFoundCode: notFoundCode)
            }
            throw SimpleSidecarError(code: notFoundCode, message: "Object not found.")
        }
        return obj
    }

    private static func validateAttachFiles(_ paths: [String]) throws {
        let fm = FileManager.default
        for path in paths {
            var isDir: ObjCBool = false
            if !fm.fileExists(atPath: path, isDirectory: &isDir) {
                throw SimpleSidecarError(code: "INVALID_ARGUMENTS", message: "File does not exist: \(path)")
            }
            if isDir.boolValue {
                throw SimpleSidecarError(code: "INVALID_ARGUMENTS", message: "Expected file but got directory: \(path)")
            }
        }
    }

    private static func noteDetail(
        app: SBApplication,
        note: SBObject,
        includePlaintext: Bool,
        includeBodyHTML: Bool,
        includeAttachments: Bool
    ) throws -> [String: Any] {
        let noteId = stringValue(note.value(forKey: "id"))
        let name = stringValue(note.value(forKey: "name"))
        let created = (note.value(forKey: "creationDate") as? Date) ?? Date(timeIntervalSince1970: 0)
        let modified = (note.value(forKey: "modificationDate") as? Date) ?? Date(timeIntervalSince1970: 0)
        let isPasswordProtected = boolValue(note.value(forKey: "passwordProtected"))
        let isShared = boolValue(note.value(forKey: "shared"))

        guard let containerRef = note.value(forKey: "container") as? SBObject else {
            throw SimpleSidecarError(code: "INTERNAL", message: "Failed to resolve note folder.")
        }
        let folder = try resolveObject(containerRef, notFoundCode: "INTERNAL")
        guard let folderId = folder.value(forKey: "id") as? String, !folderId.isEmpty else {
            throw SimpleSidecarError(code: "INTERNAL", message: "Failed to resolve note folder identifier.")
        }

        let plaintext = includePlaintext ? (note.value(forKey: "plaintext") as? String) : nil
        let bodyHTML = includeBodyHTML ? (note.value(forKey: "body") as? String) : nil
        let attachments: [[String: Any]]? = includeAttachments ? attachmentsForNote(note: note, noteId: noteId, includeShared: true) : nil

        return [
            "note": [
                "note_id": noteId,
                "folder_id": folderId,
                "name": name,
                "creation_date": formatISO8601Date(created),
                "modification_date": formatISO8601Date(modified),
                "is_password_protected": isPasswordProtected,
                "is_shared": isShared,
                "plaintext": plaintext as Any,
                "body_html": bodyHTML as Any,
                "attachments": attachments as Any
            ]
        ]
    }

    private static func attachmentsForNote(note: SBObject, noteId: String, includeShared: Bool) -> [[String: Any]] {
        guard let atts = note.value(forKey: "attachments") as? SBElementArray else {
            return []
        }
        return (0..<atts.count).compactMap { idx in
            guard let attRef = atts.object(at: idx) as? SBObject,
                  let att = try? resolveObject(attRef, notFoundCode: "INTERNAL") else {
                return nil
            }
            if !includeShared && boolValue(att.value(forKey: "shared")) {
                return nil
            }
            return attachmentDict(att, noteId: noteId)
        }
    }

    private static func attachmentDict(_ att: SBObject, noteId: String) -> [String: Any] {
        let attachmentId = stringValue(att.value(forKey: "id"))
        let name = (att.value(forKey: "name") as? String) ?? ""
        let cid = (att.value(forKey: "contentIdentifier") as? String) ?? ""
        let created = (att.value(forKey: "creationDate") as? Date) ?? Date(timeIntervalSince1970: 0)
        let modified = (att.value(forKey: "modificationDate") as? Date) ?? Date(timeIntervalSince1970: 0)
        let url = att.value(forKey: "URL") as? String
        let isShared = boolValue(att.value(forKey: "shared"))

        return [
            "attachment_id": attachmentId,
            "note_id": noteId,
            "name": name,
            "content_identifier": cid,
            "creation_date": formatISO8601Date(created),
            "modification_date": formatISO8601Date(modified),
            "url": url as Any,
            "is_shared": isShared
        ]
    }

    private static func foldersUnder(
        folder: SBObject,
        containerType: String,
        containerId: String,
        recursive: Bool,
        includeShared: Bool,
        includeRecentlyDeleted: Bool
    ) throws -> [[String: Any]] {
        guard let children = folder.value(forKey: "folders") as? SBElementArray else {
            return []
        }

        var out: [[String: Any]] = []
        for idx in 0..<children.count {
            guard let child = children.object(at: idx) as? SBObject else {
                continue
            }
            out.append(contentsOf: try folderAndMaybeDescendants(
                folder: child,
                containerType: containerType,
                containerId: containerId,
                recursive: recursive,
                includeShared: includeShared,
                includeRecentlyDeleted: includeRecentlyDeleted
            ))
        }
        return out
    }

    private static func folderAndMaybeDescendants(
        folder: SBObject,
        containerType: String,
        containerId: String,
        recursive: Bool,
        includeShared: Bool,
        includeRecentlyDeleted: Bool
    ) throws -> [[String: Any]] {
        let name = stringValue(folder.value(forKey: "name"))
        if !includeRecentlyDeleted && isRecentlyDeletedFolderName(name) {
            return []
        }

        let isShared = boolValue(folder.value(forKey: "shared"))
        if isShared && !includeShared {
            return []
        }

        let folderId = stringValue(folder.value(forKey: "id"))
        var out: [[String: Any]] = [[
            "folder_id": folderId,
            "name": name,
            "is_shared": isShared,
            "container": ["type": containerType, "id": containerId]
        ]]

        if recursive {
            out.append(contentsOf: try foldersUnder(
                folder: folder,
                containerType: "folder",
                containerId: folderId,
                recursive: true,
                includeShared: includeShared,
                includeRecentlyDeleted: includeRecentlyDeleted
            ))
        }
        return out
    }

    private static func buildFolderAccountMap(app: SBApplication) throws -> [String: String] {
        guard let accounts = app.value(forKey: "accounts") as? SBElementArray else {
            throw SimpleSidecarError(code: "INTERNAL", message: "Failed to list accounts.")
        }

        var out: [String: String] = [:]
        for idx in 0..<accounts.count {
            guard let acc = accounts.object(at: idx) as? SBObject else {
                continue
            }
            let accId = stringValue(acc.value(forKey: "id"))
            guard let folders = acc.value(forKey: "folders") as? SBElementArray else {
                continue
            }
            for jdx in 0..<folders.count {
                guard let folder = folders.object(at: jdx) as? SBObject else {
                    continue
                }
                walkFolderAccountMap(folder: folder, accountId: accId, out: &out)
            }
        }
        return out
    }

    private static func walkFolderAccountMap(folder: SBObject, accountId: String, out: inout [String: String]) {
        let folderId = stringValue(folder.value(forKey: "id"))
        if !folderId.isEmpty {
            out[folderId] = accountId
        }
        if let children = folder.value(forKey: "folders") as? SBElementArray {
            for idx in 0..<children.count {
                guard let child = children.object(at: idx) as? SBObject else {
                    continue
                }
                walkFolderAccountMap(folder: child, accountId: accountId, out: &out)
            }
        }
    }

    private static func stringValue(_ any: Any?) -> String {
        if let s = any as? String {
            return s
        }
        return ""
    }

    private static func boolValue(_ any: Any?) -> Bool {
        if let b = any as? Bool {
            return b
        }
        if let n = any as? NSNumber {
            return n.boolValue
        }
        return false
    }

    private static func mapScriptingBridgeError(_ error: Error, notFoundCode: String) -> SimpleSidecarError {
        let ns = error as NSError
        let code = ns.code
        let message = ns.localizedDescription

        switch code {
        case -1743:
            return SimpleSidecarError(code: "NOT_AUTHORIZED", message: "Automation permission denied for Notes.app.")
        case -1719, -1728:
            return SimpleSidecarError(code: notFoundCode, message: message)
        default:
            return SimpleSidecarError(code: "INTERNAL", message: message)
        }
    }

    private static func throwIfLastError(_ obj: SBObject, fallback: SimpleSidecarError) throws {
        if let err = obj.lastError() {
            throw mapScriptingBridgeError(err, notFoundCode: fallback.code)
        }
    }

    private struct NoteCandidate: Comparable {
        let note: SBObject
        let noteId: String
        let folderId: String
        let name: String
        let creationDate: Date
        let modificationDate: Date
        let isPasswordProtected: Bool
        let isShared: Bool
        let attachmentCount: Int

        static func < (lhs: NoteCandidate, rhs: NoteCandidate) -> Bool {
            if lhs.modificationDate != rhs.modificationDate {
                return lhs.modificationDate > rhs.modificationDate
            }
            let cmp = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            if cmp != .orderedSame {
                return cmp == .orderedAscending
            }
            return lhs.noteId < rhs.noteId
        }
    }

    // MARK: - AppleScript helpers (for creation & attachments)

    private static func createNoteAppleScript(folderId: String?, title: String?) throws -> String {
        var lines: [String] = []
        lines.append("tell application \"Notes\"")
        if let folderId {
            lines.append("set theFolder to first folder whose id is \(appleScriptStringLiteral(folderId))")
        } else {
            lines.append("set theAccount to default account")
            lines.append("set theFolder to default folder of theAccount")
        }

        if let title {
            lines.append("set theNote to make new note at theFolder with properties {name:\(appleScriptStringLiteral(title))}")
        } else {
            lines.append("set theNote to make new note at theFolder")
        }

        lines.append("return id of theNote")
        lines.append("end tell")

        let result = try runAppleScript(lines.joined(separator: "\n"))
        let noteId = result.stringValue ?? ""
        if noteId.isEmpty {
            throw SimpleSidecarError(code: "INTERNAL", message: "Notes.app returned an empty note identifier.")
        }
        return noteId
    }

    private static func deleteNoteAppleScript(noteId: String) throws -> String {
        let script = """
        tell application "Notes"
            set theNote to first note whose id is \(appleScriptStringLiteral(noteId))
            delete theNote
            return \(appleScriptStringLiteral(noteId))
        end tell
        """
        let result = try runAppleScript(script)
        return result.stringValue ?? noteId
    }

    private static func addAttachmentsAppleScript(noteId: String, filePaths: [String]) throws -> [String] {
        var lines: [String] = []
        lines.append("tell application \"Notes\"")
        lines.append("set theNote to first note whose id is \(appleScriptStringLiteral(noteId))")
        lines.append("set outIds to {}")
        for (idx, path) in filePaths.enumerated() {
            let varName = "a\(idx)"
            lines.append("set \(varName) to make new attachment at end of attachments of theNote with data (POSIX file \(appleScriptStringLiteral(path)))")
            lines.append("copy id of \(varName) to end of outIds")
        }
        lines.append("return outIds")
        lines.append("end tell")

        let result = try runAppleScript(lines.joined(separator: "\n"))
        return appleEventDescriptorStringList(result)
    }

    private static func saveAttachmentAppleScript(attachmentId: String, outputPath: String) throws -> String {
        let script = """
        tell application "Notes"
            set theAtt to first attachment whose id is \(appleScriptStringLiteral(attachmentId))
            save theAtt in (POSIX file \(appleScriptStringLiteral(outputPath)))
            return \(appleScriptStringLiteral(outputPath))
        end tell
        """
        let result = try runAppleScript(script)
        return result.stringValue ?? outputPath
    }

    private static func appleEventDescriptorStringList(_ desc: NSAppleEventDescriptor) -> [String] {
        // Apple event lists are 1-indexed.
        if desc.descriptorType == typeAEList {
            return (1...desc.numberOfItems).compactMap { idx in
                desc.atIndex(idx)?.stringValue
            }
        }
        if let s = desc.stringValue, !s.isEmpty {
            return [s]
        }
        return []
    }
}
