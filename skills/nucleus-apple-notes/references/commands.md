# Notes Command Patterns

If only `uvx` is available, replace each `nucleus-apple` prefix with `uvx --from nucleus-apple-mcp nucleus-apple`.

## Discovery

```bash
nucleus-apple notes list-accounts --pretty
nucleus-apple notes list-folders --pretty
nucleus-apple notes list-notes --query project --include-plaintext-excerpt --pretty
```

Use discovery commands before create, update, or attachment operations when the target note is unclear.

## Inspection

```bash
nucleus-apple notes get-note --note-id NOTE_ID --include-body-html --pretty
nucleus-apple notes list-attachments --note-id NOTE_ID --pretty
```

Read the existing note before destructive edits or attachment export.

## Mutation

```bash
nucleus-apple notes create-note \
  --folder-id FOLDER_ID \
  --title "Meeting notes" \
  --markdown $'- agenda\n- decisions' \
  --pretty

nucleus-apple notes update-note \
  --note-id NOTE_ID \
  --append-markdown "- Follow-up item" \
  --pretty

nucleus-apple notes update-note \
  --note-id NOTE_ID \
  --allow-destructive \
  --set-markdown "# Rewritten note" \
  --pretty
```

Set operations require `--allow-destructive`.

## Attachments

```bash
nucleus-apple notes add-attachment \
  --note-id NOTE_ID \
  --attach-file /tmp/file.pdf \
  --pretty

nucleus-apple notes save-attachment \
  --attachment-id ATTACHMENT_ID \
  --output-path /tmp/exported.pdf \
  --pretty
```

Inspect the note or attachment list first so you do not export or modify the wrong file.
