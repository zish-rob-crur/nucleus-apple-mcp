# Agent Workspace Fixture

This workspace is a test fixture for agent-facing skill integration.

It mirrors the two skill locations used by current agent tooling:

- `.agents/skills`
- `.claude/skills`

Both trees symlink back to the canonical repo `skills/` directory, so there is only one source of
truth for the skill content.

## CLI mode

The workspace wrappers under `bin/` support two CLI modes:

- `local`
  - default
  - runs the local development checkout through `uv run --project <repo>`
- `pypi`
  - runs the published package through `uvx --from nucleus-apple-mcp ...`

Switch modes with:

```bash
export PATH="$PWD/tests/agent-workspace/bin:$PATH"
export NUCLEUS_AGENT_WORKSPACE_CLI_MODE=local
```

Or:

```bash
export PATH="$PWD/tests/agent-workspace/bin:$PATH"
export NUCLEUS_AGENT_WORKSPACE_CLI_MODE=pypi
```

With that PATH in place, agents and manual shell tests can invoke:

```bash
nucleus-apple --help
nucleus-apple-mcp --help
```

## Why this fixture exists

The local mode is the fast feedback loop for development.

The PyPI mode is the packaging check. It exercises the same skill surface through the published
package instead of the current checkout.

That separation keeps the wrapper logic simple and makes failures easier to interpret:

- if `local` fails, the repo is broken
- if `pypi` fails, the published package or publish pipeline is behind the repo
