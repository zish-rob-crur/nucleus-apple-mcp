# Getting Started With Nucleus

This guide is the fastest way to get from a fresh install to a usable Nucleus setup.

The current shipping model is:

1. the iOS app exports Apple Health into private app storage
2. the app can optionally upload those exports to an S3-compatible bucket
3. the CLI and MCP server read Health data from that object store

Nucleus does not use iCloud for Health exports. That path was removed for App Store distribution,
so the current agent-readable path is private local export plus optional object-store upload.

## 1. Decide which setup you want

There are two reasonable ways to use Nucleus today.

### Option A: private local archive only

Choose this if you only want the iOS app to keep a private export on the device.

You will get:

- local Health export files
- background refresh inside the app
- widgets and Live Activity status

You will not get:

- Health reads from the CLI
- Health reads from the MCP server

### Option B: private local archive plus agent-readable object storage

Choose this if you want Codex, Claude Code, or other MCP clients to query the exported Health data.

You will get:

- everything in Option A
- a stable S3-compatible object-store copy of the Health export
- CLI and MCP access to the same exported data

For most people, Cloudflare R2 is the easiest starting point.

## 2. Set up the iOS app

1. Install and open `Nucleus` on your iPhone.
2. Grant the Health permissions you want Nucleus to export.
3. In the app, confirm that storage is set to the default private mode.
4. Run the first sync once so the initial export is created.

If you only want the private local archive, you can stop here.

## 3. Create an object-store destination

If you want CLI and MCP access, create an S3-compatible bucket.

For Cloudflare R2:

1. Create a bucket for Nucleus exports.
2. Pick a stable prefix such as `nucleus/`.
3. Create S3 API credentials scoped to that bucket.
4. Note these values:
   - account endpoint
   - bucket name
   - access key ID
   - secret access key

R2's S3 endpoint shape is:

`https://<ACCOUNT_ID>.r2.cloudflarestorage.com`

Recommended defaults:

- `region = "auto"`
- `use_path_style = true`

## 4. Connect the iOS app to the bucket

In the Nucleus app:

1. Open `Settings`.
2. Open `Object Store`.
3. Enter the bucket settings.
4. Save the credentials.
5. Run another sync.

After a successful sync, the bucket should contain the exported Health layout under your chosen
prefix, including:

- `health/daily/...`
- `health/raw/...`
- `health/commits/...`

## 5. Configure the CLI and MCP server

Create:

`~/.config/nucleus-apple-mcp/config.toml`

Example:

```toml
[health]
storage_backend = "s3_object_store"

[health.s3]
endpoint = "https://<accountid>.r2.cloudflarestorage.com"
region = "auto"
bucket = "your-bucket"
prefix = "nucleus"
access_key_id = "..."
secret_access_key = "..."
use_path_style = true
```

You can also use environment variables, but the config file is easier to maintain.

## 6. Verify the archive from the terminal

Install the package:

```bash
uv tool install nucleus-apple-mcp
```

Then run a few checks:

```bash
nucleus-apple health list-sample-catalog --pretty
nucleus-apple health read-daily-metrics --date 2026-03-14 --pretty
nucleus-apple health analyze-range --start-date 2026-03-01 --end-date 2026-03-14 --pretty
```

If these work, the exported archive is readable from the CLI.

## 7. Add Nucleus as an MCP server

### Codex CLI

```bash
codex mcp add nucleus-apple -- uvx nucleus-apple-mcp
```

### Claude Code

```bash
claude mcp add --scope user nucleus-apple -- uvx nucleus-apple-mcp
```

After that, agent workflows can read the same Health export through the MCP tool surface.

## 8. What to check if data does not appear

If CLI or MCP reads return empty data, check these in order:

1. the iOS app has already completed at least one successful sync
2. the object store upload is enabled and healthy
3. the bucket and prefix in `config.toml` match the app settings
4. the expected `health/` paths exist in the bucket
5. the requested dates are inside the exported range

## 9. Recommended first workflow

Once the setup is working, start with something small:

- run a one-day Health query from the CLI
- add the MCP server to your agent
- try a prompt that combines Calendar, Health, and Notes

That is the shortest path from "I installed Nucleus" to "I have a real agent-readable archive."
