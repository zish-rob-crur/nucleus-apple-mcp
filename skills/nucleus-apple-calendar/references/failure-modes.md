# Calendar Failure Modes

## Ambiguous Calendars and Events

- Never mutate by title alone.
- The same calendar title can exist under multiple sources; pair title with source when destination matters.
- Duplicate event titles in the same window require time or detail-based disambiguation.
- If several plausible events remain, run another read instead of guessing.

## Read-Only and Hidden Calendars

- Hidden calendars are excluded by default; absence from the first read is not proof that the calendar does not exist.
- Subscribed or otherwise read-only calendars can list events but reject mutations.
- A move can fail even if the current event is writable when the target calendar is not writable.

## Recurring Scope Mistakes

- `--span future` edits the series from the selected instance forward; do not use it for one-off fixes.
- A user asking to "move tomorrow's standup" usually means one instance, not the whole series.
- After a recurring edit, re-read the nearby window instead of trusting pre-edit identifiers.

## Timezone and All-Day Drift

- Date-only user language can hide timezone intent; do not rewrite explicit offsets.
- All-day events can appear shifted if inspected with the wrong timezone assumption.
- When changing only `start` or `end`, ensure the resulting event still satisfies `start < end`.

## Identifier Churn

- `event_id` is opaque and can change across sync or recurring edits.
- If a follow-up mutation fails with `NOT_FOUND`, re-locate the event in the relevant time window before retrying.
