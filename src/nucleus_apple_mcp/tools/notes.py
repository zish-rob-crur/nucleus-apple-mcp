from __future__ import annotations

from typing import Annotated, Any

from fastmcp import FastMCP
from fastmcp.exceptions import ToolError
from pydantic import Field

from ..sidecar.client import run_sidecar_cmd

notes_router = FastMCP(name="notes")


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


@notes_router.tool(name="notes.list_accounts", description="List Notes accounts.")
def list_accounts() -> dict[str, Any]:
    return _run_sidecar_json(["notes", "accounts"])


@notes_router.tool(name="notes.list_folders", description="List Notes folders.")
def list_folders(
    account_id: Annotated[
        list[str] | None,
        Field(description="Filter by account identifier (repeatable)."),
    ] = None,
    parent_folder_id: Annotated[
        str | None,
        Field(description="Filter by parent folder identifier."),
    ] = None,
    recursive: Annotated[
        bool,
        Field(description="When set, returns the entire subtree under the filter."),
    ] = False,
    include_shared: Annotated[
        bool,
        Field(description="Include shared folders."),
    ] = False,
    include_recently_deleted: Annotated[
        bool,
        Field(description='Include the system "Recently Deleted" folder (localized).'),
    ] = False,
) -> dict[str, Any]:
    argv: list[str] = ["notes", "folders"]
    for aid in account_id or []:
        argv += ["--account-id", aid]
    if parent_folder_id is not None:
        argv += ["--parent-folder-id", parent_folder_id]
    if recursive:
        argv.append("--recursive")
    if include_shared:
        argv.append("--include-shared")
    if include_recently_deleted:
        argv.append("--include-recently-deleted")
    return _run_sidecar_json(argv)


@notes_router.tool(name="notes.list_notes", description="List notes (metadata-first).")
def list_notes(
    account_id: Annotated[
        list[str] | None,
        Field(description="Filter by account identifier (repeatable)."),
    ] = None,
    folder_id: Annotated[
        list[str] | None,
        Field(description="Filter by folder identifier (repeatable)."),
    ] = None,
    query: Annotated[
        str | None,
        Field(description="Case-insensitive substring match against note name or plaintext."),
    ] = None,
    include_plaintext_excerpt: Annotated[
        bool,
        Field(description="Include a plaintext excerpt (may be slower)."),
    ] = False,
    plaintext_excerpt_max_len: Annotated[
        int,
        Field(description="Plaintext excerpt max length (must be > 0).", gt=0),
    ] = 200,
    include_shared: Annotated[
        bool,
        Field(description="Include shared notes."),
    ] = False,
    include_recently_deleted: Annotated[
        bool,
        Field(description='Include notes under the system "Recently Deleted" folder (localized).'),
    ] = False,
    limit: Annotated[
        int,
        Field(description="Limit number of notes returned (must be > 0).", gt=0),
    ] = 200,
) -> dict[str, Any]:
    argv: list[str] = ["notes", "notes"]
    for aid in account_id or []:
        argv += ["--account-id", aid]
    for fid in folder_id or []:
        argv += ["--folder-id", fid]
    if query is not None:
        argv += ["--query", query]
    if include_plaintext_excerpt:
        argv.append("--include-plaintext-excerpt")
    if plaintext_excerpt_max_len != 200:
        argv += ["--plaintext-excerpt-max-len", str(plaintext_excerpt_max_len)]
    if include_shared:
        argv.append("--include-shared")
    if include_recently_deleted:
        argv.append("--include-recently-deleted")
    if limit != 200:
        argv += ["--limit", str(limit)]
    return _run_sidecar_json(argv)


@notes_router.tool(name="notes.get_note", description="Fetch a note with optional content and attachments.")
def get_note(
    note_id: Annotated[str, Field(description="Note identifier.")],
    include_plaintext: Annotated[
        bool,
        Field(description="Include plaintext content."),
    ] = True,
    include_body_html: Annotated[
        bool,
        Field(description="Include body HTML."),
    ] = False,
    include_attachments: Annotated[
        bool,
        Field(description="Include attachments."),
    ] = True,
) -> dict[str, Any]:
    argv: list[str] = ["notes", "get-note", "--note-id", note_id]
    if not include_plaintext:
        argv.append("--no-include-plaintext")
    if include_body_html:
        argv.append("--include-body-html")
    if not include_attachments:
        argv.append("--no-include-attachments")
    return _run_sidecar_json(argv)


