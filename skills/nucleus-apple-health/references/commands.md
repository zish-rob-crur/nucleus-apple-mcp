# Health Command Patterns

If only `uvx` is available, replace each `nucleus-apple` prefix with `uvx --from nucleus-apple-mcp nucleus-apple`.

## Discovery

```bash
nucleus-apple health list-sample-catalog --pretty
```

Start here when the right `metric_key`, `type_key`, or `tag` is unclear.

## Snapshots

```bash
nucleus-apple health analyze-range \
  --start-date 2026-01-01 \
  --end-date 2026-03-22 \
  --segment-count 3 \
  --pretty

nucleus-apple health read-daily-metrics --date 2026-03-14 --pretty
nucleus-apple health read-range-metrics --start-date 2026-03-01 --end-date 2026-03-14 --pretty
```

Prefer these commands for multi-day trends and single-day summaries.

## Raw Inspection

```bash
nucleus-apple health inspect-day \
  --date 2026-03-14 \
  --metric-keys resting_hr_avg \
  --pretty

nucleus-apple health read-samples \
  --start-date 2026-03-14 \
  --end-date 2026-03-16 \
  --tags sleep \
  --max-records 100 \
  --pretty

nucleus-apple health read-daily-raw \
  --date 2026-03-14 \
  --type-keys heart_rate \
  --type-keys resting_heart_rate \
  --pretty
```

Escalate here only when the user needs anomaly explanation, workout detail, or aggregate-vs-raw diagnosis.

## Change History

```bash
nucleus-apple health list-changes --limit 20 --pretty
nucleus-apple health list-changes --limit 20 --include-raw-types --pretty
```

Use this to answer "what changed recently?" questions before pulling larger date ranges.
