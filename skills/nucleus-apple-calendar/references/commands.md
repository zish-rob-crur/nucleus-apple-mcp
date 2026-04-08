# Calendar Command Patterns

If only `uvx` is available, replace each `nucleus-apple` prefix with `uvx --from nucleus-apple-mcp nucleus-apple`.

## Discovery

```bash
nucleus-apple calendar list-sources --pretty
nucleus-apple calendar list-calendars --pretty
nucleus-apple calendar list-calendars --source-id SOURCE_ID --pretty
```

Use discovery commands before create or move operations when the destination calendar is unclear.

## Inspection

```bash
nucleus-apple calendar list-events \
  --start 2026-03-15T09:00:00+08:00 \
  --end 2026-03-15T18:00:00+08:00 \
  --include-details \
  --pretty
```

Use `--include-details` when the user cares about location, notes, or URLs.

## Mutation

```bash
nucleus-apple calendar create-event \
  --calendar-id CALENDAR_ID \
  --title "Design review" \
  --start 2026-03-15T14:00:00+08:00 \
  --end 2026-03-15T15:00:00+08:00 \
  --pretty

nucleus-apple calendar update-event \
  --event-id EVENT_ID \
  --title "Updated title" \
  --calendar-id OTHER_CALENDAR_ID \
  --pretty

nucleus-apple calendar update-event \
  --event-id EVENT_ID \
  --span future \
  --title "New recurring title" \
  --pretty

nucleus-apple calendar delete-event --event-id EVENT_ID
```

Inspect the original event first when editing or deleting user data. Use `--span future` only for explicit recurring-series changes.