@notes_router.tool(name="notes.create_note", description="Create a new note.")
def create_note(
    folder_id: Annotated[
        str | None,
        Field(description="Folder identifier. If omitted, uses the default account + default folder."),
    ] = None,
    title: Annotated[
        str | None,
        Field(description="Note title."),
    ] = None,
    plaintext: Annotated[
        str | None,
        Field(description="Plaintext content (converted to HTML)."),
    ] = None,
    markdown: Annotated[
        str | None,
        Field(description="Markdown content (converted to HTML)."),
    ] = None,
    attach_file: Annotated[
        list[str] | None,
        Field(description="Add one or more attachments after note creation (repeatable)."),
    ] = None,
) -> dict[str, Any]:
    argv: list[str] = ["notes", "create-note"]
    if folder_id is not None:
        argv += ["--folder-id", folder_id]
    if title is not None:
        argv += ["--title", title]
    if plaintext is not None:
        argv += ["--plaintext", plaintext]
    if markdown is not None:
        argv += ["--markdown", markdown]
    for path in attach_file or []:
        argv += ["--attach-file", path]
    return _run_sidecar_json(argv)


@notes_router.tool(name="notes.update_note", description="Update an existing note.")
def update_note(
    note_id: Annotated[str, Field(description="Note identifier.")],
    title: Annotated[
        str | None,
        Field(description="Update note title."),
    ] = None,
    allow_destructive: Annotated[
        bool,
        Field(description="Required when using set_* operations."),
    ] = False,
    set_plaintext: Annotated[
        str | None,
        Field(description="Replace note content with plaintext (destructive)."),
    ] = None,
    set_markdown: Annotated[
        str | None,
        Field(description="Replace note content with Markdown (destructive)."),
    ] = None,
    append_plaintext: Annotated[
        str | None,
        Field(description="Append plaintext to the end of the note (best-effort)."),
    ] = None,
    append_markdown: Annotated[
        str | None,
        Field(description="Append Markdown to the end of the note (best-effort)."),
    ] = None,
    attach_file: Annotated[
        list[str] | None,
        Field(description="Add one or more attachments to the note (repeatable)."),
    ] = None,
) -> dict[str, Any]:
    argv: list[str] = ["notes", "update-note", "--note-id", note_id]
    if title is not None:
        argv += ["--title", title]
    if allow_destructive:
        argv.append("--allow-destructive")
    if set_plaintext is not None:
        argv += ["--set-plaintext", set_plaintext]
    if set_markdown is not None:
        argv += ["--set-markdown", set_markdown]
    if append_plaintext is not None:
        argv += ["--append-plaintext", append_plaintext]
    if append_markdown is not None:
        argv += ["--append-markdown", append_markdown]
    for path in attach_file or []:
        argv += ["--attach-file", path]
    return _run_sidecar_json(argv)


@notes_router.tool(name="notes.delete_note", description="Delete a note.")
def delete_note(
    note_id: Annotated[str, Field(description="Note identifier.")],
) -> dict[str, Any]:
    argv = ["notes", "delete-note", "--note-id", note_id]
    return _run_sidecar_json(argv)


@notes_router.tool(name="notes.list_attachments", description="List attachments for a note.")
def list_attachments(
    note_id: Annotated[str, Field(description="Note identifier.")],
    include_shared: Annotated[
        bool,
        Field(description="Include shared attachments."),
    ] = False,
) -> dict[str, Any]:
    argv = ["notes", "attachments", "--note-id", note_id]
    if include_shared:
        argv.append("--include-shared")
    return _run_sidecar_json(argv)


@notes_router.tool(name="notes.save_attachment", description="Export an attachment to a file path.")
def save_attachment(
    attachment_id: Annotated[str, Field(description="Attachment identifier.")],
    output_path: Annotated[str, Field(description="Output file path.")],
    overwrite: Annotated[
        bool,
        Field(description="Overwrite the output file if it exists."),
    ] = False,
) -> dict[str, Any]:
    argv = [
        "notes",
        "save-attachment",
        "--attachment-id",
        attachment_id,
        "--output-path",
        output_path,
    ]
    if overwrite:
        argv.append("--overwrite")
    return _run_sidecar_json(argv)


@notes_router.tool(name="notes.add_attachment", description="Add attachment(s) to a note from local file paths.")
def add_attachment(
    note_id: Annotated[str, Field(description="Note identifier.")],
    attach_file: Annotated[
        list[str],
        Field(description="Local file path to attach (repeatable)."),
    ],
) -> dict[str, Any]:
    argv: list[str] = ["notes", "add-attachment", "--note-id", note_id]
    for path in attach_file:
        argv += ["--attach-file", path]
    return _run_sidecar_json(argv)

