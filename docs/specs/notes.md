# Notes Module Spec (v0)

This document defines the "playbook" for the Notes module: scope, commands, parameters, return schema, and error conventions. Implementations should follow this spec.

## 1. Scope & Constraints

- Controls macOS **Notes.app** via **Apple Events / AppleScript** (Notes scripting dictionary). No direct access to the private Notes database.
- Supports listing **accounts**, **folders** (including nested folders), **notes**, and **attachments** metadata.
- v0 focuses on **text-first** workflows:
  - Notes are stored as **HTML** (`note.body`) and also expose **read-only plaintext** (`note.plaintext`).
  - v0 supports create/update via **plaintext** (converted to simple HTML) or **Markdown** (converted to HTML).
  - v0 does **not** accept raw HTML writes from callers (no `set-body-html` style escape hatch).
- Markdown support is intended for a pragmatic subset (headings, lists, links, code blocks). The exact HTML emitted is an implementation detail and may change across releases.
- Editing complex rich content (tables, drawings, embedded files/images) is inherently fragile:
  - Replacing note content may break embedded objects or detach them from the note.
  - v0 provides **append** operations that are best-effort but still may not preserve all formatting.
- Notes contains a system folder named **"Recently Deleted"** (localized). v0 excludes it from list results by default.
- **Password-protected notes**:
  - Can be listed as metadata, but **content access is denied**. v0 returns `LOCKED` for content reads and rejects updates.
- **Shared folders/notes**:
  - v0 treats shared content as **read-only** and rejects mutations with `NOT_WRITABLE`.
- Attachments:
  - v0 supports **listing**, **exporting**, and **adding** attachments to a note from local files.
  - Deleting attachments is out of scope for v0.

### 1.1 Operational & Safety Notes

- UI behavior:
  - Implementations should avoid stealing focus (e.g. do not `activate` Notes.app) and should not require the user to keep Notes open.
  - Notes.app may still briefly open or update UI due to system behavior; this is acceptable for v0.
- Concurrency:
  - Apple Events interactions should be treated as **not concurrency-safe**.
  - Implementations should serialize Notes operations (single-flight) to reduce flaky AppleScript timeouts.
- Destructive edits:
  - `--set-plaintext` / `--set-markdown` are considered **destructive** operations and may remove rich formatting or break attachment embedding.
  - v0 requires explicit opt-in via `--allow-destructive` when performing destructive edits.
  - `--append-*` operations are preferred for preserving existing content.
- String escaping & payload size:
  - Note bodies can contain quotes, backslashes, and large payloads; implementations must avoid naive string interpolation into AppleScript.
  - Recommended: pass content via temporary files or other robust mechanisms to avoid AppleScript escaping/length limits.
- Markdown:
  - Markdown is converted to safe HTML. Raw HTML in Markdown must not be interpreted.
  - Link sanitization is implementation-defined; no remote content should be fetched.
- Plaintext search:
  - When `--query` is provided, implementations may need to fetch note plaintext and can be slower on large libraries.
  - To reduce work, implementations should evaluate plaintext matches lazily in the output order and stop after collecting `limit` matches.

## 2. Terminology

- **Account**: a Notes account container.
- **Folder**: a folder (may be nested under another folder or directly under an account).
- **Note**: a note item.
- **Attachment**: an attachment belonging to a note (images, PDFs, URL attachments, etc).

## 3. Permissions (macOS)

This module requires **Automation** permission to control Notes.app via Apple Events.

- On first use, macOS may prompt: "`<process>` wants to control Notes".
- When permission is not granted / denied, commands must return `ok=false` with `error.code=NOT_AUTHORIZED`.

## 4. Invocation Protocol (CLI only; no custom stdio protocol)

This project uses a sidecar **CLI** as the single protocol.

### 4.1 Output Convention

- Success: stdout prints a single JSON line:
  - `{"ok": true, "result": ...}`
- Failure: stdout prints a single JSON line and exits non-zero:
  - `{"ok": false, "error": {"code": "...", "message": "..."}}`
- Help output such as `--help/-h` is human-readable and not required to be JSON.

### 4.2 Error Codes (v0)

