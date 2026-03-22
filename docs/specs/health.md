# Health Module Spec

This document defines the current storage and query model for the Health module.

The old `health/v0/...revisions/latest.json` design is removed. The project is still in development, so the storage model optimizes for:

- fast MCP reads
- explicit incremental polling
- simple object-store layout
- low ambiguity around "what changed"

## 1. Scope

- Collector runtime: iOS app (`Nucleus`)
- Source of truth: files written by the iOS app into private app storage, optionally uploaded to an S3-compatible object store
- Shipping app path: Nucleus does not sync Health exports to iCloud. This product line was removed for App Store distribution because Apple App Review Guideline 5.1.3(ii) disallows storing personal health information in iCloud.
- MCP reads those files from an S3-compatible object store
- No compatibility guarantee with earlier health export layouts

## 2. Design Goals

- Single-day reads should require one object read.
- Range reads should use month-level indexes rather than scanning every date path.
- Incremental MCP polling should use a stable cursor.
- Raw sample export should be queryable without rebuilding a full-day aggregate on the server.

## 2.1 Local Collector State

The iOS collector also keeps a private anchor store in app storage.

- It is not synced to iCloud Drive.
- It is not uploaded to S3-compatible object storage.
- It stores HealthKit anchor cursors and a UUID → date index used to resolve deletions.

This local state is an implementation detail of the collector. MCP only reads exported health artifacts under `health/`.

## 2.2 Observer Delivery

For sample-based HealthKit types, the iOS collector also registers `HKObserverQuery` handlers at app launch and enables immediate background delivery after authorization is granted.

- Observer wakeups feed the same local anchor store used by manual sync.
- The app replays incremental export from the anchor cursor and only rewrites affected dates.
- Daily aggregate metrics such as activity summary are still recomputed per affected date; they are not delivered as a standalone observer stream.
- Background delivery is best-effort. It should be treated as an automatic sync trigger, not as a durability boundary; the durable cursor remains the exported `commit_id`.

## 3. Storage Layout

All health artifacts live under:

`health/`

### 3.1 Daily Snapshot

Latest snapshot for one calendar day:

`health/daily/dates/{YYYY-MM-DD}.json`

This is the primary MCP read path for `health.read_daily_metrics`.

### 3.2 Monthly Index

Month-level materialized view:

`health/daily/months/{YYYY-MM}.json`

This file contains the latest daily snapshots for every exported day in that month.

This is the primary MCP read path for `health.read_range_metrics`.

### 3.3 Raw Samples

Per-day raw export root:

`health/raw/dates/{YYYY-MM-DD}/`

Contents:

- `manifest.json`
- `types/{TYPE_KEY}.jsonl`

`manifest.json` describes which per-type files exist, their record counts, and status.

### 3.4 Commit Log

Each sync run produces one commit file:

`health/commits/{YYYY}/{MM}/{DD}/{COMMIT_ID}.json`

`COMMIT_ID` is the sync cursor. It is globally unique and lexicographically sortable.

MCP incremental polling is based on this path family.

## 4. Commit ID

`COMMIT_ID` must be:

- UTC timestamp in `YYYYMMDDTHHMMSSZ`
- followed by `-`
- followed by a random hex suffix

Example:

`20260308T091230Z-A1B2C3`

## 5. Schemas

### 5.1 Daily Snapshot

Path:

`health/daily/dates/{YYYY-MM-DD}.json`

Current metric keys may include:

- `steps`
- `active_energy_kcal`
- `exercise_minutes`
- `stand_hours`
- `resting_hr_avg`
- `hrv_sdnn_avg`
- `vo2_max`
- `oxygen_saturation_pct`
- `respiratory_rate_avg`
- `wrist_temperature_celsius`
- `body_mass_kg`
- `body_fat_percentage`
- `blood_pressure_systolic_mmhg`
- `blood_pressure_diastolic_mmhg`
- `blood_glucose_mg_dl`
- `body_temperature_celsius`
- `basal_body_temperature_celsius`
- `sleep_asleep_minutes`
- `sleep_in_bed_minutes`

Example:

