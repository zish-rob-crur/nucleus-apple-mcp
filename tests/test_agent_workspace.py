from __future__ import annotations

import os
import stat
import subprocess
from pathlib import Path

import pytest


REPO_ROOT = Path(__file__).resolve().parents[1]
WORKSPACE_ROOT = REPO_ROOT / "tests" / "agent-workspace"
SKILLS_ROOT = REPO_ROOT / "skills"


def test_agent_workspace_symlinks_cover_supported_skill_roots() -> None:
    expected = sorted(path.name for path in SKILLS_ROOT.iterdir() if path.is_dir())

    for root_name in (".agents", ".claude"):
        skill_root = WORKSPACE_ROOT / root_name / "skills"
        assert skill_root.is_dir()

        linked = sorted(path.name for path in skill_root.iterdir())
        assert linked == expected

        for skill_name in linked:
            link = skill_root / skill_name
            assert link.is_symlink()
            assert link.resolve() == SKILLS_ROOT / skill_name


def test_agent_workspace_wrappers_are_executable() -> None:
    for command_name in ("nucleus-apple", "nucleus-apple-mcp"):
        wrapper = WORKSPACE_ROOT / "bin" / command_name
        mode = wrapper.stat().st_mode
        assert mode & stat.S_IXUSR


def test_agent_workspace_local_cli_wrapper_runs_help() -> None:
    wrapper = WORKSPACE_ROOT / "bin" / "nucleus-apple"
    env = os.environ.copy()
    env["NUCLEUS_AGENT_WORKSPACE_CLI_MODE"] = "local"

    result = subprocess.run(
        [str(wrapper), "--help"],
        cwd=REPO_ROOT,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0
    assert "Nucleus Apple CLI" in result.stdout


@pytest.mark.skipif(
    os.environ.get("NUCLEUS_AGENT_WORKSPACE_TEST_PYPI") != "1",
    reason="Set NUCLEUS_AGENT_WORKSPACE_TEST_PYPI=1 to validate the published package path.",
)
def test_agent_workspace_pypi_cli_wrapper_runs_help() -> None:
    wrapper = WORKSPACE_ROOT / "bin" / "nucleus-apple"
    env = os.environ.copy()
    env["NUCLEUS_AGENT_WORKSPACE_CLI_MODE"] = "pypi"

    result = subprocess.run(
        [str(wrapper), "--help"],
        cwd=REPO_ROOT,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0
    assert "Nucleus Apple CLI" in result.stdout
