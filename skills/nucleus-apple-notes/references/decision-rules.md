# Notes Decision Rules

Load this file for anything more complex than reading one known note by ID.

## Intent Router

- Use `create-note` when the task is to make a new note.
- Use `list-notes` when the target note is described by title, query text, folder, or account rather than a known ID.
- Use `get-note` when `note_id` is already known or the task depends on current note content.
- Use attachment commands only after the target note or attachment has been identified exactly.

## Scope and Search

- If account or folder is known, narrow `list-notes` with that scope before adding `--query`.
- Use `--include-plaintext-excerpt` when snippets help disambiguate search results.
- Shared notes and Recently Deleted content are excluded by default; widen scope only when explicitly requested.
- If several notes still match, inspect note metadata before loading full note bodies.

## Read Before Write

- Call `get-note` before destructive `set-*` operations.
- Call `get-note` before exporting attachments if the target note may contain multiple files.
- Request `--include-body-html` only when formatting or embedded attachment anchors matter.
- Plaintext alone is usually enough for summary or append tasks.

## Mutation Choice

- Use `create-note` for new notes, with `--folder-id` when the destination folder is known.
- Use `--append-plaintext` or `--append-markdown` for incremental additions.
- Use `--set-plaintext` or `--set-markdown` with `--allow-destructive` only when replacing the body is intentional.
- Use Markdown when structure matters; use plaintext for literal text additions or minimal edits.

## Attachment Workflow

- Use `list-attachments` when `attachment_id` is unknown.
- Use `save-attachment` only after selecting the exact attachment to export.
- Use `add-attachment` after the target note is confirmed; do not rewrite note content just to add a file.
- Re-read the note or attachment list after destructive rewrites or attachment changes when a follow-up action depends on fresh IDs.