```json
{
  "schema_version": "health.daily.v1",
  "commit_id": "20260308T091230Z-A1B2C3",
  "date": "2026-03-08",
  "day": {
    "timezone": "Asia/Shanghai",
    "start": "2026-03-08T00:00:00+08:00",
    "end": "2026-03-09T00:00:00+08:00"
  },
  "generated_at": "2026-03-08T09:12:30Z",
  "collector": {
    "collector_id": "COLLECTOR_UUID",
    "device_id": "DEVICE_UUID"
  },
  "metrics": {
    "steps": 1250,
    "active_energy_kcal": 450.5
  },
  "metric_status": {
    "steps": "ok",
    "active_energy_kcal": "ok"
  },
  "metric_units": {
    "steps": "count",
    "active_energy_kcal": "kcal"
  },
  "raw_manifest_relpath": "health/raw/dates/2026-03-08/manifest.json"
}
```

### 5.2 Monthly Index

Path:

`health/daily/months/{YYYY-MM}.json`

Example:

```json
{
  "schema_version": "health.daily.month.v1",
  "month": "2026-03",
  "generated_at": "2026-03-08T09:12:30Z",
  "days": [
    {
      "schema_version": "health.daily.v1",
      "commit_id": "20260308T091230Z-A1B2C3",
      "date": "2026-03-08",
      "...": "same shape as daily snapshot"
    }
  ]
}
```

### 5.3 Raw Manifest

Path:

`health/raw/dates/{YYYY-MM-DD}/manifest.json`

Current raw type keys may include:

- `step_count`
- `active_energy_burned`
- `heart_rate`
- `resting_heart_rate`
- `hrv_sdnn`
- `vo2_max`
- `oxygen_saturation`
- `respiratory_rate`
- `apple_sleeping_wrist_temperature`
- `body_mass`
- `body_fat_percentage`
- `blood_pressure`
- `blood_glucose`
- `body_temperature`
- `basal_body_temperature`
- `sleep_analysis`
- `workout`

Example:

```json
{
  "schema_version": "health.raw.manifest.v1",
  "commit_id": "20260308T091230Z-A1B2C3",
  "date": "2026-03-08",
  "day": {
    "timezone": "Asia/Shanghai",
    "start": "2026-03-08T00:00:00+08:00",
    "end": "2026-03-09T00:00:00+08:00"
  },
  "generated_at": "2026-03-08T09:12:30Z",
  "collector": {
    "collector_id": "COLLECTOR_UUID",
    "device_id": "DEVICE_UUID"
  },
  "types": {
    "heart_rate": {
      "status": "ok",
      "record_count": 842,
      "relpath": "health/raw/dates/2026-03-08/types/heart_rate.jsonl"
    },
    "blood_pressure": {
      "status": "ok",
      "record_count": 2,
      "relpath": "health/raw/dates/2026-03-08/types/blood_pressure.jsonl"
    },
    "sleep_analysis": {
      "status": "unauthorized",
      "record_count": 0,
      "relpath": null
    }
  }
}
```

### 5.4 Commit File

Path:

`health/commits/{YYYY}/{MM}/{DD}/{COMMIT_ID}.json`

Example:

```json
{
  "schema_version": "health.commit.v1",
  "commit_id": "20260308T091230Z-A1B2C3",
  "generated_at": "2026-03-08T09:12:30Z",
  "collector": {
    "collector_id": "COLLECTOR_UUID",
    "device_id": "DEVICE_UUID"
  },
  "dates": [
    {
      "date": "2026-03-08",
      "daily_relpath": "health/daily/dates/2026-03-08.json",
      "month_relpath": "health/daily/months/2026-03.json",
      "raw_manifest_relpath": "health/raw/dates/2026-03-08/manifest.json",
      "raw_type_keys": ["heart_rate", "sleep_analysis", "step_count"]
    }
  ]
}
```

## 6. Collector Write Model

For each sync run:

1. Generate one `COMMIT_ID`.
2. Recompute the requested catch-up window locally.
3. Rewrite the affected day snapshots under `health/daily/dates/`.
4. Rewrite the affected month indexes under `health/daily/months/`.
5. Rewrite the affected raw manifest and per-type raw JSONL files under `health/raw/dates/`.
6. Write one commit file under `health/commits/`.

This is a current-state materialized-view model, not an append-only historical archive.

## 7. MCP Read Model

### 7.1 Single Day

`health.read_daily_metrics(date)`

- read `health/daily/dates/{date}.json`

### 7.2 Date Range

