"""Stage and validate the exact tested release bytes for Steam Workshop."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
import zipfile
import zlib

from build import ROOT, package_files, release_version, version


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def preview_bytes() -> bytes:
    data = (ROOT / "workshop/preview.png").read_bytes()
    if len(data) > 1_000_000 or data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("Workshop preview must be a PNG no larger than 1000 KB")
    offset, chunks = 8, []
    while offset < len(data):
        if offset + 12 > len(data):
            raise ValueError("Truncated preview PNG")
        size = struct.unpack(">I", data[offset:offset + 4])[0]
        kind = data[offset + 4:offset + 8]
        end = offset + 8 + size
        if end + 4 > len(data) or zlib.crc32(data[offset + 4:end]) != struct.unpack(">I", data[end:end + 4])[0]:
            raise ValueError("Invalid preview PNG checksum")
        chunks.append(kind)
        if kind == b"IHDR" and (size != 13 or struct.unpack(">II", data[offset + 8:offset + 16]) != (256, 256)):
            raise ValueError("Workshop preview must be exactly 256 by 256 pixels")
        offset = end + 4
    if not chunks or chunks[0] != b"IHDR" or chunks[-1] != b"IEND" or b"IDAT" not in chunks:
        raise ValueError("Incomplete preview PNG")
    return data


def workshop_assets() -> dict[str, bytes]:
    metadata = (ROOT / "workshop/workshop.txt").read_bytes()
    if re.search(rb"(?m)^id=", metadata):
        raise ValueError("The tracked Workshop template must not contain an item ID")
    return {"workshop.txt": metadata, "preview.png": preview_bytes()}


def stage(archive: Path, manifest_path: Path, tag: str, output: Path, notes: str = "") -> Path:
    current = release_version(tag)
    if current != version():
        raise ValueError("Release tag does not match 42/mod.info")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    expected = package_files()
    expected_hashes = {name: sha256(data) for name, data in expected.items()}
    if manifest.get("id") != "AutoMindful" or manifest.get("version") != current or manifest.get("files") != expected_hashes:
        raise ValueError("Manifest does not match the checked-out release package")
    if sha256(archive.read_bytes()) != manifest.get("archiveSha256"):
        raise ValueError("Archive SHA256 does not match the verified manifest")
    content = {}
    with zipfile.ZipFile(archive) as package:
        names = package.namelist()
        if len(names) != len(set(names)) or set(names) != set(expected):
            raise ValueError("Archive contains missing, duplicate or unexpected files")
        for name in names:
            data = package.read(name)
            if sha256(data) != expected_hashes[name]:
                raise ValueError(f"Archive member checksum failed: {name}")
            content[name] = data
    content.update(workshop_assets())
    output.mkdir(parents=True, exist_ok=False)
    for name, data in content.items():
        destination = output / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(data)
    (output / "release.json").write_text(json.dumps({
        "tag": tag, "version": current, "archiveSha256": manifest["archiveSha256"],
        "changeNote": "AutoMindful " + tag + ("\n\n" + notes.strip() if notes.strip() else ""),
        "files": {name: sha256(data) for name, data in content.items()},
    }, indent=2) + "\n", encoding="utf-8")
    print(f"Staged {tag} from the verified archive at {output}")
    return output


def checked_stage(path: Path) -> dict:
    record = json.loads((path / "release.json").read_text(encoding="utf-8"))
    if release_version(record["tag"]) != record["version"] or record["version"] != version():
        raise ValueError("Stage tag and version disagree")
    if not isinstance(record.get("changeNote"), str):
        raise ValueError("Stage release notes must be text")
    files = record["files"]
    source = package_files() | workshop_assets()
    if files != {name: sha256(data) for name, data in source.items()}:
        raise ValueError("Staged manifest does not match the checked-out release")
    expected = {"release.json", *files}
    actual = set()
    for entry in path.rglob("*"):
        if entry.is_symlink():
            raise ValueError("Workshop stage contains a symlink")
        if entry.is_file():
            actual.add(entry.relative_to(path).as_posix())
    if actual != expected:
        raise ValueError("Workshop stage contains missing or unexpected files")
    for name, digest in files.items():
        if sha256((path / name).read_bytes()) != digest:
            raise ValueError(f"Workshop stage changed after verification: {name}")
    return record


def workshop_id(value: str) -> str:
    if not re.fullmatch(r"[1-9][0-9]*", value) or int(value) >= 2 ** 64:
        raise ValueError("STEAM_WORKSHOP_ID must be the positive existing item ID; creation is not allowed in release publishing")
    return value


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    staging = commands.add_parser("stage")
    staging.add_argument("--archive", required=True, type=Path)
    staging.add_argument("--manifest", required=True, type=Path)
    staging.add_argument("--tag", required=True)
    staging.add_argument("--out", required=True, type=Path)
    staging.add_argument("--notes-file", type=Path, help="UTF-8 GitHub release notes")
    args = parser.parse_args()
    try:
        notes = args.notes_file.read_text(encoding="utf-8") if args.notes_file else ""
        stage(args.archive.resolve(), args.manifest.resolve(), args.tag, args.out.resolve(), notes)
    except (ValueError, RuntimeError, OSError, zipfile.BadZipFile) as failure:
        parser.exit(1, str(failure) + "\n")


if __name__ == "__main__":
    main()
