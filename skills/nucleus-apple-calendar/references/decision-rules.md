# Calendar Decision Rules

Load this file for any non-trivial calendar task.

## Intent Router

- Use `list-sources` when the request mentions an account or provider, such as "iCloud", "Google", or "work calendar".
- Use `list-calendars` when the user needs a writable destination or only names a calendar title.
- Use `list-events` for availability checks, schedule questions, and event lookup inside a time window.
- Use `create-event`, `update-event`, or `delete-event` only after the exact `calendar_id` or `event_id` is known.

## Scope Discovery

- If the destination calendar is already known, skip `list-sources`.
- If a calendar title is ambiguous or likely duplicated across providers, resolve `source_id` first and then narrow calendars under that source.
- If the task is "what is on my calendar this afternoon?" or "am I free tomorrow at 3?", start with the smallest time window that covers the request.
- If the task involves moving an event, identify the target writable calendar before touching the event.

## Inspection Rules

- Availability or schedule questions: use `list-events` with an exact `--start` and `--end` window.
- Event lookup by rough title or approximate time: inspect a narrow window around the expected start time rather than the whole calendar.
- Add `--include-details` only when location, notes, URL, or duplicate-title disambiguation matters.
- If the first read returns several plausible events, rerun `list-events` with a tighter window or stronger calendar scope.

## Mutation Rules

- Create events only after a writable `calendar_id` is chosen.
- Update a single event with `update-event`; use `--calendar-id` on the update only when moving the event to another writable calendar.
- Delete only after the exact `event_id` is confirmed from a read.
- If one field change solves the task, mutate only that field instead of reconstructing the whole event.

## Recurring and Time Rules

- Default recurring edits to `--span this`.
- Use `--span future` only for explicit series language such as "all future", "from now on", or "this recurring meeting going forward".
- Preserve explicit timezone offsets from the user instead of rewriting them to local time.
- Treat all-day changes as time-sensitive mutations: inspect the event before and after toggling all-day state.
- When date-only language could mean either all-day or timed, inspect the existing event shape before changing it.

## Confirmation Rules

- Re-read the affected event window after create, move, recurring edits, and all-day changes.
- Prefer the returned event payload after mutation, but do not assume an old `event_id` stays stable after sync or recurring operations.
