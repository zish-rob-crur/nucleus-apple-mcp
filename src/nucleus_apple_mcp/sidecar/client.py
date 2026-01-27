from __future__ import annotations

import json
import subprocess
from typing import Any

from .builder import SidecarBuild, build_sidecar


def run_sidecar_cmd(
    argv: list[str],
    *,
    stdin: str | None = None,
    timeout_s: float | None = 30,
    force_rebuild: bool = False,
) -> tuple[SidecarBuild, dict[str, Any]]:
    build = build_sidecar(force_rebuild=force_rebuild)

    proc = subprocess.run(
        [str(build.exe_path), *argv],
        input=stdin,
        text=True,
        capture_output=True,
        timeout=timeout_s,
        check=False,
    )

    stdout = proc.stdout.strip()
    if not stdout:
        raise RuntimeError(f"Sidecar produced no stdout. stderr:\n{proc.stderr}")

    try:
        response = json.loads(stdout)
    except json.JSONDecodeError as exc:
        raise RuntimeError(
            "Failed to parse sidecar JSON response.\n"
            f"exit={proc.returncode}\n"
            f"stdout:\n{proc.stdout}\n"
            f"stderr:\n{proc.stderr}\n"
        ) from exc

    if not isinstance(response, dict):
        raise RuntimeError(f"Sidecar response is not a JSON object: {type(response).__name__}")

    return build, response
