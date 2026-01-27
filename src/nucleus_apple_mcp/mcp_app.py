from __future__ import annotations

from fastmcp import FastMCP

from .tools.calendar import calendar_router
from .tools.reminders import reminders_router


def create_app() -> FastMCP:
    return FastMCP(
        name="nucleus-apple-mcp",
        instructions="Nucleus Apple MCP server (macOS EventKit via Swift sidecar).",
        providers=[calendar_router, reminders_router],
    )
