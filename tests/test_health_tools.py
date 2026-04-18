from __future__ import annotations

from nucleus_apple_mcp.tools import health as health_tools


def test_catalog_exposes_overlap_weighted_sleep_metrics() -> None:
    respiratory = health_tools._SAMPLE_CATALOG_BY_KEY["respiratory_rate"]
    wrist = health_tools._SAMPLE_CATALOG_BY_KEY["apple_sleeping_wrist_temperature"]

    assert respiratory.aggregate_hint == "overlap_weighted_average_per_day"
    assert wrist.aggregate_hint == "overlap_weighted_average_per_day"
    assert wrist.unit == "Δ°C"

    wrist_metric = health_tools._METRIC_SOURCE_CATALOG["wrist_temperature_celsius"]
    assert wrist_metric.aggregate_hint == "overlap_weighted_average_per_day"
    assert "delta from baseline" in wrist_metric.description


def test_wrist_temperature_plausibility_uses_delta_range() -> None:
    snapshot = {"metrics": {"wrist_temperature_celsius": 0.42}}

    assert health_tools._metric_value_is_plausible(snapshot, "wrist_temperature_celsius", 0.42)
    assert not health_tools._metric_value_is_plausible(snapshot, "wrist_temperature_celsius", 37.1)


def test_metric_observations_keep_wrist_temperature_deltas() -> None:
    observations, excluded = health_tools._metric_observations(
        [
            {"date": "2026-04-10", "metrics": {"wrist_temperature_celsius": 0.18}},
            {"date": "2026-04-11", "metrics": {"wrist_temperature_celsius": 0.31}},
        ],
        "wrist_temperature_celsius",
    )

    assert [item.date for item in observations] == ["2026-04-10", "2026-04-11"]
    assert [item.value for item in observations] == [0.18, 0.31]
    assert excluded == []
