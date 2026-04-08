---
name: nucleus-apple-notes
description: Manage Apple Notes on macOS with the `nucleus-apple` CLI. Use when the task involves searching notes, scoping by account or folder, reading note bodies, creating notes, appending or replacing note content, or adding and exporting note attachments.
metadata: {"openclaw":{"emoji":"📝","homepage":"https://github.com/zish-rob-crur/nucleus-apple-mcp","os":["darwin"],"requires":{"anyBins":["nucleus-apple","uvx"]},"install":[{"id":"uv","kind":"uv","package":"nucleus-apple-mcp","bins":["nucleus-apple"],"label":"Install nucleus-apple (uv)"}]}}
---

Use `nucleus-apple notes ...` to search, read, update, and attach files to Apple Notes data.

## Operating Stance

- Prefer the installed `nucleus-apple` binary.
- Fall back to `uvx --from nucleus-apple-mcp nucleus-apple ...` when only `uvx` is available.
- Narrow search by folder or account when that scope is already known.
- Read the note before destructive rewrites, attachment export, or ambiguous updates.
- Prefer append operations for incremental edits; use destructive set operations only for explicit replacement or format conversion.
- Include shared or recently deleted content only when the task explicitly asks for it.
- Re-read the note after destructive writes or attachment changes when follow-up actions depend on current content.

## Core Workflow

1. Resolve account, folder, or note scope only as far as the task requires.
2. Inspect current note state before risky edits or attachment work.
3. Choose create vs append vs destructive set from `references/decision-rules.md`.
4. Use `references/commands.md` for canonical command shapes.
5. Use `references/failure-modes.md` when notes are locked, shared, or still ambiguous after search.

## Task Routing

- Search by text, folder, or note ID: read `references/decision-rules.md#scope-and-search`.
- Choose append vs replace body: read `references/decision-rules.md#mutation-choice`.
- Export or add attachments: read `references/decision-rules.md#attachment-workflow`.
- Locked notes, shared notes, expensive plaintext search, or rewrite risk: read `references/failure-modes.md`.

## Output / Escalation

- Use `--pretty` for human inspection.
- Use `--include-body-html` only when formatting or embedded attachment anchors matter.
- Use `--allow-destructive` only alongside `--set-plaintext` or `--set-markdown`.
