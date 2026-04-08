# Reminders Decision Rules

Load this file for anything more complex than reading one known reminder by ID.

## Intent Router

- Use `list-sources` when the request mentions a provider or account.
- Use `list-lists` when the destination list is unknown or a list title may be ambiguous.
- Use `list-reminders` for all due-date, start-date, status, and list-based queries.
- Use `update-reminder` for edits, list moves, field clearing, completion, and reopening.

## Scope Discovery

- If the list is already known, skip `list-sources`.
- If provider or account matters, narrow by `source_id` before choosing a list.
- If the user asks across all reminders, omit list filters and rely on date or status filters first.
- If moving a reminder, confirm the target list before editing the reminder.

## Date Filtering

- Use `due-start` and `due-end` for deadline questions.
- Use `start` and `end` for scheduled-start questions.
- Preserve date-only input when the user spoke in date-only terms.
- When both start-based and due-based filters are present, expect the intersection.
- Reminders with null `due` or `start` drop out when that field is filtered.
- Use `--status all` only when the user explicitly wants open and completed items together.

## Mutation Choice

- Use `create-reminder` when the destination list is known and writable.
- Use `update-reminder` for title, dates, notes, URL, priority, list move, and `clear-*` operations.
- Use `clear-*` to remove a field instead of rewriting the whole reminder.
- Move with `--list-id` only after the target list is confirmed writable.

## Completion vs Deletion

- Complete with `--completed` when the task is "done", "finished", or "check this off".
- Reopen with `--no-completed` when the user wants the item active again.
- Delete only for explicit removal or cleanup requests.
- After completion, reopening, moving, or deleting, rerun the relevant `list-reminders` filter if confirmation matters.
