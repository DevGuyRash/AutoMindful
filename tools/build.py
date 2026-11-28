"""Compile client Lua and build a portable local/Workshop-layout archive."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
VERSION_PATTERN = r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)"
MENU_ICONS = {"mods/SecondNature/common/media/ui/AutoMindful/" + name + ".png"
              for name in ("Mindful", "Yoga", "Meditate", "Endurance")}
MOD_ID = "SecondNature"
# Saves and servers made before 0.7.0 name the mod AutoMindful. The package
# carries the same files under that ID too, so they keep working; both copies
# use the same internal Lua paths, so enabling both still loads each file once.
LEGACY_ID = "AutoMindful"
LEGACY_NAME = " (legacy ID: only for saves made before 0.7.0)"


def legacy_info(data: bytes) -> bytes:
    """The same mod.info under the old ID, its name saying what it is for."""
    lines = []
    for line in data.decode("utf-8").splitlines():
        if line.startswith("id="):
            line = "id=" + LEGACY_ID
        elif line.startswith("name="):
            line = line + LEGACY_NAME
        lines.append(line)
    return ("\n".join(lines) + "\n").encode("utf-8")


def release_version(tag: str) -> str:
    if not re.fullmatch("v" + VERSION_PATTERN, tag):
        raise ValueError("Release tags must use stable vMAJOR.MINOR.PATCH, for example v0.1.1")
    return tag[1:]


def version() -> str:
    lines = (ROOT / "mods/SecondNature/42/mod.info").read_text(encoding="utf-8").splitlines()
    versions = [line.removeprefix("modversion=").strip() for line in lines if line.startswith("modversion=")]
    if len(versions) != 1 or not re.fullmatch(VERSION_PATTERN, versions[0]):
        raise ValueError("42/mod.info must contain exactly one stable modversion=MAJOR.MINOR.PATCH")
    return versions[0]


def package_files() -> dict[str, bytes]:
    result = {}
    for path in sorted((ROOT / "mods").rglob("*")):
        if path.is_symlink():
            raise ValueError(f"Package input is a symlink: {path.relative_to(ROOT)}")
        if not path.is_file():
            continue
        relative = path.relative_to(ROOT).as_posix()
        if not relative.startswith(f"mods/{MOD_ID}/") or any(part.startswith(".") for part in path.relative_to(ROOT).parts):
            raise ValueError(f"Unexpected mod in package: {relative}")
        if path.name != "mod.info" and relative not in MENU_ICONS and not (path.suffix == ".lua" and "/media/lua/client/" in relative):
            raise ValueError(f"Unsupported package input: {relative}")
        data = path.read_bytes()
        result["Contents/" + relative] = data
        legacy = relative.replace(f"mods/{MOD_ID}/", f"mods/{LEGACY_ID}/", 1)
        result["Contents/" + legacy] = legacy_info(data) if path.name == "mod.info" else data
    if any("Contents/" + icon not in result for icon in MENU_ICONS):
        raise ValueError("Missing packaged menu icon")
    for mod in (MOD_ID, LEGACY_ID):
        result[f"Contents/mods/{mod}/LICENSE"] = (ROOT / "LICENSE").read_bytes()
    return result


def build(output: Path, tag: str | None = None) -> Path:
    current_version = version()
    if tag is not None and release_version(tag) != current_version:
        raise ValueError(f"Release tag {tag} does not match modversion={current_version}")
    compiler = shutil.which("luac5.1")
    if not compiler:
        raise RuntimeError("Lua 5.1 compiler (luac5.1) is required")
    files = package_files()
    scripts = [ROOT / name.removeprefix("Contents/") for name in files if name.endswith(".lua") and f"/mods/{MOD_ID}/" in "/" + name]
    if not scripts:
        raise RuntimeError("No client Lua found")
    for script in scripts:
        if "/media/lua/client/" not in script.as_posix():
            raise RuntimeError(f"Runtime script outside client directory: {script}")
        subprocess.run([compiler, "-p", str(script)], check=True, timeout=30)
    output.mkdir(parents=True, exist_ok=True)
    staging = Path(tempfile.mkdtemp(prefix=".automindful-build-", dir=output))
    cleanup = True
    try:
        archive = staging / f"{MOD_ID}-{current_version}.zip"
        manifest = {}
        with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as package:
            for name, data in files.items():
                entry = zipfile.ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0))
                entry.compress_type = zipfile.ZIP_DEFLATED
                entry.external_attr = 0o100644 << 16
                package.writestr(entry, data)
                manifest[name] = hashlib.sha256(data).hexdigest()
        (staging / "manifest.json").write_text(json.dumps({
            "id": MOD_ID, "version": current_version, "files": manifest,
            "archiveSha256": hashlib.sha256(archive.read_bytes()).hexdigest(),
        }, indent=2) + "\n", encoding="utf-8")
        artifacts = [archive, staging / "manifest.json"]
        backups = {}
        for artifact in artifacts:
            destination = output / artifact.name
            if destination.is_symlink() or (destination.exists() and not destination.is_file()):
                raise ValueError(f"Release artifact is not a regular file: {destination}")
            if destination.exists():
                backup = staging / (artifact.name + ".previous")
                shutil.copy2(destination, backup)
                backups[destination] = backup
        replaced = []
        try:
            for artifact in artifacts:
                destination = output / artifact.name
                os.replace(artifact, destination)
                replaced.append(destination)
        except BaseException:
            # Recover handled commit failures. Two files cannot be atomically
            # replaced together: concurrent writers and host crashes are outside
            # this bounded recovery contract.
            try:
                for destination in reversed(replaced):
                    if destination in backups:
                        os.replace(backups[destination], destination)
                    else:
                        destination.unlink()
            except OSError as recovery_error:
                cleanup = False
                raise RuntimeError(f"Artifact recovery failed; preserve backups in {staging}") from recovery_error
            raise
    finally:
        if cleanup:
            shutil.rmtree(staging)
    archive = output / archive.name
    print(f"Built {archive} ({len(scripts)} client Lua files)", flush=True)
    return archive


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=ROOT / "dist")
    parser.add_argument("--tag", help="Require a matching stable release tag")
    args = parser.parse_args()
    build(args.out.expanduser().resolve(), args.tag)