- `INVALID_ARGUMENTS`: invalid params / parse failure.
- `NOT_AUTHORIZED`: permission not granted / denied (Automation / Apple Events).
- `NOT_FOUND`: `account_id`, `folder_id`, `note_id`, or `attachment_id` not found.
- `LOCKED`: the target note is password protected.
- `NOT_WRITABLE`: shared content or otherwise not writable.
- `INTERNAL`: runtime exception (unknown error, serialization failure, AppleScript error not mapped above, etc.).

## 5. Data Models

Time format: ISO-8601 with timezone offset, e.g. `2026-01-27T20:21:54-08:00`.

### 5.1 Account

- `account_id` (string, opaque)
- `name` (string)
- `upgraded` (bool)
- `default_folder_id` (string, opaque|null)

### 5.2 Folder

- `folder_id` (string, opaque)
- `name` (string)
- `is_shared` (bool)
- `container` (object):
  - `type` (string enum): `account | folder`
  - `id` (string, opaque)

### 5.3 NoteSummary (list output)

- `note_id` (string, opaque; may change across sync/edit)
- `folder_id` (string, opaque)
- `name` (string)
- `creation_date` (string, ISO-8601)
- `modification_date` (string, ISO-8601)
- `is_password_protected` (bool)
- `is_shared` (bool)
- `attachment_count` (int)
- `plaintext_excerpt` (string|null): optional, present only when requested; may be truncated

### 5.4 NoteDetail (get/create/update output)

- `note_id` (string, opaque)
- `folder_id` (string, opaque)
- `name` (string)
- `creation_date` (string, ISO-8601)
- `modification_date` (string, ISO-8601)
- `is_password_protected` (bool)
- `is_shared` (bool)
- `plaintext` (string|null): optional
- `body_html` (string|null): optional (HTML)
- `attachments` (Attachment[]|null): optional

### 5.5 Attachment

- `attachment_id` (string, opaque)
- `note_id` (string, opaque)
- `name` (string)
- `content_identifier` (string): the content-id URL referenced in note HTML
- `creation_date` (string, ISO-8601)
- `modification_date` (string, ISO-8601)
- `url` (string|null): for URL attachments
- `is_shared` (bool)

## 6. Sidecar CLI (Swift) Commands

Notes commands live under the `notes` command group.

### 6.1 `notes accounts`

List Notes accounts.

Return:

- `{"accounts": Account[]}`

### 6.2 `notes folders`

List folders.

Options:

- `--account-id <id>` (repeatable; optional): limit to folders under the given account(s).
- `--parent-folder-id <id>` (optional): limit to direct children of a specific folder.
- `--recursive` (bool flag, default: false): when set, returns the entire subtree under the filter.
- `--include-shared` (bool flag, default: false): include shared folders.
- `--include-recently-deleted` (bool flag, default: false): include the system "Recently Deleted" folder (localized).

Return:

- `{"folders": Folder[]}`

Notes:

- If neither `--account-id` nor `--parent-folder-id` is provided, returns all top-level folders from all accounts (excluding shared unless `--include-shared`).
- Implementations should detect "Recently Deleted" by name across common localizations (best-effort).

### 6.3 `notes notes`

List notes (metadata-first).

Options:

- `--account-id <id>` (repeatable; optional): limit to notes under the given account(s).
- `--folder-id <id>` (repeatable; optional): limit to notes under the given folder(s).
- `--query <text>` (optional): case-insensitive substring match against note `name` **or** `plaintext`.
- `--include-plaintext-excerpt` (bool flag, default: false)
- `--plaintext-excerpt-max-len <n>` (optional; default: 200; must be > 0)
- `--include-shared` (bool flag, default: false): include shared notes.
- `--include-recently-deleted` (bool flag, default: false): include notes under the system "Recently Deleted" folder (localized).
- `--limit <n>` (optional; default: 200; must be > 0)

Return:

- `{"notes": NoteSummary[]}`

Sorting (stable output):

- `modification_date` descending, then `name` (case-insensitive), then `note_id`.

Notes:

