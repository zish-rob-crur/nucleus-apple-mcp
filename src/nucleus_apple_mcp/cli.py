from __future__ import annotations

import asyncio
import inspect
import json
import sys
from collections import defaultdict
from typing import Any

import click
import typer
from fastmcp.exceptions import ToolError
from pydantic import ValidationError

from . import apply_config_file, run_mcp_server
from .mcp_app import create_app

_CONTEXT_SETTINGS = {"help_option_names": ["-h", "--help"]}
_CONFIG_HELP = "Path to a TOML config file. Defaults to ~/.config/nucleus-apple-mcp/config.toml"
_PRETTY_HELP = "Pretty-print JSON output."

_app: typer.Typer | None = None


def _resolve_schema(schema: dict[str, Any], defs: dict[str, Any]) -> dict[str, Any]:
    if "$ref" in schema:
        ref_name = schema["$ref"].rpartition("/")[-1]
        return _resolve_schema(defs[ref_name], defs)

    if "anyOf" in schema:
        variants = [_resolve_schema(variant, defs) for variant in schema["anyOf"]]
        non_null = [variant for variant in variants if variant.get("type") != "null"]
        if len(non_null) == 1:
            merged = dict(non_null[0])
            for key in ("description", "default", "minimum", "maximum", "title"):
                if key in schema and key not in merged:
                    merged[key] = schema[key]
            return merged

    resolved = dict(schema)
    items = resolved.get("items")
    if isinstance(items, dict):
        resolved["items"] = _resolve_schema(items, defs)
    return resolved


def _dump_json(payload: Any, *, pretty: bool, stream: Any | None = None) -> None:
    target = stream or sys.stdout
    json.dump(
        payload,
        target,
        ensure_ascii=False,
        indent=2 if pretty else None,
        separators=None if pretty else (",", ":"),
    )
    target.write("\n")


def _command_name(raw_name: str) -> str:
    return raw_name.replace("_", "-")


def _help_text(schema: dict[str, Any]) -> str | None:
    description = schema.get("description")
    if schema.get("type") != "integer":
        return description

    suffixes: list[str] = []
    if "minimum" in schema:
        suffixes.append(f"(min: {schema['minimum']})")
    if "maximum" in schema:
        suffixes.append(f"(max: {schema['maximum']})")
    if not suffixes:
        return description
    if description:
        return f"{description} {' '.join(suffixes)}"
    return " ".join(suffixes)


def _annotation_for_schema(schema: dict[str, Any], *, required: bool) -> Any:
    schema_type = schema.get("type")
    default = schema.get("default")

    if schema_type == "boolean":
        return bool if required or default is not None else bool | None
    if schema_type == "integer":
        return int if required or default is not None else int | None
    if schema_type == "string":
        return str if required or default is not None else str | None
    if schema_type == "array":
        list_type = list[str]
        return list_type if required or default is not None else list_type | None

    raise ValueError(f"Unsupported schema type: {schema}")


def _click_type_for_schema(schema: dict[str, Any]) -> click.ParamType | None:
    if schema.get("type") == "string" and "enum" in schema:
        return click.Choice(schema["enum"], case_sensitive=True)

    if schema.get("type") == "array":
        item_schema = schema.get("items", {})
        if "enum" in item_schema:
            return click.Choice(item_schema["enum"], case_sensitive=True)

    return None


def _show_default(default: Any) -> bool:
    return default not in (None, False, [])


def _option_info_for_param(name: str, schema: dict[str, Any], *, required: bool) -> Any:
    default = ... if required else schema.get("default")
    option_name = f"--{_command_name(name)}"
    option_kwargs: dict[str, Any] = {
        "help": _help_text(schema),
        "show_default": _show_default(default),
    }

    click_type = _click_type_for_schema(schema)
    if click_type is not None:
        option_kwargs["click_type"] = click_type

    if schema.get("type") == "integer":
        option_kwargs["min"] = schema.get("minimum")
        option_kwargs["max"] = schema.get("maximum")

    if schema.get("type") == "boolean":
        if default is False:
            return typer.Option(False, option_name, **option_kwargs)

        return typer.Option(default, f"{option_name}/--no-{_command_name(name)}", **option_kwargs)

    return typer.Option(default, option_name, **option_kwargs)


