---
name: nucleus-apple-notes
description: Manage Apple Notes on macOS via the nucleus-apple CLI. Use when a user wants to list folders, search notes, fetch note bodies, create or update notes, and manage note attachments from the terminal.
homepage: https://github.com/zish-rob-crur/nucleus-apple-mcp
metadata:
  {
    "openclaw":
      {
        "emoji": "📝",
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

# Nucleus Apple Notes

Use `nucleus-apple notes` to work with Apple Notes from the terminal.

## Setup

- Requires `uv` / `uvx` on `PATH`
- Run commands via: `uvx --from nucleus-apple-mcp nucleus-apple ...`
- macOS only; grant Notes automation access when prompted
- Use `--pretty` when inspecting nested note or attachment payloads

## Common Commands

```bash
uvx --from nucleus-apple-mcp nucleus-apple notes list-accounts --pretty
uvx --from nucleus-apple-mcp nucleus-apple notes list-folders --pretty
uvx --from nucleus-apple-mcp nucleus-apple notes list-notes --query project --include-plaintext-excerpt --pretty
uvx --from nucleus-apple-mcp nucleus-apple notes get-note --note-id NOTE_ID --include-body-html --pretty
uvx --from nucleus-apple-mcp nucleus-apple notes create-note --title "Meeting notes" --markdown "- agenda\\n- decisions" --pretty
uvx --from nucleus-apple-mcp nucleus-apple notes update-note --note-id NOTE_ID --append-plaintext "Follow-up item" --pretty
uvx --from nucleus-apple-mcp nucleus-apple notes add-attachment --note-id NOTE_ID --attach-file /tmp/file.pdf --pretty
uvx --from nucleus-apple-mcp nucleus-apple notes save-attachment --attachment-id ATTACHMENT_ID --output-path /tmp/exported.pdf --pretty
```

## Guidance

- Use `list-folders` or `list-notes` first if the target note identifier is unknown.
- `update-note` requires `--allow-destructive` when using `--set-plaintext` or `--set-markdown`.
- `get-note` defaults to plaintext plus attachments; disable fields explicitly when a smaller payload is preferable.
