# Reminders Command Patterns

If only `uvx` is available, replace each `nucleus-apple` prefix with `uvx --from nucleus-apple-mcp nucleus-apple`.

## Discovery

```bash
nucleus-apple reminders list-sources --pretty
nucleus-apple reminders list-lists --pretty
nucleus-apple reminders list-reminders --due-end 2026-03-20 --status open --pretty
nucleus-apple reminders list-reminders --status all --pretty
```

Use `--status all` when the user cares about both completed and open reminders.

## Mutation

```bash
nucleus-apple reminders create-reminder \
  --list-id LIST_ID \
  --title "Buy milk" \
  --due 2026-03-20 \
  --pretty

nucleus-apple reminders update-reminder \
  --reminder-id REMINDER_ID \
  --title "Buy oat milk" \
  --due 2026-03-21 \
  --priority 5 \
  --pretty

nucleus-apple reminders update-reminder \
  --reminder-id REMINDER_ID \
  --completed \
  --pretty

nucleus-apple reminders update-reminder \
  --reminder-id REMINDER_ID \
  --no-completed \
  --clear-due \
  --pretty
```

Prefer completion over deletion unless the user explicitly wants the reminder removed.

## Deletion

```bash
nucleus-apple reminders delete-reminder --reminder-id REMINDER_ID
```

Inspect the target reminder first so you do not delete the wrong item.
