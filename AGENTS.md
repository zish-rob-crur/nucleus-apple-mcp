# Repository Guidelines

## Project Structure & Module Organization

- `src/nucleus_apple_mcp/`: Python MCP server (FastMCP). Entry points: `__main__.py`, `mcp_app.py`.
- `src/nucleus_apple_mcp/tools/`: MCP tool routers (e.g., `calendar.py`, `reminders.py`).
- `src/nucleus_apple_mcp/sidecar/`: Python helpers to build/run the native sidecar and manage caching.
- `src/nucleus_apple_mcp/sidecar/swift/`: SwiftPM package for the `nucleus-apple-sidecar` executable (EventKit).
- `docs/specs/`: Notes/specs for tool behavior and payload shapes.

## Build, Test, and Development Commands

Prereqs: macOS 12+, Python `>=3.10`, and Xcode Command Line Tools (Swift).

- `uv sync`: Create/update the local virtual environment from `uv.lock`.
- `uv run nucleus-apple-mcp` (or `python -m nucleus_apple_mcp`): Run the MCP server over stdio.
- `just --list`: Show available Swift sidecar dev commands.
- `just sidecar-run`: Run a basic sidecar “ping” smoke test.
- `just sidecar-help`: Show the sidecar CLI help (ArgumentParser).

The first server run compiles the Swift sidecar and caches it under `~/Library/Caches/nucleus-apple-mcp/…` (override with `NUCLEUS_APPLE_MCP_CACHE_DIR`). You can also set `NUCLEUS_SWIFT` / `NUCLEUS_SWIFTC` to override toolchain paths.

## Coding Style & Naming Conventions

- Python: 4-space indentation; prefer type hints; keep modules/functions `snake_case` and classes `CapWords`.
- Swift: follow Swift API Design Guidelines; keep CLI JSON responses stable and backward compatible.
- Avoid committing generated artifacts (e.g., `.venv/`, `__pycache__/`, Swift `.build/` outputs).

## Testing Guidelines

There is no automated test suite in this repository yet. For validation:

- Run `uv run nucleus-apple-mcp` and exercise tools via an MCP client (Calendar/Reminders permissions required).
- Run relevant sidecar commands via `just` (e.g., `just sidecar-run`, `just sidecar "echo --payload '{\"x\":2}'"`).

If you add tests, use `pytest` and place them under a top-level `tests/` directory with `test_*.py` naming.

## Commit & Pull Request Guidelines

- Commit messages follow Conventional Commits (examples in history: `fix: …`, `chore: …`).
- PRs should include: a short summary, the exact test commands you ran, macOS version, and any new privacy/permission implications (EventKit reads/writes). Link related issues when applicable.

