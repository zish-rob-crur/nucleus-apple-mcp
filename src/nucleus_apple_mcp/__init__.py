from __future__ import annotations


def main() -> None:
    from .mcp_app import create_app

    app = create_app()
    app.run(transport="stdio")

