# Reminders Module Spec (v0)

This document defines the "playbook" for the Reminders module: scope, commands, parameters, return schema, and error conventions. Implementations should follow this spec.

## 1. Scope & Constraints

- Only covers macOS **Reminders.app**, backed by **EventKit** (`EKReminder` / `EKCalendar(entityType: .reminder)` / `EKSource`).
- Supports **multiple accounts/sources**: iCloud / Google / Exchange / On My Mac / subscribed, etc. (as returned by EventKit).
- Default behavior: **exclude hidden lists** (EventKit: the hidden property on `EKCalendar`).
- Supports CRUD for Reminder (only for lists where `is_writable=true`).
- v0 supports basic fields only: `title/start/due/is_completed/notes/url/priority`; excludes subtasks, tags, attachments, geofencing, smart lists, etc.
- Calendar is out of scope (handled in a separate module).

## 2. Terminology

- **Source**: account/provider container (EventKit: `EKSource`).
- **List**: a reminder list (EventKit: `EKCalendar`, `entityType = .reminder`).
- **Reminder**: a reminder item (EventKit: `EKReminder`).

## 3. Permissions (macOS)

The sidecar requires Reminders permission (System Privacy settings).

- When not authorized / denied, must return `ok=false` and `error.code=NOT_AUTHORIZED`.

## 4. Invocation Protocol (CLI only; no custom stdio protocol)

This project uses the Swift sidecar **CLI** as the single protocol.

### 4.1 Output Convention

- Success: stdout prints a single JSON line:
  - `{"ok": true, "result": ...}`
- Failure: stdout prints a single JSON line and exits non-zero:
  - `{"ok": false, "error": {"code": "...", "message": "..."}}`
- Help output such as `--help/-h` is human-readable and not required to be JSON.

### 4.2 Error Codes (v0)

- `INVALID_ARGUMENTS`: invalid params / parse failure.
- `NOT_AUTHORIZED`: permission not granted / denied.
- `NOT_FOUND`: `list_id` or `reminder_id` not found.
- `NOT_WRITABLE`: target list not writable (read-only/subscribed/insufficient permission, etc.).
- `INTERNAL`: runtime exception (unknown error, serialization failure, etc.).

## 5. Data Models

### 5.1 Source

Same as the Calendar module:

- `source_id` (string, opaque)
- `title` (string)
- `type` (string enum): `local | caldav | exchange | subscribed | birthdays | unknown`
- `list_count` (int): number of visible (non-hidden) lists under this source
- `writable_list_count` (int): number of writable lists under this source

### 5.2 List

- `list_id` (string, opaque)
- `source_id` (string, opaque)
- `title` (string)
- `type` (string enum): `local | caldav | exchange | subscription | birthday | unknown` (maps from EventKit `EKCalendarType`; exact mapping follows implementation)
- `color` (string, hex `#RRGGBB`)
- `is_writable` (bool)
- `is_hidden` (bool)

### 5.3 Reminder (v0)

Time format: ISO-8601.

- For `start/due`, allow either **date-only** (`YYYY-MM-DD`) or **datetime** with timezone offset (e.g. `2026-01-26T13:00:00-08:00`).
- Output follows the same rule: date-only outputs `YYYY-MM-DD`; datetime outputs a timezone-offset ISO-8601 datetime.

Fields:

- `reminder_id` (string, opaque; may change across sync/edit)
- `list_id` (string)
- `title` (string)
- `start` (string|null)
- `due` (string|null)
- `is_completed` (bool)
- `notes` (string|null)
- `url` (string|null)
- `priority` (int, 0-9; 0 means none. Suggested values: `1` high, `5` medium, `9` low)

## 6. Sidecar CLI (Swift) Commands

Reminders commands live under the `reminders` command group.

### 6.1 `reminders sources`

List sources (accounts/providers).

Options:

- `--include-empty` (bool, default: false): include sources with zero lists.

Return:

- `{"sources": Source[]}`

### 6.2 `reminders lists`

List reminder lists.

Options:

- `--source-id <id>` (repeatable; optional): only return lists under the given source(s).
- `--include-hidden` (bool, default: false)

Return:

- `{"lists": List[]}`

### 6.3 `reminders reminders`

List reminders by filters.

Options:

- `--start <iso8601|YYYY-MM-DD>` (optional): lower bound filter for reminder `start` (`start >= start`). date-only is interpreted as local timezone at 00:00.
- `--end <iso8601|YYYY-MM-DD>` (optional): upper bound filter for reminder `start` (`start < end`). date-only is interpreted as local timezone at **next day 00:00** (i.e. includes the whole date).
- `--due-start <iso8601|YYYY-MM-DD>` (optional): lower bound filter for reminder `due` (`due >= due-start`). date-only is interpreted as local timezone at 00:00.
- `--due-end <iso8601|YYYY-MM-DD>` (optional): upper bound filter for reminder `due` (`due < due-end`). date-only is interpreted as local timezone at next day 00:00.
- `--list-id <id>` (repeatable; optional)
- `--source-id <id>` (repeatable; optional)
- `--status <open|completed|all>` (optional; default: `open`; filters by `is_completed`)
- `--limit <n>` (optional; default: 200; must be > 0)

