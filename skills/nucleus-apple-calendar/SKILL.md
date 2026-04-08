---
name: nucleus-apple-calendar
description: Manage Apple Calendar on macOS with the `nucleus-apple` CLI. Use when the task involves checking availability, listing event windows, creating events, editing one event or future recurring events, moving events across calendars, or deleting Calendar events.
metadata: {"openclaw":{"emoji":"📅","homepage":"https://github.com/zish-rob-crur/nucleus-apple-mcp","os":["darwin"],"requires":{"anyBins":["nucleus-apple","uvx"]},"install":[{"id":"uv","kind":"uv","package":"nucleus-apple-mcp","bins":["nucleus-apple"],"label":"Install nucleus-apple (uv)"}]}}
---

Use `nucleus-apple calendar ...` to inspect, schedule, and mutate Apple Calendar data.

## Operating Stance

- Prefer the installed `nucleus-apple` binary.
- Fall back to `uvx --from nucleus-apple-mcp nucleus-apple ...` when only `uvx` is available.
- Keep reads narrow: exact time windows first, source or calendar filters when provider choice matters.
- Default recurring edits to `--span this`; widen to `--span future` only for explicit series changes.
- Preserve explicit timezone offsets from the request.
- Re-read the affected window after mutations that can change IDs or recurrence scope.

## Core Workflow

1. Resolve source or calendar scope only as far as the task requires.
2. Inspect the smallest event window that can answer the question or identify the target event.
3. Choose the mutation path from `references/decision-rules.md`.
4. Use `references/commands.md` for canonical command shapes.
5. Use `references/failure-modes.md` when results are ambiguous or a writable target is unclear.

## Task Routing

- Availability or "what is on my calendar" questions: read `references/decision-rules.md#inspection-rules`.
- Single-event create, edit, move, or delete: read `references/decision-rules.md#mutation-rules`.
- Recurring-series edits, timezone-sensitive requests, or all-day changes: read `references/decision-rules.md#recurring-and-time-rules`.
- Duplicate titles, read-only calendars, hidden calendars, or post-edit identifier churn: read `references/failure-modes.md`.

## Output / Escalation

- Use `--pretty` only for human inspection.
- Omit `--pretty` when another tool or script will parse the JSON.
- Add `--include-details` only when the task depends on location, notes, URL, or event disambiguation.
