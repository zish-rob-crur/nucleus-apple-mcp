# Health Decision Rules

Load this file when the task is more than a simple one-day snapshot read.

## Intent Router

- Use `list-sample-catalog` when the right `metric_key`, `type_key`, `tag`, or `kind` is unclear.
- Use snapshot commands first for summaries and trends.
- Use `inspect-day` when the task is "why is this metric missing, inconsistent, or surprising?"
- Use raw sample reads only when the user needs record-level detail, workouts, or manifest-aware export inspection.
- Use `list-changes` for recent sync activity or commit cursor questions.

## Snapshot Routing

- Use `analyze-range` for high-level summaries, segment comparisons, notable days, and generated insights.
- Use `read-range-metrics` when the caller wants per-day values for a range or will do custom analysis.
- Use `read-daily-metrics` for one day's exported snapshot.
- Treat `missing_dates` in range reads as missing exports, not as zero-valued metrics.

## Daily and Diagnostic Routing

- Use `inspect-day` before raw reads when the question is "why no data?" or "why does this aggregate not match expectations?"
- Pass `metric_keys` when the diagnosis is about specific daily metrics.
- Pass `type_keys` to `inspect-day` when the question starts from raw types and needs mapping back to aggregates.
- If one metric is enough to answer the question, do not inspect the full catalog.

## Raw Escalation

- Use `read-daily-raw` for one-day raw inspection.
- Use `read-samples` for multi-date raw reads, cross-day sample collection, or paginated sample inspection.
- Use `manifest_only` when the task is about which raw exports exist rather than reading sample payloads.
- Use raw reads only when snapshot outputs or `inspect-day` do not already answer the question.

## Filter Selection

- Use `type_keys` when the exact raw type is known.
- Use `tags` or `kinds` when the user describes a concept such as sleep, workout, or quantity records rather than an exact raw type.
- Set `max_records` on exploratory raw reads instead of pulling large payloads by default.
- Reuse `next_cursor` exactly as returned when paginating.

## Change History

- Use `list-changes` when the user asks what synced recently, which dates changed, or which commit cursor to resume from.
- Add `include_raw_types` only when the task is about which raw exports changed, not just that a commit exists.
