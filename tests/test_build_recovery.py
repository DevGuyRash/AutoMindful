"""Real ZIP/filesystem failure recovery; Lua compilation is a separate gate."""
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import build


class BuildRecovery(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.output = Path(temporary.name)
        # Only bypass unavailable external compiler; use real source bytes/ZIP/I/O.
        self.compiler = patch('build.shutil.which', return_value='/fixture/luac5.1')
        self.run = patch('build.subprocess.run')
        self.compiler.start(); self.run.start()
        self.addCleanup(self.compiler.stop); self.addCleanup(self.run.stop)
        self.archive = build.build(self.output)
        self.manifest = self.output / 'manifest.json'
        self.old = {p.name: p.read_bytes() for p in (self.archive, self.manifest)}
        (self.output / 'unrelated').write_text('keep')

    def preserved(self):
        self.assertEqual({p.name: p.read_bytes() for p in (self.archive, self.manifest)}, self.old)
        self.assertEqual((self.output / 'unrelated').read_text(), 'keep')
        self.assertEqual(list(self.output.glob('.automindful-build-*')), [])

    def valid(self):
        manifest = json.loads(self.manifest.read_text())
        self.assertEqual(manifest['archiveSha256'], hashlib.sha256(self.archive.read_bytes()).hexdigest())
        with zipfile.ZipFile(self.archive) as archive:
            self.assertEqual(set(archive.namelist()), set(manifest['files']))
            for name in archive.namelist():
                self.assertEqual(hashlib.sha256(archive.read(name)).hexdigest(), manifest['files'][name])

    def test_archive_failure_preserves_previous_pair_and_retry(self):
        with patch('build.zipfile.ZipFile.writestr', side_effect=OSError('disk full')):
            with self.assertRaises(OSError): build.build(self.output)
        self.preserved(); build.build(self.output); self.valid()

    def test_manifest_failure_preserves_previous_pair_and_retry(self):
        original = Path.write_text
        def fail(path, *args, **kwargs):
            if path.name == 'manifest.json': raise OSError('disk full')
            return original(path, *args, **kwargs)
        with patch.object(Path, 'write_text', fail):
            with self.assertRaises(OSError): build.build(self.output)
        self.preserved(); build.build(self.output); self.valid()

    def test_backup_failure_preserves_previous_pair(self):
        with patch('build.shutil.copy2', side_effect=OSError('disk full')):
            with self.assertRaises(OSError): build.build(self.output)
        self.preserved()

    def test_archive_close_failure_preserves_previous_pair(self):
        original = zipfile.ZipFile.close
        def fail(archive):
            was_open = archive.fp is not None
            original(archive)
            if was_open and archive.mode == 'w': raise OSError('close failed')
        with patch.object(zipfile.ZipFile, 'close', fail):
            with self.assertRaises(OSError): build.build(self.output)
        self.preserved()

    def test_first_commit_failure_preserves_previous_pair(self):
        with patch('build.os.replace', side_effect=OSError('commit denied')):
            with self.assertRaises(OSError): build.build(self.output)
        self.preserved()

    def test_second_commit_failure_restores_pair_and_retry(self):
        original = build.os.replace
        changed = {name: data + b'\n' for name, data in build.package_files().items()}
        def fail(source, destination):
            if Path(source).name == 'manifest.json': raise OSError('commit denied')
            return original(source, destination)
        with patch('build.os.replace', fail), patch('build.package_files', return_value=changed):
            with self.assertRaises(OSError): build.build(self.output)
        self.preserved(); build.build(self.output); self.valid()

    def test_new_output_commit_failure_removes_partial_archive(self):
        fresh = self.output / 'fresh'
        original = build.os.replace
        def fail(source, destination):
            if Path(source).name == 'manifest.json': raise OSError('commit denied')
            return original(source, destination)
        with patch('build.os.replace', fail):
            with self.assertRaises(OSError): build.build(fresh)
        self.assertEqual(list(fresh.iterdir()), [])
        build.build(fresh)
        self.assertTrue((fresh / self.archive.name).is_file())

    def test_failed_rollback_retains_recovery_bytes(self):
        original = build.os.replace
        changed = {name: data + b'\n' for name, data in build.package_files().items()}
        def fail(source, destination):
            if Path(source).name == 'manifest.json' or Path(source).name.endswith('.previous'):
                raise OSError('commit and recovery denied')
            return original(source, destination)
        with patch('build.os.replace', fail), patch('build.package_files', return_value=changed):
            with self.assertRaisesRegex(RuntimeError, 'preserve backups'): build.build(self.output)
        retained, = self.output.glob('.automindful-build-*')
        for name, data in self.old.items():
            self.assertEqual((retained / (name + '.previous')).read_bytes(), data)

    def test_repeat_success_has_identical_artifacts_and_keeps_unrelated(self):
        build.build(self.output); self.preserved(); self.valid()


if __name__ == '__main__': unittest.main()
