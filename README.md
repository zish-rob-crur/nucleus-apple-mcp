# ⚛️ Nucleus: macOS Life Context Server

**Give your AI Agent a Hippocampus.**

`nucleus-apple-mcp` is a Model Context Protocol (MCP) server designed to unify your digital life on macOS. It allows AI agents (like Claude Desktop, Cursor, or custom agents) to securely read and interact with your personal data ecosystem.

Unlike fragile PyObjC bridges, **Nucleus** uses a hybrid architecture: a Python MCP server that orchestrates lightweight, JIT-compiled native Swift workers. This ensures type-safe, performant, and reliable access to Apple's native APIs while remaining easily distributable via `uvx`.

## 🔌 Integrations

* **📅 Calendar:** Fetch upcoming schedules, check availability, and create events via `EventKit`.
* **✅ Reminders:** Read pending tasks and manage your to-do lists via `EventKit`.
* **📝 Notes:** Access your Apple Notes database (The "Second Brain" memory layer).
* **❤️ Health:** Ingest health metrics (Sleep, HR, Activity) via iOS-to-Mac iCloud exports.

### 🏗 Architecture

* **Python:** Handles the MCP protocol, request routing, and distribution (pip/uv).
* **Swift:** Embedded source code acts as a "Sidecar." It is compiled locally on the first run (using SwiftPM `swift build`) to interface directly with macOS private frameworks, bypassing the limitations of Python-Objective-C bridges.

### 📦 Swift Sidecar Layout

* **Swift Package Root:** `src/nucleus_apple_mcp/sidecar/swift/` (includes `Package.swift`; CLI uses `swift-argument-parser`)
* **Build Cache (macOS):** `~/Library/Caches/nucleus-apple-mcp/sidecar/<build_id>/nucleus-apple-sidecar`
* **Optional Env Vars:** `NUCLEUS_APPLE_MCP_CACHE_DIR` (overrides cache directory), `NUCLEUS_SWIFT` (swift path), `NUCLEUS_SWIFTC` (swiftc path)

### 🚀 Usage

```bash
# No manual compilation required.
# The Python wrapper handles the local Swift build automatically.
uvx nucleus-apple-mcp
```