`health.read_range_metrics(start_date, end_date)`

- read the minimal set of monthly indexes that cover the requested range
- filter in-memory by date
- report missing dates explicitly

### 7.3 Sample Catalog

`health.list_sample_catalog()`

- return known raw `type_key` values
- return `kind` and logical `tags` for each type
- return how each raw type maps to exported daily metrics

### 7.4 Raw Samples

`health.read_samples(start_date, end_date?, type_keys?, tags?, kinds?, cursor?, max_records?, manifest_only?)`

- read `health/raw/dates/{date}/manifest.json` across the requested date range
- filter by canonical `type_key`, logical `tags`, and/or `kind`
- paginate fairly across date/type boundaries with an opaque cursor
- allow manifest-only reads without forcing sample payloads

### 7.5 Daily Raw Wrapper

`health.read_daily_raw(date, ...)`

- compatibility wrapper around `health.read_samples(...)` for a single date

### 7.6 Day Inspection

`health.inspect_day(date, metric_keys?, type_keys?)`

- combine the daily snapshot with the raw manifest
- explain why a daily metric is `ok`, `no_data`, `unauthorized`, or structurally disconnected from raw samples

### 7.7 Incremental Polling

`health.list_changes(since_cursor, include_raw_types=true)`

- list commit files under `health/commits/`
- return commits whose `commit_id` is lexicographically greater than `since_cursor`
- optionally enrich each changed date with raw type `status`, `record_count`, and `relpath`

### 7.8 Range Analysis

`health.analyze_range(start_date, end_date, metric_keys?, segment_count=3)`

- read the same monthly indexes used by `health.read_range_metrics`
- analyze exported daily snapshots in-memory
- do not read raw samples by default
- return per-metric coverage, summary statistics, segment means, trend direction, notable days, and short insight strings
- report missing dates explicitly so analysis confidence can be judged from data completeness

## 8. MCP Tool Set

Required:

- `health.list_sample_catalog`
- `health.read_daily_metrics`
- `health.read_range_metrics`
- `health.analyze_range`
- `health.read_samples`
- `health.read_daily_raw`
- `health.inspect_day`
- `health.list_changes`

## 9. Storage Configuration

Shipping product path:

- private export inside the iOS app container
- optional `s3_object_store` upload for MCP / agent access

The reference MCP implementation reads from:

- `s3_object_store`

Rationale:

- Apple App Review Guideline 5.1.3(ii) does not allow App Store apps to store personal health information in iCloud.
- Nucleus therefore removed iCloud health sync from the shipping collector path.
- The MCP implementation no longer exposes an iCloud backend.

Reference:

- https://developer.apple.com/app-store/review/guidelines/

Preferred local config file:

- `~/.config/nucleus-apple-mcp/config.toml`
- Or override path with `NUCLEUS_APPLE_MCP_CONFIG`
- Or start the server with `nucleus-apple-mcp --config-file /path/to/config.toml`

Suggested shape:

```toml
[health]
storage_backend = "s3_object_store"

[health.s3]
endpoint = "https://<accountid>.r2.cloudflarestorage.com"
region = "auto"
bucket = "your-bucket"
prefix = "nucleus"
access_key_id = "..."
secret_access_key = "..."
use_path_style = true
```

Environment variables remain supported and override file values when present:

### 9.1 S3-compatible Object Store

- `NUCLEUS_HEALTH_S3_ENDPOINT`
- `NUCLEUS_HEALTH_S3_REGION`
- `NUCLEUS_HEALTH_S3_BUCKET`
- `NUCLEUS_HEALTH_S3_PREFIX`
- `NUCLEUS_HEALTH_S3_ACCESS_KEY_ID`
- `NUCLEUS_HEALTH_S3_SECRET_ACCESS_KEY`
- `NUCLEUS_HEALTH_S3_SESSION_TOKEN`
- `NUCLEUS_HEALTH_S3_USE_PATH_STYLE`

## 10. Errors

- `INVALID_ARGUMENTS`
- `NOT_AUTHORIZED`
- `DATA_NOT_FOUND`
- `STORAGE_UNAVAILABLE`
- `INTERNAL`

## 11. Product Notes

- App name: `Nucleus`
- The storage layout is optimized for agent reads and MCP consumption, not for long-term archival compatibility.
