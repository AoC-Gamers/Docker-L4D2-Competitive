"""Archive expansion identity includes observable filesystem metadata."""
import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile
import tarfile
import unittest

LIB = Path(__file__).resolve().parents[1] / 'lib'
sys.path.insert(0, str(LIB))
import source_identity
import test_installer_flow as flow_module


class ArchiveIdentity(unittest.TestCase):
    def test_archive_identity_tracks_modes_and_empty_directories_not_timestamps(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            tool = root / 'tool'
            tool.write_text('#!/bin/sh\n')
            tool.chmod(0o755)
            empty = root / 'empty'
            empty.mkdir()
            original = source_identity.archive_tree_sha(root)
            legacy = source_identity.tree_sha(root)

            os.utime(tool, (1, 1))
            os.utime(empty, (1, 1))
            self.assertEqual(source_identity.archive_tree_sha(root), original)

            root_mode = root.stat().st_mode & 0o777
            root.chmod(0o755 if root_mode != 0o755 else 0o700)
            self.assertNotEqual(source_identity.archive_tree_sha(root), original)
            root.chmod(root_mode)
            self.assertEqual(source_identity.archive_tree_sha(root), original)

            tool.chmod(0o644)
            self.assertNotEqual(source_identity.archive_tree_sha(root), original)
            self.assertEqual(source_identity.tree_sha(root), legacy)

            tool.chmod(0o755)
            empty.chmod(0o700)
            self.assertNotEqual(source_identity.archive_tree_sha(root), original)
            empty.chmod(0o755)
            empty.rmdir()
            self.assertNotEqual(source_identity.archive_tree_sha(root), original)
            # Existing pinned source and legacy release identities retain their
            # historical bytes-only meaning; archive expansions opt into v1.
            self.assertEqual(source_identity.tree_sha(root), legacy)

    def test_corrupt_expansion_is_rebuilt_from_persisted_archive_without_download(self):
        flow = flow_module.InstallerFlow()
        flow.setUp()
        self.addCleanup(flow.doCleanups)

        source = flow.base / 'archive-source'
        source.mkdir()
        (source / 'plugin').write_text('archive version')
        tool = source / 'tool'
        tool.write_text('#!/bin/sh\n')
        tool.chmod(0o755)
        (source / 'empty').mkdir()
        archive = flow.base / 'artifact.tar'
        with tarfile.open(archive, 'w') as bundle:
            bundle.add(source / 'plugin', arcname='plugin')
            bundle.add(tool, arcname='tool')
            bundle.add(source / 'empty', arcname='empty')
        archive_sha = hashlib.sha256(archive.read_bytes()).hexdigest()
        (flow.stack / 'manifests/components.json').write_text(json.dumps({'demo': {
            'folder': 'demo', 'source_type': 'archive', 'url': archive.as_uri(),
            'archive_name': 'artifact.tar', 'sha256': archive_sha,
            'prepare_cache': True}}))
        calls = flow.base / 'hook-calls'
        flow.hook.write_text(flow.hook.read_text() + f'''
if [[ -x "$1/tool" && -d "$1/empty" ]]; then
  printf pristine > "$DIR_SOURCEMOD/plugins/demo.smx"
else
  printf damaged > "$DIR_SOURCEMOD/plugins/demo.smx"
fi
printf call >> "{calls}"
''')

        flow.assertSuccess(flow.run_install('install'))
        self.assertEqual((flow.game / 'addons/sourcemod/plugins/demo.smx').read_text(), 'pristine')
        expanded_root = flow.installer / 'cache/artifacts/expanded'
        expanded = next(path for path in expanded_root.iterdir() if path.is_dir())
        self.assertEqual((expanded / 'tool').stat().st_mode & 0o111, 0o111)

        # Simulate chmod damage and loss of an empty directory in persistent
        # expanded cache. Hook logic changes to force a cache miss; its result
        # must still reflect the pristine archive, with no remote archive left.
        # First replace the versioned marker with the previous bytes-only format
        # to exercise migration of an expansion produced by older code.
        (expanded.with_name(expanded.name + '.sha256')).write_text(
            source_identity.tree_sha(expanded) + '\n')
        (expanded / 'tool').chmod(0o644)
        (expanded / 'empty').rmdir()
        archive.unlink()
        flow.hook.write_text(flow.hook.read_text() + '# force a new preparation key\n')
        result = flow.run_install(extra={'STACK_REUSE_SOURCES': 'true'})
        flow.assertSuccess(result)
        self.assertEqual((flow.game / 'addons/sourcemod/plugins/demo.smx').read_text(), 'pristine')
        self.assertEqual(calls.read_text(), 'callcall')
        self.assertEqual((expanded / 'tool').stat().st_mode & 0o111, 0o111)
        self.assertTrue((expanded / 'empty').is_dir())
        original = flow.installer / 'cache/artifacts' / archive_sha / 'artifact.tar'
        self.assertEqual(hashlib.sha256(original.read_bytes()).hexdigest(), archive_sha)

    def test_expansion_root_mode_damage_rebuilds_before_hook_workspace_copy(self):
        flow = flow_module.InstallerFlow()
        flow.setUp()
        self.addCleanup(flow.doCleanups)

        source = flow.base / 'archive-source'
        source.mkdir()
        (source / 'plugin').write_text('archive version')
        archive = flow.base / 'artifact.tar'
        with tarfile.open(archive, 'w') as bundle:
            bundle.add(source / 'plugin', arcname='plugin')
        archive_sha = hashlib.sha256(archive.read_bytes()).hexdigest()
        (flow.stack / 'manifests/components.json').write_text(json.dumps({'demo': {
            'folder': 'demo', 'source_type': 'archive', 'url': archive.as_uri(),
            'archive_name': 'artifact.tar', 'sha256': archive_sha,
            'prepare_cache': True}}))
        flow.hook.write_text(flow.hook.read_text() + '''
root_mode=$(stat -c %a "$1")
printf '%s' "$root_mode" > "$DIR_SOURCEMOD/plugins/demo.smx"
''')

        flow.assertSuccess(flow.run_install('install'))
        expansion_root = flow.installer / 'cache/artifacts/expanded'
        expanded = next(path for path in expansion_root.iterdir() if path.is_dir())
        expected_mode = expanded.stat().st_mode & 0o777
        expected_mode_text = format(expected_mode, 'o')
        self.assertEqual((flow.game / 'addons/sourcemod/plugins/demo.smx').read_text(), expected_mode_text)

        damaged_mode = 0o700 if expected_mode != 0o700 else 0o755
        expanded.chmod(damaged_mode)
        archive.unlink()
        flow.hook.write_text(flow.hook.read_text() + '# force a preparation cache miss\n')
        result = flow.run_install(extra={'STACK_REUSE_SOURCES': 'true'})
        flow.assertSuccess(result)
        self.assertEqual((flow.game / 'addons/sourcemod/plugins/demo.smx').read_text(), expected_mode_text)
        self.assertEqual(expanded.stat().st_mode & 0o777, expected_mode)
        original = flow.installer / 'cache/artifacts' / archive_sha / 'artifact.tar'
        self.assertEqual(hashlib.sha256(original.read_bytes()).hexdigest(), archive_sha)


if __name__ == '__main__':
    unittest.main()
