---
name: nucleus-apple-health
description: Query and analyze exported Apple Health metrics and raw samples via the nucleus-apple CLI. Use when a user wants range summaries, daily metrics, raw Health sample inspection, change history, or diagnostics about gaps between aggregates and raw exports.
homepage: https://github.com/zish-rob-crur/nucleus-apple-mcp
metadata:
  {
    "openclaw":
      {
        "emoji": "❤️",
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

# Nucleus Apple Health

Use `nucleus-apple health` to query and analyze exported Health data from iCloud Drive or an S3-compatible object store.

## Setup

- Requires `uv` / `uvx` on `PATH`
- Run commands via: `uvx --from nucleus-apple-mcp nucleus-apple ...`
- Configure Health export storage through `~/.config/nucleus-apple-mcp/config.toml` or `--config-file`
- Prefer exact dates in `YYYY-MM-DD`

## Common Commands

```bash
uvx --from nucleus-apple-mcp nucleus-apple health list-sample-catalog --pretty
uvx --from nucleus-apple-mcp nucleus-apple health analyze-range --start-date 2026-01-01 --end-date 2026-03-22 --segment-count 3 --pretty
uvx --from nucleus-apple-mcp nucleus-apple health read-daily-metrics --date 2026-03-14 --pretty
uvx --from nucleus-apple-mcp nucleus-apple health read-range-metrics --start-date 2026-03-01 --end-date 2026-03-14 --pretty
uvx --from nucleus-apple-mcp nucleus-apple health read-samples --start-date 2026-03-14 --tags sleep --max-records 100 --pretty
uvx --from nucleus-apple-mcp nucleus-apple health read-daily-raw --date 2026-03-14 --type-keys heart_rate --type-keys resting_heart_rate --pretty
uvx --from nucleus-apple-mcp nucleus-apple health inspect-day --date 2026-03-14 --metric-keys resting_hr_avg --pretty
uvx --from nucleus-apple-mcp nucleus-apple health list-changes --limit 20 --pretty
```

## Guidance

- Prefer `analyze-range` for multi-day or trend questions. It uses exported daily snapshots only and avoids raw-sample reads by default.
- Use `read-daily-metrics` for single-day summaries and `read-samples` or `read-daily-raw` for detailed inspection.
- Use `inspect-day` when a user asks why a metric is missing or inconsistent.
- Start with `list-sample-catalog` if the right `type_key`, `tag`, or `metric_key` is unclear.
- Escalate to raw sample commands only when a user needs anomaly explanation, workout detail, or aggregate/raw diagnosis.
