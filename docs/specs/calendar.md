# Calendar Module Spec (v0)

This document defines the "playbook" for the Calendar module: scope, commands, parameters, return schema, and error conventions. Implementations should follow this spec.

## 1. Scope & Constraints

- Only covers **Event calendars (Calendar.app)**, backed by macOS **EventKit**.
- Supports **multiple accounts/sources**: iCloud / Google / Exchange / On My Mac / subscribed, etc.
- Default behavior: **exclude hidden calendars**.
- Supports CRUD for **Event** (only for calendars where `is_writable=true`).
- v0 supports basic fields only: `title/start/end/is_all_day/location/notes/url/availability`; no attendees, alerts, recurrence rules, attachments, etc.
- Reminders are out of scope (handled in a separate module).

## 2. Terminology

- **Source**: account/provider container (EventKit: `EKSource`).
- **Calendar**: a specific calendar (EventKit: `EKCalendar`).
- **Event**: an event instance within a time window (EventKit: `EKEvent`).

## 3. Permissions (macOS)

The sidecar requires Calendar permission (System Privacy settings).

- When not authorized / denied, must return `ok=false` and `error.code=NOT_AUTHORIZED`.

## 4. Invocation Protocol (CLI only; no custom stdio protocol)

This project uses the Swift sidecar **CLI** as the single protocol (the legacy stdin JSON mode is not supported).

### 4.1 Output Convention

- Success: stdout prints a single JSON line:
  - `{"ok": true, "result": ...}`
- Failure: stdout prints a single JSON line and exits non-zero:
  - `{"ok": false, "error": {"code": "...", "message": "..."}}`
- Help output such as `--help/-h` is human-readable and not required to be JSON.

### 4.2 Error Codes (v0)

- `INVALID_ARGUMENTS`: invalid params / parse failure (e.g. `--start`/`--end` not satisfying `start < end`).
- `NOT_AUTHORIZED`: permission not granted / denied.
- `NOT_FOUND`: `calendar_id` or `event_id` not found.
- `NOT_WRITABLE`: target calendar not writable (read-only/subscribed/insufficient permission, etc.).
- `INTERNAL`: runtime exception (unknown error, serialization failure, etc.).

## 5. Data Models

### 5.1 Source

- `source_id` (string, opaque)
- `title` (string)
- `type` (string enum): `local | caldav | exchange | subscribed | birthdays | unknown`
- `calendar_count` (int)
- `writable_calendar_count` (int)

### 5.2 Calendar

- `calendar_id` (string, opaque)
- `source_id` (string, opaque)
- `title` (string)
- `type` (string enum): `local | caldav | exchange | subscription | birthday | unknown` (maps from EventKit `EKCalendarType`; exact mapping follows implementation)
- `color` (string, hex `#RRGGBB`)
- `is_writable` (bool)
- `is_hidden` (bool)

### 5.3 Event (v0)

Time format: ISO-8601 (with timezone offset), e.g. `2026-01-26T13:00:00-08:00`.

Required fields:

- `event_id` (string, opaque; may change across sync/edit)
- `calendar_id` (string)
- `title` (string)
- `start` (string, ISO-8601)
- `end` (string, ISO-8601)
- `is_all_day` (bool)

Optional fields (guaranteed only when listing with `--include-details`; included by default on create/update):

- `location` (string|null)
- `notes` (string|null)
- `url` (string|null)
- `availability` (string enum): `busy | free | tentative | unavailable | unknown`

## 6. Sidecar CLI (Swift) Commands

Calendar commands live under the `calendar` command group.

### 6.1 `calendar sources`

List sources (accounts/providers).

Options:

- `--include-empty` (bool, default: false): include sources with zero calendars.

Return:

- `{"sources": Source[]}`

Example:

```bash
nucleus-apple-sidecar calendar sources
```

### 6.2 `calendar calendars`

List event calendars.

Options:

- `--source-id <id>` (repeatable; optional): only return calendars under the given source(s).
- `--include-hidden` (bool, default: false)

Return:

- `{"calendars": Calendar[]}`

Example:

```bash
nucleus-apple-sidecar calendar calendars
```

