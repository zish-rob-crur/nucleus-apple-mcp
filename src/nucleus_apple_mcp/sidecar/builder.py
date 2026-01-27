from __future__ import annotations

import hashlib
import os
import platform
import shutil
import subprocess
from dataclasses import dataclass
from importlib import resources
from importlib.metadata import PackageNotFoundError, version
from pathlib import Path


@dataclass(frozen=True)
class SidecarBuild:
    build_id: str
    exe_path: Path


def build_sidecar(*, force_rebuild: bool = False) -> SidecarBuild:
    """
    Build the embedded Swift sidecar and return the executable path.

    The compiled binary is cached under a stable, user-local cache directory.
    """
    _require_darwin()

    swift_sources = resources.files("nucleus_apple_mcp").joinpath("sidecar/swift")
    with resources.as_file(swift_sources) as swift_sources_dir:
        if (swift_sources_dir / "Package.swift").exists():
            return _build_with_swiftpm(swift_sources_dir, force_rebuild=force_rebuild)
        return _build_with_swiftc(swift_sources_dir, force_rebuild=force_rebuild)


def _build_with_swiftpm(swift_sources_dir: Path, *, force_rebuild: bool) -> SidecarBuild:
    swift = _resolve_swift()

    files = _collect_files(swift_sources_dir, extra_files=("Package.swift",))
    build_id = _compute_build_id(swift_sources_dir, files, algo="swiftpm-v1")
    build_dir = _cache_root() / "sidecar" / build_id
    exe_path = build_dir / "nucleus-apple-sidecar"

    if exe_path.exists() and not force_rebuild:
        return SidecarBuild(build_id=build_id, exe_path=exe_path)

    build_dir.mkdir(parents=True, exist_ok=True)

    package_dir = build_dir / "package"
    scratch_dir = build_dir / ".build"

    if package_dir.exists():
        shutil.rmtree(package_dir)
    if scratch_dir.exists():
        shutil.rmtree(scratch_dir)

    shutil.copytree(swift_sources_dir, package_dir)

    cmd = [
        swift,
        "build",
        "-c",
        "release",
        "--product",
        "nucleus-apple-sidecar",
        "--package-path",
        str(package_dir),
        "--scratch-path",
        str(scratch_dir),
    ]
    try:
        subprocess.run(cmd, check=True, capture_output=True, text=True)
    except subprocess.CalledProcessError as exc:
        raise RuntimeError(
            "swift build failed.\n"
            f"cmd: {' '.join(cmd)}\n"
            f"stdout:\n{exc.stdout}\n"
            f"stderr:\n{exc.stderr}\n"
        ) from exc

    built_bin = _find_built_binary(scratch_dir, "nucleus-apple-sidecar")

    tmp_exe_path = exe_path.with_suffix(".tmp")
    if tmp_exe_path.exists():
        tmp_exe_path.unlink()
    shutil.copy2(str(built_bin), str(tmp_exe_path))
    shutil.move(str(tmp_exe_path), str(exe_path))

    return SidecarBuild(build_id=build_id, exe_path=exe_path)


def _build_with_swiftc(swift_sources_dir: Path, *, force_rebuild: bool) -> SidecarBuild:
    swiftc = _resolve_swiftc()

    swift_files = _collect_files(swift_sources_dir)
    build_id = _compute_build_id(swift_sources_dir, swift_files, algo="swiftc-v1")
    build_dir = _cache_root() / "sidecar" / build_id
    exe_path = build_dir / "nucleus-apple-sidecar"

    if exe_path.exists() and not force_rebuild:
        return SidecarBuild(build_id=build_id, exe_path=exe_path)

    build_dir.mkdir(parents=True, exist_ok=True)
    tmp_exe_path = exe_path.with_suffix(".tmp")
    if tmp_exe_path.exists():
        tmp_exe_path.unlink()

    cmd = [
        swiftc,
        "-O",
        "-o",
        str(tmp_exe_path),
        *[str(p) for p in swift_files],
    ]
    try:
        subprocess.run(cmd, check=True, capture_output=True, text=True)
    except subprocess.CalledProcessError as exc:
        raise RuntimeError(
            "swiftc build failed.\n"
            f"cmd: {' '.join(cmd)}\n"
            f"stdout:\n{exc.stdout}\n"
            f"stderr:\n{exc.stderr}\n"
        ) from exc

    shutil.move(str(tmp_exe_path), str(exe_path))
    return SidecarBuild(build_id=build_id, exe_path=exe_path)


def _resolve_swift() -> str:
    swift = os.environ.get("NUCLEUS_SWIFT") or os.environ.get("SWIFT") or "swift"
    if shutil.which(swift) is None:
        raise RuntimeError(
            f"swift not found: {swift!r}. Install Xcode Command Line Tools, or set NUCLEUS_SWIFT."
        )
    return swift


def _resolve_swiftc() -> str:
    swiftc = os.environ.get("NUCLEUS_SWIFTC") or os.environ.get("SWIFTC") or "swiftc"
    if shutil.which(swiftc) is None:
        raise RuntimeError(
            f"swiftc not found: {swiftc!r}. Install Xcode Command Line Tools, or set NUCLEUS_SWIFTC."
        )
    return swiftc


def _require_darwin() -> None:
    if platform.system() != "Darwin":
        raise RuntimeError("Swift sidecar is only supported on macOS (Darwin).")


def _cache_root() -> Path:
    override = os.environ.get("NUCLEUS_APPLE_MCP_CACHE_DIR")
    if override:
        return Path(override).expanduser()

    home = Path.home()
    if platform.system() == "Darwin":
        return home / "Library" / "Caches" / "nucleus-apple-mcp"

    xdg = os.environ.get("XDG_CACHE_HOME")
    return (Path(xdg).expanduser() if xdg else (home / ".cache")) / "nucleus-apple-mcp"


def _collect_files(swift_sources_dir: Path, *, extra_files: tuple[str, ...] = ()) -> list[Path]:
    files: list[Path] = []
    for rel in extra_files:
        p = swift_sources_dir / rel
        if p.exists():
            files.append(p)
    files.extend(sorted(swift_sources_dir.rglob("*.swift")))
    if not files:
        raise RuntimeError(f"No Swift sources found under: {swift_sources_dir}")
    return files


def _find_built_binary(scratch_dir: Path, name: str) -> Path:
    candidates: list[Path] = []
    for p in scratch_dir.rglob(name):
        if not p.is_file():
            continue
        if not os.access(p, os.X_OK):
            continue
        candidates.append(p)

    if not candidates:
        raise RuntimeError(f"SwiftPM build succeeded but binary {name!r} was not found under: {scratch_dir}")

    def sort_key(p: Path) -> tuple[int, int]:
        parts = p.parts
        has_release = 0 if "release" in parts else 1
        return (has_release, len(parts))

    candidates.sort(key=sort_key)
    return candidates[0]


def _compute_build_id(swift_sources_dir: Path, files: list[Path], *, algo: str) -> str:
    h = hashlib.sha256()

    try:
        pkg_ver = version("nucleus-apple-mcp")
    except PackageNotFoundError:
        pkg_ver = "0.0.0+local"

    h.update(f"pkg=nucleus-apple-mcp@{pkg_ver}\n".encode())
    h.update(f"algo={algo}\n".encode())

    for file in files:
        rel = file.relative_to(swift_sources_dir).as_posix()
        h.update(f"file={rel}\n".encode())
        h.update(file.read_bytes())
        h.update(b"\n")

    return h.hexdigest()[:16]
