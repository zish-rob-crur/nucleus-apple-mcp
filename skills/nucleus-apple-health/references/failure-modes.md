# Health Failure Modes

## Missing Dates vs Missing Metrics

- `read-range-metrics` and `analyze-range` can return `missing_dates` without treating them as errors.
- A missing date means there is no exported daily snapshot for that day; it does not mean the metric is zero.
- `read-daily-metrics` and `inspect-day` fail when the target date has no exported artifact at all.

## Metric Status Meanings

- `metric_status=ok` means the daily aggregate is present.
- `metric_status=unsupported` means the exporter or device does not support that metric.
- `metric_status=unauthorized` means authorization is missing for that metric or its source data.
- If status is missing or still not explanatory, use `inspect-day` to read the derived diagnosis.

## Aggregate vs Raw Gaps

- Activity summary metrics can still report no data even when supporting raw samples exist.
- Raw samples present with a missing daily aggregate can indicate an exporter aggregation gap or schema mismatch.
- Raw types present with `record_count=0` means "no raw records for that day", not necessarily an exporter failure.
- Some metrics map to multiple raw types; absence of one raw type does not prove the metric cannot exist.

## Filtered Empty Results

- Narrow `type_keys`, `tags`, or `kinds` can legitimately produce empty sample sets.
- Empty filtered samples do not prove the date has no raw export outside the selected filter.
- Use `manifest_only` or inspect returned manifests when you need to distinguish "no matching export" from "no matching records."

## Storage and Cursor Pitfalls

- Object-store `401`, `403`, and storage-unavailable errors are backend access problems, not HealthKit data gaps.
- Missing artifacts can be real export gaps rather than empty days.
- `next_cursor` is opaque; reuse it exactly rather than constructing your own cursor.
- `list-changes` is commit-level, so a changed date does not imply that every metric on that date changed.