### 6.3 `calendar events`

List event instances within a time range.

Options:

- `--start <iso8601>` (required)
- `--end <iso8601>` (required)
- `--calendar-id <id>` (repeatable; optional)
- `--source-id <id>` (repeatable; optional)
- `--include-details` (bool, default: false)
- `--limit <n>` (optional)

Return:

- `{"events": Event[]}`

Example:

```bash
nucleus-apple-sidecar calendar events \
  --start 2026-01-26T00:00:00-08:00 \
  --end   2026-02-02T00:00:00-08:00
```

### 6.4 `calendar create-event`

Create a new Event (written to a specific calendar).

Options:

- `--calendar-id <id>` (required)
- `--title <string>` (required)
- `--start <iso8601>` (required)
- `--end <iso8601>` (required)
- `--all-day` (bool flag, default: false)
- `--location <string>` (optional)
- `--notes <string>` (optional)
- `--url <string>` (optional)
- `--availability <busy|free|tentative|unavailable>` (optional)

Validation:

- `--start` must be earlier than `--end`.
- `calendar_id` must exist and `is_writable=true`.

Return:

- `{"event": Event}` (**create/update** returns full event fields by default; includes `location/notes/url/availability` with defaults `null/unknown`).

Example:

```bash
nucleus-apple-sidecar calendar create-event \
  --calendar-id <calendar_id> \
  --title "1:1" \
  --start 2026-01-26T13:00:00-08:00 \
  --end   2026-01-26T13:30:00-08:00 \
  --location "Office" \
  --notes "Discuss roadmap" \
  --url "https://example.com" \
  --availability busy
```

### 6.5 `calendar update-event`

Update an existing Event.

Options:

- `--event-id <id>` (required)
- `--span <this|future>` (optional; default: `this`; only meaningful for recurring events; `this`=EKSpan.thisEvent, `future`=EKSpan.futureEvents)

Updatable fields (provide at least one):

- `--calendar-id <id>` (optional; move to another calendar; target calendar must be writable)
- `--title <string>` (optional)
- `--start <iso8601>` (optional)
- `--end <iso8601>` (optional)
- `--is-all-day <true|false>` (optional; explicitly set all-day / not)
- `--location <string>` (optional)
- `--clear-location` (optional)
- `--notes <string>` (optional)
- `--clear-notes` (optional)
- `--url <string>` (optional)
- `--clear-url` (optional)
- `--availability <busy|free|tentative|unavailable>` (optional)
- `--clear-availability` (optional; reset to `unknown`)

Validation:

- Must provide at least one updatable field; otherwise `INVALID_ARGUMENTS`.
- If `start`/`end` is updated (either one), the resulting event must satisfy `start < end`.
- The event's current calendar and the target calendar (if moving) must be writable; otherwise `NOT_WRITABLE`.

Return:

- `{"event": Event}`

Example:

```bash
nucleus-apple-sidecar calendar update-event \
  --event-id <event_id> \
  --title "Updated title" \
  --start 2026-01-26T14:00:00-08:00 \
  --end   2026-01-26T14:30:00-08:00
```

### 6.6 `calendar delete-event`

Delete an Event.

Options:

- `--event-id <id>` (required)
- `--span <this|future>` (optional; default: `this`; only meaningful for recurring events; `this`=EKSpan.thisEvent, `future`=EKSpan.futureEvents)

Return:

- `{"deleted": true, "event_id": "..."}`

Example:

```bash
nucleus-apple-sidecar calendar delete-event --event-id <event_id>
```

## 7. MCP Tool Mapping (Python / FastMCP)

The Python MCP server must provide tools with a 1:1 mapping to sidecar commands:

- `calendar.list_sources` → `nucleus-apple-sidecar calendar sources`
- `calendar.list_calendars` → `nucleus-apple-sidecar calendar calendars`
- `calendar.list_events` → `nucleus-apple-sidecar calendar events`
- `calendar.create_event` → `nucleus-apple-sidecar calendar create-event`
- `calendar.update_event` → `nucleus-apple-sidecar calendar update-event`
- `calendar.delete_event` → `nucleus-apple-sidecar calendar delete-event`