def _config_option() -> Any:
    return typer.Option(None, "--config-file", help=_CONFIG_HELP, show_default=False)


def _pretty_option() -> Any:
    return typer.Option(False, "--pretty", help=_PRETTY_HELP, show_default=False)


def _common_parameters() -> list[inspect.Parameter]:
    return [
        inspect.Parameter(
            "pretty",
            inspect.Parameter.POSITIONAL_OR_KEYWORD,
            annotation=bool,
            default=_pretty_option(),
        ),
    ]


async def _invoke_tool(tool: Any, arguments: dict[str, Any], *, pretty: bool) -> None:
    try:
        result = await tool.run(arguments)
    except (ToolError, ValidationError, ValueError) as exc:
        _dump_json(
            {
                "ok": False,
                "error": {
                    "type": exc.__class__.__name__,
                    "message": str(exc),
                },
            },
            pretty=pretty,
            stream=sys.stderr,
        )
        raise typer.Exit(code=1) from exc

    payload = result.structured_content if result.structured_content is not None else result.content
    _dump_json(payload, pretty=pretty)


def _make_tool_callback(tool: Any) -> Any:
    def callback(**kwargs: Any) -> None:
        pretty = bool(kwargs.pop("pretty", False))
        asyncio.run(_invoke_tool(tool, kwargs, pretty=pretty))

    callback.__name__ = tool.name.replace(".", "_")
    callback.__doc__ = tool.description

    schema = tool.parameters
    defs = schema.get("$defs", {})
    required_names = set(schema.get("required", []))
    parameters = _common_parameters()

    for param_name, raw_param_schema in schema.get("properties", {}).items():
        resolved_schema = _resolve_schema(raw_param_schema, defs)
        parameters.append(
            inspect.Parameter(
                param_name,
                inspect.Parameter.POSITIONAL_OR_KEYWORD,
                annotation=_annotation_for_schema(resolved_schema, required=param_name in required_names),
                default=_option_info_for_param(param_name, resolved_schema, required=param_name in required_names),
            )
        )

    callback.__signature__ = inspect.Signature(parameters)
    return callback


def _make_typer_app(*, help_text: str | None = None) -> typer.Typer:
    return typer.Typer(
        add_completion=False,
        no_args_is_help=True,
        help=help_text,
        context_settings=_CONTEXT_SETTINGS,
    )


async def _build_typer_app() -> typer.Typer:
    root = _make_typer_app(
        help_text="Nucleus Apple CLI for Calendar, Reminders, Notes, Health, and MCP server operations.",
    )
    tools = await create_app().get_tools()

    @root.callback()
    def root_callback(
        config_file: str | None = _config_option(),
    ) -> None:
        apply_config_file(config_file)

    grouped_names: dict[str, list[Any]] = defaultdict(list)
    for tool_name in sorted(tools):
        namespace, _ = tool_name.split(".", maxsplit=1)
        grouped_names[namespace].append(tools[tool_name])

    for namespace, namespace_tools in sorted(grouped_names.items()):
        namespace_app = _make_typer_app(help_text=f"{namespace} commands")
        for tool in namespace_tools:
            _, command_name = tool.name.split(".", maxsplit=1)
            namespace_app.command(name=_command_name(command_name), help=tool.description)(_make_tool_callback(tool))
        root.add_typer(namespace_app, name=namespace, help=f"{namespace} commands")

    mcp_app = _make_typer_app(help_text="Run the MCP server over stdio.")

    @mcp_app.command("serve", help="Run the MCP server over stdio.")
    def serve() -> None:
        run_mcp_server()

    root.add_typer(mcp_app, name="mcp", help="Run the MCP server over stdio.")
    return root


def get_app() -> typer.Typer:
    global _app
    if _app is None:
        _app = asyncio.run(_build_typer_app())
    return _app


def main(argv: list[str] | None = None) -> None:
    get_app()(args=argv, prog_name="nucleus-apple")
