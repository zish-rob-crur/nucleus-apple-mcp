from __future__ import annotations

from typing import Annotated, Any, Literal

from fastmcp import FastMCP
from fastmcp.exceptions import ToolError
from pydantic import Field

from ..sidecar.client import run_sidecar_cmd

calendar_router = FastMCP(name="calendar")


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


@calendar_router.tool(name="calendar.list_sources", description="List calendar sources/accounts.")
def list_sources(
    include_empty: Annotated[
        bool,
        Field(description="Include sources with zero visible (non-hidden) calendars."),
    ] = False,
) -> dict[str, Any]:
    argv = ["calendar", "sources"]
    if include_empty:
        argv.append("--include-empty")
    return _run_sidecar_json(argv)


@calendar_router.tool(name="calendar.list_calendars", description="List event calendars.")
def list_calendars(
    source_id: Annotated[
        list[str] | None,
        Field(description="Filter by source identifier (repeatable)."),
    ] = None,
    include_hidden: Annotated[
        bool,
        Field(description="Include hidden calendars."),
    ] = False,
) -> dict[str, Any]:
    argv = ["calendar", "calendars"]
    for sid in source_id or []:
        argv += ["--source-id", sid]
    if include_hidden:
        argv.append("--include-hidden")
    return _run_sidecar_json(argv)


@calendar_router.tool(name="calendar.list_events", description="List events within a time range.")
def list_events(
    start: Annotated[
        str,
        Field(description="Start datetime (ISO-8601)."),
    ],
    end: Annotated[
        str,
        Field(description="End datetime (ISO-8601). Must be after start."),
    ],
    calendar_id: Annotated[
        list[str] | None,
        Field(description="Filter by calendar identifier (repeatable)."),
    ] = None,
    source_id: Annotated[
        list[str] | None,
        Field(description="Filter by source identifier (repeatable)."),
    ] = None,
    include_details: Annotated[
        bool,
        Field(description="Include optional fields like location/notes/url."),
    ] = False,
    limit: Annotated[
        int | None,
        Field(description="Limit number of events returned.", gt=0),
    ] = None,
) -> dict[str, Any]:
    argv = [
        "calendar",
        "events",
        "--start",
        start,
        "--end",
        end,
    ]
    for cid in calendar_id or []:
        argv += ["--calendar-id", cid]
    for sid in source_id or []:
        argv += ["--source-id", sid]
    if include_details:
        argv.append("--include-details")
    if limit is not None:
        argv += ["--limit", str(limit)]
    return _run_sidecar_json(argv)


@calendar_router.tool(name="calendar.create_event", description="Create a calendar event.")
def create_event(
    calendar_id: Annotated[
        str,
        Field(description="Calendar identifier."),
    ],
    title: Annotated[
        str,
        Field(description="Event title."),
    ],
    start: Annotated[
        str,
        Field(description="Start datetime (ISO-8601)."),
    ],
    end: Annotated[
        str,
        Field(description="End datetime (ISO-8601). Must be after start."),
    ],
    all_day: Annotated[
        bool,
        Field(description="Create as an all-day event."),
    ] = False,
    location: Annotated[
        str | None,
        Field(description="Event location."),
    ] = None,
    notes: Annotated[
        str | None,
        Field(description="Event notes."),
    ] = None,
    url: Annotated[
        str | None,
        Field(description="Event url."),
    ] = None,
    availability: Annotated[
        Literal["busy", "free", "tentative", "unavailable"] | None,
        Field(description="Event availability."),
    ] = None,
) -> dict[str, Any]:
    argv = [
        "calendar",
        "create-event",
        "--calendar-id",
        calendar_id,
        "--title",
        title,
        "--start",
        start,
        "--end",
        end,
    ]
    if all_day:
        argv.append("--all-day")
    if location is not None:
        argv += ["--location", location]
    if notes is not None:
        argv += ["--notes", notes]
    if url is not None:
        argv += ["--url", url]
    if availability is not None:
        argv += ["--availability", availability]
    return _run_sidecar_json(argv)


@calendar_router.tool(name="calendar.update_event", description="Update an existing calendar event.")
def update_event(
    event_id: Annotated[
        str,
        Field(description="Event identifier."),
    ],
    span: Annotated[
        Literal["this", "future"],
        Field(description="Apply changes to this or future events (recurrence)."),
    ] = "this",
    calendar_id: Annotated[
        str | None,
        Field(description="Move the event to another calendar (calendar must be writable)."),
    ] = None,
    title: Annotated[
        str | None,
        Field(description="Event title."),
    ] = None,
    start: Annotated[
        str | None,
        Field(description="Start datetime (ISO-8601)."),
    ] = None,
    end: Annotated[
        str | None,
        Field(description="End datetime (ISO-8601)."),
    ] = None,
    is_all_day: Annotated[
        bool | None,
        Field(description="Explicitly set all-day status (true/false)."),
    ] = None,
    location: Annotated[
        str | None,
        Field(description="Event location."),
    ] = None,
    clear_location: Annotated[
        bool,
        Field(description="Clear location."),
    ] = False,
    notes: Annotated[
        str | None,
        Field(description="Event notes."),
    ] = None,
    clear_notes: Annotated[
        bool,
        Field(description="Clear notes."),
    ] = False,
    url: Annotated[
        str | None,
        Field(description="Event url."),
    ] = None,
    clear_url: Annotated[
        bool,
        Field(description="Clear url."),
    ] = False,
    availability: Annotated[
        Literal["busy", "free", "tentative", "unavailable"] | None,
        Field(description="Event availability."),
    ] = None,
    clear_availability: Annotated[
        bool,
        Field(description="Clear availability (reset to unknown)."),
    ] = False,
) -> dict[str, Any]:
    argv: list[str] = [
        "calendar",
        "update-event",
        "--event-id",
        event_id,
    ]
    if span != "this":
        argv += ["--span", span]
    if calendar_id is not None:
        argv += ["--calendar-id", calendar_id]
    if title is not None:
        argv += ["--title", title]
    if start is not None:
        argv += ["--start", start]
    if end is not None:
        argv += ["--end", end]
    if is_all_day is not None:
        argv += ["--is-all-day", "true" if is_all_day else "false"]
    if location is not None:
        argv += ["--location", location]
    if clear_location:
        argv.append("--clear-location")
    if notes is not None:
        argv += ["--notes", notes]
    if clear_notes:
        argv.append("--clear-notes")
    if url is not None:
        argv += ["--url", url]
    if clear_url:
        argv.append("--clear-url")
    if availability is not None:
        argv += ["--availability", availability]
    if clear_availability:
        argv.append("--clear-availability")
    return _run_sidecar_json(argv)


@calendar_router.tool(name="calendar.delete_event", description="Delete a calendar event.")
def delete_event(
    event_id: Annotated[
        str,
        Field(description="Event identifier."),
    ],
    span: Annotated[
        Literal["this", "future"],
        Field(description="Delete this or future events (recurrence)."),
    ] = "this",
) -> dict[str, Any]:
    argv: list[str] = [
        "calendar",
        "delete-event",
        "--event-id",
        event_id,
    ]
    if span != "this":
        argv += ["--span", span]
    return _run_sidecar_json(argv)
