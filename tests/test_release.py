import hashlib
import json
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest
from unittest import mock
import zipfile
import zlib

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import build
import workshop


def png_chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))


def preview_png(parts, *, depth=8, interlaced=False):
    header = struct.pack(">IIBBBBB", 256, 256, depth, 6, 0, 0, int(interlaced))
    return (b"\x89PNG\r\n\x1a\n" + png_chunk(b"IHDR", header)
        + b"".join(png_chunk(b"IDAT", part) for part in parts) + png_chunk(b"IEND", b""))


class PreviewTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="automindful-preview-test-")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        (self.root / "workshop").mkdir()

    def check_preview(self, data):
        (self.root / "workshop/preview.png").write_bytes(data)
        with mock.patch.object(workshop, "ROOT", self.root):
            return workshop.preview_bytes()

    def test_real_preview_is_accepted_unchanged(self):
        data = (ROOT / "workshop/preview.png").read_bytes()
        self.assertEqual(self.check_preview(data), data)

    def test_valid_stream_split_across_idat_chunks_is_accepted(self):
        compressed = zlib.compress((b"\0" + b"\0" * (256 * 4)) * 256)
        for parts in ([compressed], [compressed[:1], compressed[1:-1], compressed[-1:]],
                      [b"", compressed, b""]):
            with self.subTest(chunks=len(parts)):
                data = preview_png(parts)
                self.assertEqual(self.check_preview(data), data)

    def test_largest_supported_pixel_format_and_adam7_rows_fit(self):
        # Each pass has a filter byte per row and eight bytes per RGBA16 pixel.
        passes = ((32, 32), (32, 32), (64, 32), (64, 64), (128, 64), (128, 128), (256, 128))
        raw = b"".join((b"\0" + b"\0" * (width * 8)) * height for width, height in passes)
        data = preview_png([zlib.compress(raw)], depth=16, interlaced=True)
        self.assertEqual(self.check_preview(data), data)

    def test_invalid_stream_is_rejected_even_with_valid_chunk_checksums(self):
        with self.assertRaisesRegex(ValueError, "compressed image data"):
            self.check_preview(preview_png([b"not a zlib stream"]))

    def test_truncated_and_missing_streams_are_rejected(self):
        compressed = zlib.compress((b"\0" + b"\0" * (256 * 4)) * 256)
        for payload in (b"", compressed[:1], compressed[:-1], compressed[:-4]):
            with self.subTest(length=len(payload)), self.assertRaisesRegex(ValueError, "compressed image data"):
                self.check_preview(preview_png([payload]))

    def test_unused_trailing_idat_bytes_are_ignored(self):
        compressed = zlib.compress((b"\0" + b"\0" * (256 * 4)) * 256)
        for extra in (b"trailing", zlib.compress(b"another stream")):
            with self.subTest(extra=extra):
                data = preview_png([compressed + extra])
                self.assertEqual(self.check_preview(data), data)

    def test_decompression_is_bounded(self):
        oversized = preview_png([zlib.compress(b"\0" * (256 * (256 * 8 + 2) + 1))])
        self.assertLess(len(oversized), 1_000_000)
        with self.assertRaisesRegex(ValueError, "too large"):
            self.check_preview(oversized)


class ReleaseTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.package_directory = tempfile.TemporaryDirectory(prefix="automindful-release-package-")
        cls.package = Path(cls.package_directory.name)
        cls.tag = "v" + build.version()
        cls.archive = build.build(cls.package, cls.tag)
        cls.manifest = cls.package / "manifest.json"

    @classmethod
    def tearDownClass(cls):
        cls.package_directory.cleanup()

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="automindful-release-test-")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)

    def make_stage(self):
        return workshop.stage(self.archive, self.manifest, self.tag, self.root / "stage")

    def test_stage_cli_copies_exact_checked_bytes(self):
        output = self.root / "cli-stage"
        notes = self.root / "notes.txt"
        notes.write_text('Fix "quoted" paths\\folders.\nResume training.', encoding="utf-8")
        result = subprocess.run([sys.executable, "tools/workshop.py", "stage", "--archive", str(self.archive),
            "--manifest", str(self.manifest), "--tag", self.tag, "--out", str(output), "--notes-file", str(notes)], cwd=ROOT,
            text=True, capture_output=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)
        record = workshop.checked_stage(output)
        self.assertEqual(record["version"], build.version())
        self.assertEqual(record["changeNote"], f'AutoMindful {self.tag}\n\nFix "quoted" paths\\folders.\nResume training.')
        with zipfile.ZipFile(self.archive) as package:
            for name in package.namelist():
                self.assertEqual((output / name).read_bytes(), package.read(name))
        self.assertEqual((output / "preview.png").read_bytes(), (ROOT / "workshop/preview.png").read_bytes())
        self.assertFalse(any(path.name == ".git" for path in output.rglob("*")))

    def test_stable_tag_and_metadata_version_must_agree(self):
        for tag in ("0.1.0", "v01.2.3", "v1.2", "v1.2.3-rc.1", "v1.2.3+meta", "v1.2.3\n", "../main"):
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                build.release_version(tag)
        with self.assertRaises(ValueError):
            build.build(self.root / "bad", "v999999.0.0")
        with self.assertRaises(ValueError):
            workshop.stage(self.archive, self.manifest, "v999999.0.0", self.root / "bad-stage")

    def test_archive_hash_and_member_integrity_are_required(self):
        damaged = self.root / self.archive.name
        damaged.write_bytes(self.archive.read_bytes() + b"changed")
        with self.assertRaisesRegex(ValueError, "Archive SHA256"):
            workshop.stage(damaged, self.manifest, self.tag, self.root / "damaged")
        with zipfile.ZipFile(self.archive) as source, zipfile.ZipFile(damaged, "w") as target:
            for name in source.namelist():
                target.writestr(name, source.read(name) + (b"changed" if name.endswith("Controller.lua") else b""))
        record = json.loads(self.manifest.read_text())
        record["archiveSha256"] = hashlib.sha256(damaged.read_bytes()).hexdigest()
        manifest = self.root / "manifest.json"
        manifest.write_text(json.dumps(record))
        with self.assertRaisesRegex(ValueError, "member checksum"):
            workshop.stage(damaged, manifest, self.tag, self.root / "changed-member")

    def test_archive_allowlist_rejects_extra_content_even_with_a_new_archive_hash(self):
        damaged = self.root / self.archive.name
        with zipfile.ZipFile(self.archive) as source, zipfile.ZipFile(damaged, "w") as target:
            for name in source.namelist():
                target.writestr(name, source.read(name))
            target.writestr("Contents/mods/AutoMindful/.git/config", "not release content")
        record = json.loads(self.manifest.read_text())
        record["archiveSha256"] = hashlib.sha256(damaged.read_bytes()).hexdigest()
        manifest = self.root / "manifest.json"
        manifest.write_text(json.dumps(record))
        with self.assertRaisesRegex(ValueError, "unexpected files"):
            workshop.stage(damaged, manifest, self.tag, self.root / "extra")

    def test_stage_rejects_mutation_and_untracked_files(self):
        stage = self.make_stage()
        injected = stage / "Contents/mods/AutoMindful/config.vdf"
        injected.write_text("not release content")
        with self.assertRaisesRegex(ValueError, "unexpected files"):
            workshop.checked_stage(stage)
        injected.unlink()
        preview = stage / "preview.png"
        preview.write_bytes(preview.read_bytes() + b"changed")
        with self.assertRaisesRegex(ValueError, "changed after verification"):
            workshop.checked_stage(stage)

    def test_existing_stage_is_not_overwritten(self):
        stage = self.make_stage()
        with self.assertRaises(FileExistsError):
            workshop.stage(self.archive, self.manifest, self.tag, stage)
        workshop.checked_stage(stage)

    def test_invalid_preview_stops_before_creating_stage(self):
        assets = self.root / "workshop"
        assets.mkdir()
        (assets / "workshop.txt").write_bytes((ROOT / "workshop/workshop.txt").read_bytes())
        (assets / "preview.png").write_bytes(preview_png([b"not a zlib stream"]))
        output = self.root / "rejected-stage"
        with mock.patch.object(workshop, "ROOT", self.root), self.assertRaisesRegex(ValueError, "compressed image data"):
            workshop.stage(self.archive, self.manifest, self.tag, output)
        self.assertFalse(output.exists())

    def test_preview_dimensions_and_metadata_id_are_checked(self):
        assets = self.root / "workshop"
        assets.mkdir()
        metadata = (ROOT / "workshop/workshop.txt").read_bytes()
        (assets / "workshop.txt").write_bytes(metadata + b"id=1234\n")
        with mock.patch.object(workshop, "ROOT", self.root), self.assertRaisesRegex(ValueError, "must not contain an item ID"):
            workshop.workshop_assets()
        (assets / "workshop.txt").write_bytes(metadata)
        data = bytearray((ROOT / "workshop/preview.png").read_bytes())
        data[16:20] = struct.pack(">I", 512)
        data[29:33] = struct.pack(">I", zlib.crc32(data[12:29]))
        (assets / "preview.png").write_bytes(data)
        with mock.patch.object(workshop, "ROOT", self.root), self.assertRaisesRegex(ValueError, "256 by 256"):
            workshop.workshop_assets()

    def test_existing_workshop_id_is_required(self):
        self.assertEqual(workshop.workshop_id("3837554362"), "3837554362")
        for value in ("", "0", "-1", "01", "123\n", str(2 ** 64)):
            with self.subTest(value=value), self.assertRaises(ValueError):
                workshop.workshop_id(value)

    def test_desktop_cli_stops_for_invalid_id_or_missing_game(self):
        stage = self.make_stage()
        for item, reason in (("0", "positive existing item ID"), ("3837554362", "installed game")):
            result = subprocess.run([sys.executable, "tools/publish_desktop.py", "--stage", str(stage),
                "--game", str(self.root / "missing-game"), "--item-id", item], cwd=ROOT, text=True,
                capture_output=True, timeout=30)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(reason, result.stderr)

    def test_desktop_cli_stops_if_verified_stage_changes(self):
        stage = self.make_stage()
        (stage / "preview.png").write_bytes(b"changed")
        result = subprocess.run([sys.executable, "tools/publish_desktop.py", "--stage", str(stage),
            "--game", str(self.root / "missing-game"), "--item-id", "3837554362"], cwd=ROOT,
            text=True, capture_output=True, timeout=30)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("changed after verification", result.stderr)


if __name__ == "__main__":
    unittest.main()
