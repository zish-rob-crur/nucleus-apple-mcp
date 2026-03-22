---
name: nucleus-apple-calendar
description: Manage Apple Calendar on macOS via the nucleus-apple CLI. Use when a user wants to list calendars, inspect availability, search events in a time range, or create, update, and delete Calendar events.
homepage: https://github.com/zish-rob-crur/nucleus-apple-mcp
metadata:
  {
    "openclaw":
      {
        "emoji": "📅",
        "os": ["darwin"],
        "requires": { "bins": ["nucleus-apple"] },
        "install":
          [
            {
              "id": "uv",
              "kind": "uv",
              "package": "nucleus-apple-mcp",
              "bins": ["nucleus-apple"],
              "label": "Install nucleus-apple (uv)",
            },
          ],
      },
  }
---

# Nucleus Apple Calendar

Use `nucleus-apple calendar` to work with Apple Calendar through EventKit.

## Setup

- Requires `uv` / `uvx` on `PATH`
- Run commands via: `uvx --from nucleus-apple-mcp nucleus-apple ...`
- macOS only; grant Calendar access when prompted
- Prefer exact ISO 8601 datetimes when filtering or creating events

## Common Commands

```bash
uvx --from nucleus-apple-mcp nucleus-apple calendar list-sources --pretty
uvx --from nucleus-apple-mcp nucleus-apple calendar list-calendars --pretty
uvx --from nucleus-apple-mcp nucleus-apple calendar list-events --start 2026-03-15T09:00:00+08:00 --end 2026-03-15T18:00:00+08:00 --include-details --pretty
uvx --from nucleus-apple-mcp nucleus-apple calendar create-event --calendar-id CALENDAR_ID --title "Design review" --start 2026-03-15T14:00:00+08:00 --end 2026-03-15T15:00:00+08:00 --pretty
uvx --from nucleus-apple-mcp nucleus-apple calendar update-event --event-id EVENT_ID --title "Updated title" --pretty
uvx --from nucleus-apple-mcp nucleus-apple calendar delete-event --event-id EVENT_ID
```

## Guidance

- Run `list-calendars` before creating or moving events if the calendar identifier is unknown.
- Use `--include-details` on `list-events` when location, notes, or URL matter.
- Use explicit timezone offsets in datetimes to avoid ambiguity.
