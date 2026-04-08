---
name: nucleus-apple-health
description: Query and analyze exported Apple Health metrics and raw samples with the `nucleus-apple` CLI. Use when the task involves trend summaries, daily metrics, raw sample inspection, sync change history, or diagnosing gaps between aggregates and raw exports.
metadata: {"openclaw":{"emoji":"❤️","homepage":"https://github.com/zish-rob-crur/nucleus-apple-mcp","os":["darwin"],"requires":{"anyBins":["nucleus-apple","uvx"]},"install":[{"id":"uv","kind":"uv","package":"nucleus-apple-mcp","bins":["nucleus-apple"],"label":"Install nucleus-apple (uv)"}]}}
---

Use `nucleus-apple health ...` to summarize exported Health data and drill into raw samples only when needed.

## Operating Stance

- Prefer the installed `nucleus-apple` binary.
- Fall back to `uvx --from nucleus-apple-mcp nucleus-apple ...` when only `uvx` is available.
- Start with snapshot-based reads; escalate to raw sample reads only when the task needs record-level evidence or gap diagnosis.
- Use exact `YYYY-MM-DD` dates and keep ranges as narrow as the question allows.
- Narrow heavy reads with `metric_keys`, `type_keys`, `tags`, `kinds`, or `max_records`.
- Treat `missing_dates`, `metric_status`, and raw manifest status as separate signals.
- Reuse returned cursors when paginating raw reads instead of widening filters.

## Core Workflow

1. If metric vocabulary is unclear, start with `list-sample-catalog`.
2. Route summary questions through snapshot reads using `references/decision-rules.md`.
3. Escalate to `inspect-day` before raw samples when the question is "why is this missing or inconsistent?"
4. Use `references/commands.md` for canonical command shapes.
5. Use `references/failure-modes.md` to interpret missing data, authorization gaps, and storage errors.

## Task Routing

- Trend summaries or range overviews: read `references/decision-rules.md#snapshot-routing`.
- Single-day values or missing-metric diagnosis: read `references/decision-rules.md#daily-and-diagnostic-routing`.
- Record-level raw samples, workouts, or filtered manifests: read `references/decision-rules.md#raw-escalation` and `references/decision-rules.md#filter-selection`.
- Recent sync or export changes: read `references/decision-rules.md#change-history`.
- Unsupported metrics, aggregate-vs-raw gaps, or empty filtered reads: read `references/failure-modes.md`.

## Output / Escalation

- Use `--pretty` only for human inspection.
- Keep raw reads bounded with `--max-records` unless full pagination is explicitly requested.
- Prefer `inspect-day` over direct raw reads when the task is to explain a missing or inconsistent daily aggregate.
