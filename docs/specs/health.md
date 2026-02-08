# Health Module Spec (v0.1)

This document defines the playbook for the Health module: scope, sync architecture, file schema, MCP tools, and error conventions.

v0.1 tightens the v0 design for correctness under real-world constraints:

- iOS background execution is **best-effort**; uploads can be delayed. ([Apple Developer][6])
- Network retries and concurrent runs can cause **write races**; older uploads must never overwrite newer data.
- “A day” must be unambiguous across timezones/DST; day boundaries must be explicit.
- Missing/unauthorized data must be explicit; never encode “no data” as `0`.

---

## 1. Scope & Constraints

- Module name: **health**
- Data collection runtime: **iOS companion app only** (no direct macOS HealthKit collection in v0.x).
- v0.x is **read-only for downstream agents** (no write-back to HealthKit).
- v0.x uploads **aggregated metrics only** (daily buckets), not raw samples.
- Supports two storage backends:
  - `icloud_drive` (Documents folder under the app’s iCloud ubiquity container)
  - `s3_object_store`
- Sync mode: **File-based synchronization** (Daily + incremental updates).
- Consistency model: **eventual consistency** (files appear when uploaded).

Out of scope in v0.x:

- ECG/clinical records
- raw-sample export APIs
- server-side databases/indexing services (v0.x is “direct file read”)
- complex on-demand triggers (push notifications)

---

## 2. Terminology

- **Collector**: iOS app component that reads HealthKit and uploads health daily data files.
- **Storage**: iCloud Drive (Documents) or S3 bucket/prefix where files are deposited.
- **Day**: a reporting day with explicit timezone and `[start, end)` boundaries.
- **Revision**: an immutable file representing one generated snapshot for a specific day.
- **Latest Pointer**: a small file indicating the best-known latest revision for a day.

---

## 3. Platform Facts This Spec Assumes

- HealthKit authorization is fine-grained; apps must request read permissions per type. ([Apple Developer][4])
- Background delivery uses observer queries / background delivery and is best-effort. ([Apple Developer][5])
- Background task scheduling is best-effort; do not assume exact timing or frequency. ([Apple Developer][6])
- S3 has strong read-after-write consistency for PUT/GET/LIST. ([AWS][7])

---

## 4. Architecture

### 4.1 High-Level Flow

1. iOS Collector reads HealthKit (daily statistics queries).
2. Collector constructs a **Daily Revision** JSON payload for the reporting day.
3. Collector uploads an immutable revision file under that day’s directory (append-only).
4. (Optional) Collector updates that day’s `latest.json` pointer.
5. MCP tools read these files directly to answer queries.

### 4.2 Write Model (Normative): Append-Only Revisions

To prevent write races from corrupting “latest” data, **do not overwrite daily data files**.

- Each update produces a new revision file under `.../{YYYY}/{MM}/{DD}/revisions/`.
- Revision file names must sort chronologically (lexicographic order) and be globally unique.
- The collector may update `latest.json` as an optimization, but MCP must tolerate it being missing or stale.

### 4.3 Sync Triggers (Best-Effort)

- **Primary Trigger (HealthKit Updates)**:
  - Register `HKObserverQuery` for tracked types. ([Apple Developer][5])
  - On notification (Background Delivery), recompute “today” and upload a new revision.
- **Secondary Trigger (Scheduled)**:
  - Use `BGAppRefreshTask` to run periodically (e.g., nightly). ([Apple Developer][6])
  - Recompute and upload revisions for a **catch-up window** (default: last 7 days) to absorb late-arriving data (sleep, HRV, etc.).

---

## 5. Storage Layout (Normative)

### 5.1 Base Prefix

All objects live under:

`health/v0/`

### 5.2 Day Directory

`health/v0/data/{YYYY}/{MM}/{DD}/`

Contents:

- `revisions/{REVISION_ID}.json` (immutable; 1+ files)
- `latest.json` (optional; pointer to the best-known latest revision)

