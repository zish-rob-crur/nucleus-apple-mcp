from __future__ import annotations

import argparse
import os


def apply_config_file(config_file: str | None) -> None:
    if config_file:
        os.environ["NUCLEUS_APPLE_MCP_CONFIG"] = os.path.expanduser(config_file)


def run_mcp_server(*, config_file: str | None = None) -> None:
    apply_config_file(config_file)

    from .mcp_app import create_app

    app = create_app()
    app.run(transport="stdio")


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description="Run the Nucleus Apple MCP server.")
    parser.add_argument(
        "--config-file",
        dest="config_file",
        help="Path to a TOML config file. Defaults to ~/.config/nucleus-apple-mcp/config.toml",
    )
    args = parser.parse_args(argv)
    run_mcp_server(config_file=args.config_file)
