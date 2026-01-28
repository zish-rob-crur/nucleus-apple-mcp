from __future__ import annotations

from fastmcp import FastMCP

from .tools.calendar import calendar_router
from .tools.reminders import reminders_router


def create_app() -> FastMCP:
    app = FastMCP(
        name="nucleus-apple-mcp",
        instructions="Nucleus Apple MCP server (macOS EventKit via Swift sidecar).",
    )

    app.mount(calendar_router)
    app.mount(reminders_router)
    return app