### 5.3 Revision ID Format (Normative)

`REVISION_ID` must be:

- UTC timestamp formatted as `YYYYMMDDTHHMMSSZ`
- followed by `-` and a random suffix (6+ base16 chars)

Example:

- `20260208T100000Z-7F3A2C`

### 5.4 latest.json Format (Optional)

```json
{
  "date": "2026-02-08",
  "latest_generated_at": "2026-02-08T10:00:00Z",
  "revision_id": "20260208T100000Z-7F3A2C",
  "revision_relpath": "revisions/20260208T100000Z-7F3A2C.json"
}
```

Semantics:

- `revision_relpath` is relative to `health/v0/data/{YYYY}/{MM}/{DD}/`.
- MCP must verify the referenced revision exists and is parseable; otherwise it must fall back to scanning `revisions/`.

---

## 6. Daily Revision File Schema (v0)

### 6.1 File Path

`health/v0/data/{YYYY}/{MM}/{DD}/revisions/{REVISION_ID}.json`

### 6.2 JSON Content

```json
{
  "schema_version": "health.v0",
  "date": "2026-02-08",
  "day": {
    "timezone": "America/Los_Angeles",
    "start": "2026-02-08T00:00:00-08:00",
    "end": "2026-02-09T00:00:00-08:00"
  },
  "generated_at": "2026-02-08T10:00:00Z",
  "collector": {
    "collector_id": "4E0A0B4E-2E08-4B63-9B50-8E3F6F8A1F1F",
    "device_id": "A1B2C3D4-E5F6-7890-ABCD-EF0123456789"
  },
  "metrics": {
    "steps": 1250,
    "active_energy_kcal": 450.5,
    "exercise_minutes": 30,
    "stand_hours": 4,
    "resting_hr_avg": null,
    "hrv_sdnn_avg": null,
    "sleep_asleep_minutes": null,
    "sleep_in_bed_minutes": null
  },
  "metric_status": {
    "steps": "ok",
    "active_energy_kcal": "ok",
    "exercise_minutes": "ok",
    "stand_hours": "ok",
    "resting_hr_avg": "no_data",
    "hrv_sdnn_avg": "unauthorized",
    "sleep_asleep_minutes": "no_data",
    "sleep_in_bed_minutes": "no_data"
  },
  "metric_units": {
    "steps": "count",
    "active_energy_kcal": "kcal",
    "exercise_minutes": "min",
    "stand_hours": "hr",
    "resting_hr_avg": "bpm",
    "hrv_sdnn_avg": "ms",
    "sleep_asleep_minutes": "min",
    "sleep_in_bed_minutes": "min"
  }
}
```

Rules:

- `generated_at` MUST be an ISO-8601 datetime in UTC (suffix `Z`).
- `day.start`/`day.end` MUST be ISO-8601 with explicit timezone offset; interval is `[start, end)`.
- `metrics` values are numbers or `null` (never use `0` to mean “no data”).
- For a metric key `k`:
  - if `metric_status[k] == "ok"`, then `metrics[k]` MUST be a number
  - if `metric_status[k] != "ok"`, then `metrics[k]` MUST be `null`

### 6.3 metric_status Enum

- `ok`: data computed and present
- `no_data`: authorized but HealthKit had no data for that interval
- `unauthorized`: collector did not have permission to read that metric
- `unsupported`: metric not supported on this device/OS configuration

---

## 7. Metric Keys (v0)

- `steps`
- `active_energy_kcal`
- `exercise_minutes`
- `stand_hours`
- `resting_hr_avg`
- `hrv_sdnn_avg`
- `sleep_asleep_minutes`
- `sleep_in_bed_minutes`

---

## 8. iOS Collector Behavior (Normative)

### 8.1 Collector Identity

- `collector_id` MUST be stable across launches and ideally across reinstalls (e.g., UUID stored in Keychain).
- `device_id` SHOULD be a stable UUID chosen by the app; avoid using transient identifiers.

### 8.2 What Gets Recomputed

