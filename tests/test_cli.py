from __future__ import annotations

import json
import os

from typer.testing import CliRunner

from nucleus_apple_mcp import cli

runner = CliRunner()


def test_health_list_sample_catalog_outputs_json() -> None:
    result = runner.invoke(cli.get_app(), ["health", "list-sample-catalog"])
    payload = json.loads(result.stdout)

    assert result.exit_code == 0
    assert "sample_types" in payload
    assert any(item["type_key"] == "heart_rate" for item in payload["sample_types"])


def test_boolean_flags_use_expected_help_forms() -> None:
    result = runner.invoke(cli.get_app(), ["reminders", "update-reminder", "--help"])

    assert result.exit_code == 0
    assert "--completed" in result.stdout
    assert "--no-completed" in result.stdout
    assert "--clear-start" in result.stdout
    assert "--no-clear-start" not in result.stdout


def test_global_config_option_applies_before_subcommand(monkeypatch) -> None:
    cli._app = None
    monkeypatch.delenv("NUCLEUS_APPLE_MCP_CONFIG", raising=False)

    result = runner.invoke(
        cli.get_app(),
        ["--config-file", "/tmp/nucleus-config.toml", "health", "list-sample-catalog"],
    )

    assert result.exit_code == 0
    assert os.environ["NUCLEUS_APPLE_MCP_CONFIG"] == "/tmp/nucleus-config.toml"
