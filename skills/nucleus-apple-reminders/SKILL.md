---
name: nucleus-apple-reminders
description: Manage Apple Reminders on macOS via the nucleus-apple CLI. Use when a user wants to inspect reminder lists, filter reminders by dates or status, or create, update, complete, and delete reminders that sync through Apple Reminders.
homepage: https://github.com/zish-rob-crur/nucleus-apple-mcp
metadata:
  {
    "openclaw":
      {
        "emoji": "✅",
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

# Nucleus Apple Reminders

Use `nucleus-apple reminders` to manage Apple Reminders through EventKit.

## Setup

- Requires `uv` / `uvx` on `PATH`
- Run commands via: `uvx --from nucleus-apple-mcp nucleus-apple ...`
- macOS only; grant Reminders access when prompted
- Prefer explicit dates like `2026-03-20` or `2026-03-20T09:00:00+08:00`

## Common Commands

```bash
uvx --from nucleus-apple-mcp nucleus-apple reminders list-sources --pretty
uvx --from nucleus-apple-mcp nucleus-apple reminders list-lists --pretty
uvx --from nucleus-apple-mcp nucleus-apple reminders list-reminders --due-end 2026-03-20 --status open --pretty
uvx --from nucleus-apple-mcp nucleus-apple reminders create-reminder --list-id LIST_ID --title "Buy milk" --due 2026-03-20 --pretty
uvx --from nucleus-apple-mcp nucleus-apple reminders update-reminder --reminder-id REMINDER_ID --completed --pretty
uvx --from nucleus-apple-mcp nucleus-apple reminders delete-reminder --reminder-id REMINDER_ID
```

## Guidance

- Use `list-lists` first if the target list is not known.
- Use `list-reminders` with `--status all` when looking for both open and completed items.
- Mark a reminder complete with `update-reminder --completed true` rather than deleting it unless removal is explicitly requested.
