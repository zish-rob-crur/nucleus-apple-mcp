# Notes Failure Modes

## Locked and Shared Notes

- Password-protected notes can appear in listings but content reads and updates fail with `LOCKED`.
- Shared folders and shared notes should be treated as read-only for mutations.
- A search hit is not enough to prove that the note is writable.

## Destructive Rewrite Risks

- `--set-plaintext` and `--set-markdown` can strip formatting or detach embedded content.
- `append-*` is still best-effort, but it is less risky than replacing the entire body.
- Raw HTML writes are out of scope; do not invent a direct HTML write path.

## Query and Excerpt Costs

- `--query` matches title or plaintext, and plaintext matching can be slower on large libraries.
- Password-protected notes do not match the plaintext portion of a query.
- `plaintext_excerpt` can be `null` for locked notes.

## Visibility and Folder Pitfalls

- Recently Deleted is excluded by default and localized by the system.
- Shared folders and notes are excluded by default.
- Notes can live inside nested folders; do not assume every folder filter is top-level.

## Identifier and Attachment Ambiguity

- `note_id` is opaque and may change across sync or edits.
- Attachment export operates on `attachment_id`, not a guessed filename.
- Re-list attachments after changes if a follow-up action depends on exact attachment IDs.
