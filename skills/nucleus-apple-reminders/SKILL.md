---
name: nucleus-apple-reminders
description: Manage Apple Reminders on macOS with the `nucleus-apple` CLI. Use when the task involves filtering reminders by due or start dates, listing reminder lists, creating reminders, editing or moving reminders, marking them complete or incomplete, or deleting reminders.
metadata: {"openclaw":{"emoji":"✅","homepage":"https://github.com/zish-rob-crur/nucleus-apple-mcp","os":["darwin"],"requires":{"anyBins":["nucleus-apple","uvx"]},"install":[{"id":"uv","kind":"uv","package":"nucleus-apple-mcp","bins":["nucleus-apple"],"label":"Install nucleus-apple (uv)"}]}}
---

Use `nucleus-apple reminders ...` to inspect and mutate Apple Reminders data.

## Operating Stance

- Prefer the installed `nucleus-apple` binary.
- Fall back to `uvx --from nucleus-apple-mcp nucleus-apple ...` when only `uvx` is available.
- Prefer exact due or start windows and list filters over broad all-list reads when scope is known.
- Treat completion as the default state-changing operation; delete only for explicit removal.
- Read current reminder state before mutating ambiguous titles.
- Preserve date-only vs datetime semantics from the request.
- Re-read the affected query after moves, completion changes, and deletes when confirmation matters.

## Core Workflow

1. Resolve source or list scope only as far as the task requires.
2. Inspect reminders with the relevant date and status filters.
3. Choose create vs update vs complete vs delete from `references/decision-rules.md`.
4. Use `references/commands.md` for canonical command shapes.
5. Use `references/failure-modes.md` when date boundaries, hidden lists, or null due or start fields matter.

## Task Routing

- Due or start filtering, open vs completed views: read `references/decision-rules.md#date-filtering`.
- Create, edit, or move reminders: read `references/decision-rules.md#mutation-choice`.
- Mark complete, reopen, or delete: read `references/decision-rules.md#completion-vs-deletion`.
- Hidden lists, date-only surprises, status ordering, or null date fields: read `references/failure-modes.md`.

## Output / Escalation

- Use `--pretty` only for human inspection.
- Use `--status all` when the user cares about both open and completed reminders.
- Prefer `--clear-*` or `--no-completed` over reconstructing the full reminder payload.
