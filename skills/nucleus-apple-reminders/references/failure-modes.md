# Reminders Failure Modes

## Hidden and Read-Only Lists

- Hidden lists are excluded by default, so absence from the first read is not proof that the list does not exist.
- Read-only or subscribed lists can be listed but reject mutations.
- A move can fail if the target list is not writable even when the current reminder is writable.

## Date Boundary Surprises

- Date-only `due-end` and `end` are whole-day upper bounds in user intent, not narrow midnight checks.
- Mixing date-only and datetime filters can surface timezone surprises.
- If both start and due filters are present, the intersection can be much smaller than expected.

## Null Date Fields

- Reminders without `due` or `start` disappear when filtering on that field.
- Missing `due` or `start` is different from overdue or open.
- If null-date reminders should stay visible, broaden the query instead of tightening filters.

## Status Ordering

- `--status all` sorts open reminders before completed ones, then sorts by due, start, title, and ID.
- `limit` is applied after sorting, so completed items can drop out first.
- Use a narrower date or list filter if the expected reminder is not visible inside a limited mixed-status query.

## Reopen and Delete Confusion

- `--no-completed` reopens the same reminder; it does not clone it.
- Delete is not a substitute for "mark done".
- Title-only matches are unsafe for destructive operations; read first and mutate by `reminder_id`.