On each run (foreground launch, observer wake, or scheduled task):

- Always recompute **today**.
- Recompute a **catch-up window** of past days (default: last 7 days) to handle late-arriving or corrected data.

### 8.3 Upload Procedure (Per Day)

1. Compute the day boundaries (`day.timezone`, `day.start`, `day.end`) and aggregated metrics for that interval.
2. Generate a new `REVISION_ID` using the current UTC time and a random suffix.
3. Write JSON to a local temp file, then upload/move into `revisions/{REVISION_ID}.json` (immutable).
4. Optionally update `latest.json` to point to the new revision.

The collector MAY skip writing a new revision if the computed payload is byte-for-byte identical to the current latest revision.

---

## 9. MCP Read Behavior (Normative)

### 9.1 Resolving “Latest” for a Day

Given a `date`:

1. Try to read `health/v0/data/YYYY/MM/DD/latest.json`.
2. If present, attempt to read the referenced revision file.
3. If `latest.json` is missing, stale, or invalid, list `health/v0/data/YYYY/MM/DD/revisions/` and choose the lexicographically greatest `REVISION_ID`.

### 9.2 Range Reads

Range reads MUST be date-driven (by calendar date), not by listing arbitrary prefixes:

- For each date in `[start_date, end_date]` (inclusive), attempt to resolve latest and read one revision.
- Missing dates are reported in `missing_dates` and do not cause the tool to fail.

---

## 10. Error Codes (v0.x)

- `INVALID_ARGUMENTS`: invalid params / parse failure (bad date format, `start_date > end_date`, range too large).
- `NOT_AUTHORIZED`: MCP lacks permission/credentials to read the configured storage.
- `DATA_NOT_FOUND`: no data exists for the requested date (no revisions found).
- `STORAGE_UNAVAILABLE`: storage backend temporarily unavailable (network, API errors).
- `INTERNAL`: unexpected exception (serialization, bug).

---

## 11. MCP Tool Mapping (Python / FastMCP)

Required tools:

- `health.read_daily_metrics`
- `health.read_range_metrics`

### 11.1 `health.read_daily_metrics`

Inputs:

- `date` (YYYY-MM-DD, required)

Returns:

- `date` (YYYY-MM-DD)
- `generated_at` (ISO-8601 UTC)
- `day` (timezone + boundaries)
- `metrics` (object, values are number|null)
- `metric_status` (object)
- `metric_units` (object)

### 11.2 `health.read_range_metrics`

Inputs:

- `start_date` (YYYY-MM-DD, required)
- `end_date` (YYYY-MM-DD, required; inclusive)

Constraints:

- `start_date <= end_date` else `INVALID_ARGUMENTS`
- maximum span: 366 days (else `INVALID_ARGUMENTS`)

Returns:

- `start_date`
- `end_date`
- `data`: array of daily objects (sorted by `date` ascending)
- `missing_dates`: array of YYYY-MM-DD for which no revision exists

---

## 12. Freshness Policy

- Data is as fresh as the newest available revision for the date.
- MCP always reports `generated_at` so callers can reason about staleness.

---

## 13. Security & Privacy

- Collector writes only to private user storage (iCloud Drive / private S3 prefix).
- No raw samples are exported in v0.x; only daily aggregates are uploaded.
- MCP reads from storage with user-provided credentials; there is no intermediate ingest server.

---

## 14. v0.x Acceptance Criteria

- iOS app uploads append-only daily revisions under `health/v0/...`.
- “Latest” resolution is correct under retries/races (no older revision can overwrite newer data).
- MCP can read single-day and range results, with explicit missing/unauthorized semantics.

---

## References

[4]: https://developer.apple.com/documentation/healthkit/authorizing_access_to_health_data
[5]: https://developer.apple.com/documentation/healthkit/hkobserverquery
[6]: https://developer.apple.com/documentation/backgroundtasks
[7]: https://docs.aws.amazon.com/AmazonS3/latest/userguide/Welcome.html
