from __future__ import annotations

from typing import Annotated, Any, Literal

from fastmcp import FastMCP
from fastmcp.exceptions import ToolError
from pydantic import Field

from ..sidecar.client import run_sidecar_cmd

reminders_router = FastMCP(name="reminders")


def _run_sidecar_json(argv: list[str]) -> dict[str, Any]:
    _build, response = run_sidecar_cmd(argv)

    ok = bool(response.get("ok"))
    if not ok:
        error = response.get("error") or {}
        code = error.get("code", "INTERNAL")
        message = error.get("message", "Unknown error")
        raise ToolError(f"{code}: {message}")

    result = response.get("result")
    if not isinstance(result, dict):
        raise ToolError("INTERNAL: Sidecar returned an unexpected result type.")
    return result


@reminders_router.tool(name="reminders.list_sources", description="List reminder sources/accounts.")
def list_sources(
    include_empty: Annotated[
        bool,
        Field(description="Include sources with zero visible (non-hidden) lists."),
    ] = False,
) -> dict[str, Any]:
    argv = ["reminders", "sources"]
    if include_empty:
        argv.append("--include-empty")
    return _run_sidecar_json(argv)


@reminders_router.tool(name="reminders.list_lists", description="List reminder lists.")
def list_lists(
    source_id: Annotated[
        list[str] | None,
        Field(description="Filter by source identifier (repeatable)."),
    ] = None,
    include_hidden: Annotated[
        bool,
        Field(description="Include hidden lists."),
    ] = False,
) -> dict[str, Any]:
    argv = ["reminders", "lists"]
    for sid in source_id or []:
        argv += ["--source-id", sid]
    if include_hidden:
        argv.append("--include-hidden")
    return _run_sidecar_json(argv)


@reminders_router.tool(name="reminders.list_reminders", description="List reminders by filters.")
def list_reminders(
    start: Annotated[
        str | None,
        Field(description="Filter lower bound for reminder start (ISO-8601 datetime or YYYY-MM-DD)."),
    ] = None,
    end: Annotated[
        str | None,
        Field(description="Filter upper bound for reminder start (ISO-8601 datetime or YYYY-MM-DD)."),
    ] = None,
    due_start: Annotated[
        str | None,
        Field(description="Filter lower bound for reminder due (ISO-8601 datetime or YYYY-MM-DD)."),
    ] = None,
    due_end: Annotated[
        str | None,
        Field(description="Filter upper bound for reminder due (ISO-8601 datetime or YYYY-MM-DD)."),
    ] = None,
    list_id: Annotated[
        list[str] | None,
        Field(description="Filter by list identifier (repeatable)."),
    ] = None,
    source_id: Annotated[
        list[str] | None,
        Field(description="Filter by source identifier (repeatable)."),
    ] = None,
    status: Annotated[
        Literal["open", "completed", "all"],
        Field(description="Filter by completion status."),
    ] = "open",
    limit: Annotated[
        int,
        Field(description="Limit number of reminders returned.", gt=0),
    ] = 200,
) -> dict[str, Any]:
    argv: list[str] = ["reminders", "reminders"]
    if start is not None:
        argv += ["--start", start]
    if end is not None:
        argv += ["--end", end]
    if due_start is not None:
        argv += ["--due-start", due_start]
    if due_end is not None:
        argv += ["--due-end", due_end]
    for lid in list_id or []:
        argv += ["--list-id", lid]
    for sid in source_id or []:
        argv += ["--source-id", sid]
    if status != "open":
        argv += ["--status", status]
    if limit != 200:
        argv += ["--limit", str(limit)]
    return _run_sidecar_json(argv)