Notes:

- If neither `--list-id` nor `--source-id` is provided: query **all visible (non-hidden) lists** by default.
- `--list-id` is repeatable and uses **OR** semantics (matches any listed id).
- `--source-id` is repeatable and uses **OR** semantics.
- If both `--list-id` and `--source-id` are provided, filtering is **AND** (first narrow lists by source, then filter by list-id).
- If both `start/end` and `due-start/due-end` are provided, filtering is **AND** (intersection).
- If both `--start` and `--end` are provided, must satisfy `start < end`; otherwise `INVALID_ARGUMENTS`.
- If both `--due-start` and `--due-end` are provided, must satisfy `due-start < due-end`; otherwise `INVALID_ARGUMENTS`.
- If a reminder's `start`/`due` is null, and the corresponding range filter is present, treat it as non-matching (excluded).
- Sorting (for stable output):
  - When `--status=all`: `is_completed=false` first, then `is_completed=true`.
  - Then sort by `due` ascending (`null` last) → `start` ascending (`null` last) → `title` (case-insensitive) → `reminder_id`.
  - `limit` is applied after sorting (take the first N).

Return:

- `{"reminders": Reminder[]}`

### 6.4 `reminders create-reminder`

Create a new Reminder.

Options:

- `--list-id <id>` (required)
- `--title <string>` (required)
- `--start <iso8601|YYYY-MM-DD>` (optional)
- `--due <iso8601|YYYY-MM-DD>` (optional)
- `--notes <string>` (optional)
- `--url <string>` (optional)
- `--priority <0-9>` (optional; default: 0)

Validation:

- `list_id` must exist and `is_writable=true`.
- `start/due` must parse if provided.
- `priority` must be in `0-9`; otherwise `INVALID_ARGUMENTS`.
- `url` must parse as URL if provided; otherwise `INVALID_ARGUMENTS`.

Return:

- `{"reminder": Reminder}` (create/update returns full fields by default; missing optional values default to `null/0`).

### 6.5 `reminders update-reminder`

Update an existing Reminder.

Options:

- `--reminder-id <id>` (required)

Updatable fields (provide at least one):

- `--list-id <id>` (optional; move to another list; target list must be writable)
- `--title <string>` (optional)
- `--start <iso8601|YYYY-MM-DD>` (optional)
- `--clear-start` (optional)
- `--due <iso8601|YYYY-MM-DD>` (optional)
- `--clear-due` (optional)
- `--notes <string>` (optional)
- `--clear-notes` (optional)
- `--url <string>` (optional)
- `--clear-url` (optional)
- `--priority <0-9>` (optional)
- `--clear-priority` (optional; reset to 0)
- `--completed <true|false>` (optional; mark complete/uncomplete)

Mutual exclusion & validation:

- Must provide at least one updatable field; otherwise `INVALID_ARGUMENTS`.
- The following options are mutually exclusive (both present → `INVALID_ARGUMENTS`):
  - `--start` vs `--clear-start`
  - `--due` vs `--clear-due`
  - `--notes` vs `--clear-notes`
  - `--url` vs `--clear-url`
  - `--priority` vs `--clear-priority`
- `start/due` must parse if provided.
- `priority` must be in `0-9` if provided; otherwise `INVALID_ARGUMENTS`.
- `url` must parse as URL if provided; otherwise `INVALID_ARGUMENTS`.
- `--completed=true`: set `is_completed=true` and write `completionDate` (v0: "now").
- `--completed=false`: set `is_completed=false` and clear `completionDate`.
- If the reminder's current list or the target list is not writable, return `NOT_WRITABLE`.

Return:

- `{"reminder": Reminder}`

### 6.6 `reminders delete-reminder`

Delete a Reminder.

Options:

- `--reminder-id <id>` (required)

Return:

- `{"deleted": true, "reminder_id": "..."}`

## 7. MCP Tool Mapping (Python / FastMCP)

The Python MCP server must provide tools with a 1:1 mapping to sidecar commands:

- `reminders.list_sources` → `nucleus-apple-sidecar reminders sources`
- `reminders.list_lists` → `nucleus-apple-sidecar reminders lists`
- `reminders.list_reminders` → `nucleus-apple-sidecar reminders reminders`
- `reminders.create_reminder` → `nucleus-apple-sidecar reminders create-reminder`
- `reminders.update_reminder` → `nucleus-apple-sidecar reminders update-reminder`
- `reminders.delete_reminder` → `nucleus-apple-sidecar reminders delete-reminder`
