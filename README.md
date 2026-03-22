# ⚛️ Nucleus: macOS Life Context Server

**Give your AI Agent a Hippocampus.**

`nucleus-apple-mcp` is a Model Context Protocol (MCP) server designed to unify your digital life on macOS. It allows AI agents (like Claude Desktop, Cursor, or custom agents) to securely read and interact with your personal data ecosystem.

Unlike fragile PyObjC bridges, **Nucleus** uses a hybrid architecture: a Python MCP server that orchestrates lightweight, JIT-compiled native Swift workers. This ensures type-safe, performant, and reliable access to Apple's native APIs while remaining easily distributable via `uvx`.

## 🔌 Integrations

### ✅ Available (current release)

* **📅 Calendar:** Fetch upcoming schedules, check availability, and create events via `EventKit`.
* **✅ Reminders:** Read pending tasks and manage your to-do lists via `EventKit`.
* **📝 Notes:** List/search notes, read content, and add/export attachments via Notes.app (Apple Events).
* **❤️ Health:** Read exported Apple Health metrics and raw samples from an S3-compatible object store.

### 🏗 Architecture

* **Python:** Handles the MCP protocol, request routing, and distribution (pip/uv).
* **Swift:** Embedded source code acts as a "Sidecar." It is compiled locally on the first run (using SwiftPM `swift build`) to interface directly with macOS private frameworks, bypassing the limitations of Python-Objective-C bridges.

### 📦 Swift Sidecar Layout

* **Swift Package Root:** `src/nucleus_apple_mcp/sidecar/swift/` (includes `Package.swift`; CLI uses `swift-argument-parser`)
* **Build Cache (macOS):** `~/Library/Caches/nucleus-apple-mcp/sidecar/<build_id>/nucleus-apple-sidecar`
* **Optional Env Vars:** `NUCLEUS_APPLE_MCP_CACHE_DIR` (overrides cache directory), `NUCLEUS_SWIFT` (swift path), `NUCLEUS_SWIFTC` (swiftc path)

### 🚀 Usage

```bash
# Run the CLI directly.
uvx --from nucleus-apple-mcp nucleus-apple health list-sample-catalog

# Or run the MCP server.
uvx nucleus-apple-mcp
```

## 🧰 CLI

Install the package once and use the unified `nucleus-apple` command:

```bash
uv tool install nucleus-apple-mcp
```

Examples:

```bash
# Calendar
nucleus-apple calendar list-events --start 2026-03-15T09:00:00+08:00 --end 2026-03-15T18:00:00+08:00 --pretty

# Reminders
nucleus-apple reminders list-reminders --due-end 2026-03-20 --pretty

# Notes
nucleus-apple notes list-notes --query project --include-plaintext-excerpt --pretty

# Health
nucleus-apple health read-daily-metrics --date 2026-03-14 --pretty
```

The CLI mirrors the MCP tool surface and emits JSON, which makes it suitable for shell automation and OpenClaw-style skills.

## 🔧 Add as an MCP server

This server uses the **stdio** transport (a local subprocess). The first run will compile the Swift sidecar.

### Codex CLI

```bash
# Add the server (writes to ~/.codex/config.toml)
codex mcp add nucleus-apple -- uvx nucleus-apple-mcp

# Verify
codex mcp list
```

### Claude Code

```bash
# Add the server (use --scope user to make it available globally)
claude mcp add --scope user nucleus-apple -- uvx nucleus-apple-mcp

# Verify
claude mcp list
```

You can also launch the server through the CLI:

```bash
nucleus-apple mcp serve
```

## 🪝 OpenClaw Skills

This repository includes OpenClaw-ready skills under `skills/` for:

* `nucleus-apple-calendar`
* `nucleus-apple-reminders`
* `nucleus-apple-notes`
* `nucleus-apple-health`

Each skill depends on the `nucleus-apple` binary and is designed to be contributed upstream without changing the command surface.