@reminders_router.tool(name="reminders.create_reminder", description="Create a reminder.")
def create_reminder(
    list_id: Annotated[
        str,
        Field(description="List identifier."),
    ],
    title: Annotated[
        str,
        Field(description="Reminder title."),
    ],
    start: Annotated[
        str | None,
        Field(description="Start date/time (ISO-8601 datetime or YYYY-MM-DD)."),
    ] = None,
    due: Annotated[
        str | None,
        Field(description="Due date/time (ISO-8601 datetime or YYYY-MM-DD)."),
    ] = None,
    notes: Annotated[
        str | None,
        Field(description="Reminder notes."),
    ] = None,
    url: Annotated[
        str | None,
        Field(description="Reminder url."),
    ] = None,
    priority: Annotated[
        int,
        Field(description="Priority (0-9; 0 means none).", ge=0, le=9),
    ] = 0,
) -> dict[str, Any]:
    argv = [
        "reminders",
        "create-reminder",
        "--list-id",
        list_id,
        "--title",
        title,
    ]
    if start is not None:
        argv += ["--start", start]
    if due is not None:
        argv += ["--due", due]
    if notes is not None:
        argv += ["--notes", notes]
    if url is not None:
        argv += ["--url", url]
    if priority != 0:
        argv += ["--priority", str(priority)]
    return _run_sidecar_json(argv)


@reminders_router.tool(name="reminders.update_reminder", description="Update an existing reminder.")
def update_reminder(
    reminder_id: Annotated[
        str,
        Field(description="Reminder identifier."),
    ],
    list_id: Annotated[
        str | None,
        Field(description="Move the reminder to another list (list must be writable)."),
    ] = None,
    title: Annotated[
        str | None,
        Field(description="Reminder title."),
    ] = None,
    start: Annotated[
        str | None,
        Field(description="Start date/time (ISO-8601 datetime or YYYY-MM-DD)."),
    ] = None,
    clear_start: Annotated[
        bool,
        Field(description="Clear start."),
    ] = False,
    due: Annotated[
        str | None,
        Field(description="Due date/time (ISO-8601 datetime or YYYY-MM-DD)."),
    ] = None,
    clear_due: Annotated[
        bool,
        Field(description="Clear due."),
    ] = False,
    notes: Annotated[
        str | None,
        Field(description="Reminder notes."),
    ] = None,
    clear_notes: Annotated[
        bool,
        Field(description="Clear notes."),
    ] = False,
    url: Annotated[
        str | None,
        Field(description="Reminder url."),
    ] = None,
    clear_url: Annotated[
        bool,
        Field(description="Clear url."),
    ] = False,
    priority: Annotated[
        int | None,
        Field(description="Priority (0-9; 0 means none).", ge=0, le=9),
    ] = None,
    clear_priority: Annotated[
        bool,
        Field(description="Clear priority (reset to 0)."),
    ] = False,
    completed: Annotated[
        bool | None,
        Field(description="Set completion status (true/false)."),
    ] = None,
) -> dict[str, Any]:
    argv: list[str] = [
        "reminders",
        "update-reminder",
        "--reminder-id",
        reminder_id,
    ]
    if list_id is not None:
        argv += ["--list-id", list_id]
    if title is not None:
        argv += ["--title", title]
    if start is not None:
        argv += ["--start", start]
    if clear_start:
        argv.append("--clear-start")
    if due is not None:
        argv += ["--due", due]
    if clear_due:
        argv.append("--clear-due")
    if notes is not None:
        argv += ["--notes", notes]
    if clear_notes:
        argv.append("--clear-notes")
    if url is not None:
        argv += ["--url", url]
    if clear_url:
        argv.append("--clear-url")
    if priority is not None:
        argv += ["--priority", str(priority)]
    if clear_priority:
        argv.append("--clear-priority")
    if completed is not None:
        argv += ["--completed", "true" if completed else "false"]
    return _run_sidecar_json(argv)


@reminders_router.tool(name="reminders.delete_reminder", description="Delete a reminder.")
def delete_reminder(
    reminder_id: Annotated[
        str,
        Field(description="Reminder identifier."),
    ],
) -> dict[str, Any]:
    argv = [
        "reminders",
        "delete-reminder",
        "--reminder-id",
        reminder_id,
    ]
    return _run_sidecar_json(argv)