- Password-protected notes are included in listing, but `plaintext_excerpt` must be `null` and they must never match the plaintext portion of `--query`.
- Plaintext searching may require fetching note plaintext and can be slower on large libraries; implementations should evaluate matches lazily in sorted order and stop after `limit` matches.

### 6.4 `notes get-note`

Fetch a note with optional content and attachments.

Options:

- `--note-id <id>` (required)
- `--include-plaintext` (bool flag, default: true)
- `--include-body-html` (bool flag, default: false)
- `--include-attachments` (bool flag, default: true)

Return:

- `{"note": NoteDetail}`

Errors:

- If the note is password protected: `LOCKED`.

### 6.5 `notes create-note`

Create a new note.

Options:

- `--folder-id <id>` (optional): if omitted, uses the Notes.app default account + default folder.
- `--title <text>` (optional)
- `--plaintext <text>` (optional)
- `--markdown <text>` (optional)
- `--attach-file <path>` (repeatable; optional): add one or more attachments after note creation.

Mutual exclusion:

- At most one of `--plaintext` and `--markdown` may be provided.

Return:

- `{"note": NoteDetail}` (by default: includes `plaintext=true`, `body_html=false`, `attachments=true`)

### 6.6 `notes update-note`

Update an existing note.

Options:

- `--note-id <id>` (required)
- `--title <text>` (optional)
- `--allow-destructive` (bool flag, default: false): required when using `--set-plaintext` or `--set-markdown`.

Content update modes (provide at most one):

- `--set-plaintext <text>`: replace note content with plaintext (converted to simple HTML).
- `--set-markdown <text>`: replace note content with Markdown (converted to HTML).
- `--append-plaintext <text>`: append plaintext to the end of the note (best-effort).
- `--append-markdown <text>`: append Markdown to the end of the note (best-effort).
- `--attach-file <path>` (repeatable; optional): add one or more attachments to the note.

Validation:

- Must provide at least one updatable field.
- If `--set-plaintext` or `--set-markdown` is provided, `--allow-destructive` must be set; otherwise `INVALID_ARGUMENTS`.

Return:

- `{"note": NoteDetail}` (by default: includes `plaintext=true`, `body_html=false`, `attachments=true`)

Errors:

- If the note is password protected: `LOCKED`.
- If the note is shared: `NOT_WRITABLE`.

### 6.7 `notes delete-note`

Delete a note.

Options:

- `--note-id <id>` (required)

Return:

- `{"deleted_note_id": "<id>"}`

### 6.8 `notes attachments`

List attachments for a note.

Options:

- `--note-id <id>` (required)
- `--include-shared` (bool flag, default: false)

Return:

- `{"attachments": Attachment[]}`

Errors:

- If the note is password protected: `LOCKED`.

### 6.9 `notes save-attachment`

Export an attachment to a file path.

Options:

- `--attachment-id <id>` (required)
- `--output-path <path>` (required)
- `--overwrite` (bool flag, default: false)

Return:

- `{"output_path": "<path>"}` (the final written path)

### 6.10 `notes add-attachment`

Add attachment(s) to a note from local file paths.

Options:

- `--note-id <id>` (required)
- `--attach-file <path>` (repeatable; required): one or more local file paths to attach.

Return:

- `{"attachments": Attachment[]}` (attachments created; order matches input paths when possible)

Notes:

- Notes.app decides how attachments are embedded in the note UI/body.
- This operation is best-effort; some file types may be represented as URL attachments or may fail to import.
- Validation:
  - Each `--attach-file` must exist and be a regular file; directories are rejected with `INVALID_ARGUMENTS`.

## Appendix A. References (for implementers)

- Notes.app scripting dictionary:
  - Use `sdef /System/Applications/Notes.app` (macOS) to inspect the Apple Events surface area (accounts, folders, notes, attachments, properties like `body` and `plaintext`).
- Reference project (Apple Notes CLI):
  - `memo` by `antoniorodr`: <https://github.com/antoniorodr/memo>
  - Helpful patterns to study:
    - Excluding the localized "Recently Deleted" folder (see its multi-locale name list approach).
    - Warning users before destructive edits/moves when HTML indicates images/attachments.
