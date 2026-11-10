"""Compile client Lua and build a portable local/Workshop-layout archive."""

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def build(output: Path) -> Path:
    compiler = shutil.which("luac5.1")
    if not compiler:
        raise RuntimeError("Lua 5.1 compiler (luac5.1) is required")
    files = sorted(path for path in (ROOT / "mods").rglob("*") if path.is_file())
    files.append(ROOT / "LICENSE")
    scripts = [path for path in files if path.suffix == ".lua"]
    if not scripts:
        raise RuntimeError("No client Lua found")
    for script in scripts:
        if "/media/lua/client/" not in script.as_posix():
            raise RuntimeError(f"Runtime script outside client directory: {script}")
        subprocess.run([compiler, "-p", str(script)], check=True, timeout=30)
    output.mkdir(parents=True, exist_ok=True)
    archive = output / "AutoMindful-0.1.0.zip"
    manifest = {}
    with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as package:
        for path in files:
            name = "Contents/mods/AutoMindful/LICENSE" if path == ROOT / "LICENSE" else "Contents/" + path.relative_to(ROOT).as_posix()
            data = path.read_bytes()
            entry = zipfile.ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0))
            entry.compress_type = zipfile.ZIP_DEFLATED
            entry.external_attr = 0o100644 << 16
            package.writestr(entry, data)
            manifest[name] = hashlib.sha256(data).hexdigest()
    (output / "manifest.json").write_text(json.dumps({
        "id": "AutoMindful", "version": "0.1.0", "files": manifest,
        "archiveSha256": hashlib.sha256(archive.read_bytes()).hexdigest(),
    }, indent=2) + "\n", encoding="utf-8")
    print(f"Built {archive} ({len(scripts)} client Lua files)", flush=True)
    return archive


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=ROOT / "dist")
    args = parser.parse_args()
    build(args.out.expanduser().resolve())
