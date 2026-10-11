"""Exclusions stay observable when absent, repeated, or refused."""
from contextlib import redirect_stdout
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

LIB = Path(__file__).resolve().parents[1] / 'lib'
sys.path.insert(0, str(LIB))
from final_policy import apply


class ExclusionLogging(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name) / 'game'
        self.root.mkdir()

    def bash(self, script, *paths):
        return subprocess.run(
            ['bash', '-c', 'set -euo pipefail; source "$DIR_INSTALLER_LIB/tools_stack.sh"; '
             'source "$DIR_INSTALLER_LIB/stack_component_lib.sh"; ' + script,
             'bash', *map(str, paths)], capture_output=True, text=True,
            env=dict(os.environ, DIR_INSTALLER_LIB=str(LIB), DIR_LEFT4DEAD2=str(self.root)))

    def test_files_directories_and_absence_on_every_run(self):
        file = self.root / 'plugin with spaces.smx'
        file.write_text('excluded')
        directory = self.root / 'excluded-dir'
        directory.mkdir()
        (directory / 'child').write_text('excluded')
        missing = self.root / 'missing.smx'
        neighbor = self.root / 'community.smx'
        neighbor.write_text('keep')
        first = self.bash('stack_remove_paths_if_present "$@"', file, directory, missing)
        self.assertEqual(first.returncode, 0, first.stderr)
        for name in (file.name, directory.name):
            self.assertIn(f'Excluded path from deployment: {name} (removed)', first.stdout)
        self.assertIn('missing.smx (absent)', first.stdout)
        again = self.bash('stack_remove_paths_if_present "$@"', file, directory, missing)
        self.assertEqual(again.returncode, 0, again.stderr)
        self.assertEqual(again.stdout.count('(absent)'), 3)
        self.assertEqual(neighbor.read_text(), 'keep')

    def test_symlinks_are_removed_without_following_the_target(self):
        outside = self.root.parent / 'outside'
        outside.mkdir()
        (outside / 'keep').write_text('keep')
        link = self.root / 'linked-dir'
        link.symlink_to(outside, target_is_directory=True)
        dangling = self.root / 'dangling'
        dangling.symlink_to(self.root.parent / 'missing')
        result = self.bash('stack_remove_files_if_present "$@"', link, dangling)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.count('(removed)'), 2)
        self.assertFalse(link.is_symlink())
        self.assertFalse(dangling.is_symlink())
        self.assertEqual((outside / 'keep').read_text(), 'keep')

    def test_file_exclusion_refuses_directory_and_special_file(self):
        directory = self.root / 'unexpected'
        directory.mkdir()
        keep = directory / 'keep'
        keep.write_text('keep')
        fifo = self.root / 'fifo'
        os.mkfifo(fifo)
        for path in (directory, fifo):
            with self.subTest(path=path):
                result = self.bash('stack_remove_files_if_present "$@"', path)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('(failed)', result.stderr)
                self.assertNotIn('(removed)', result.stdout)
                self.assertTrue(path.exists())
        self.assertEqual(keep.read_text(), 'keep')

    def test_failed_removal_does_not_claim_success(self):
        file = self.root / 'locked.smx'
        file.write_text('keep')
        result = self.bash('rm() { return 23; }; stack_remove_paths_if_present "$@"', file)
        self.assertEqual(result.returncode, 23)
        self.assertIn('locked.smx (failed)', result.stderr)
        self.assertNotIn('(removed)', result.stdout)
        self.assertTrue(file.exists())

    def test_copy_replacement_is_not_an_exclusion(self):
        source = self.root.parent / 'source'
        source.mkdir()
        (source / 'community.smx').write_text('new')
        (self.root / 'community.smx').write_text('old')
        result = self.bash('stack_sync_file "$1" "$2"', source / 'community.smx', self.root)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn('Excluded path', result.stdout)
        self.assertEqual((self.root / 'community.smx').read_text(), 'new')

    def test_sir_logs_named_and_discovered_exclusions(self):
        source = self.root.parent / 'sir'
        cfg = source / 'cfg'
        addons = source / 'addons'
        cfg.mkdir(parents=True)
        addons.mkdir()
        (cfg / 'server.cfg').write_text('excluded default')
        dll = addons / 'windows binary.dll'
        dll.write_text('excluded binary')
        (addons / 'linux.so').write_text('keep')
        hook = LIB.parents[1] / 'stack/hooks/sir.default.sh'
        for download, status in [('true', 'removed'), ('false', 'absent')]:
            result = self.bash('export DIR_CFG="$DIR_LEFT4DEAD2/cfg"; '
                               'export DIR_SOURCEMOD="$DIR_LEFT4DEAD2/addons/sourcemod"; '
                               'bash "$1" "$2" install "$3"', hook, source, download)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn(f'{cfg / "server.cfg"} ({status})', result.stdout)
            if download == 'true':
                self.assertIn(f'{dll} (removed)', result.stdout)
            self.assertEqual((self.root / 'addons/linux.so').read_text(), 'keep')

    def test_final_policy_logs_paths_and_exact_commands_when_present_or_absent(self):
        cfg = self.root / 'cfg'
        cfg.mkdir()
        (cfg / 'sharedplugins.cfg').write_text('old')
        local = cfg / 'local.cfg'
        local.write_text('exec sharedplugins.cfg\nexec "sharedplugins.cfg"\n'
                         'sm plugins load "vip/VIP_Core.smx"\nhostname community\n')
        policy = self.root.parent / 'policy.json'
        policy.write_text(json.dumps({
            'remove': {'cfg/sharedplugins.cfg': 'reason', 'cfg/sharedplugins1.cfg': 'reason'},
            'remove_exec': ['sharedplugins.cfg', 'sharedplugins1.cfg'],
            'remove_load': ['vip/VIP_Core.smx', 'VIP_Core.smx']}))
        first = io.StringIO()
        with redirect_stdout(first):
            apply(self.root, policy)
        self.assertIn('cfg/sharedplugins.cfg (removed)', first.getvalue())
        self.assertIn('cfg/sharedplugins1.cfg (absent)', first.getvalue())
        self.assertIn('exec sharedplugins.cfg (removed; occurrences=2)', first.getvalue())
        self.assertIn('sm plugins load vip/VIP_Core.smx (removed; occurrences=1)', first.getvalue())
        self.assertIn('sm plugins load VIP_Core.smx (absent; occurrences=0)', first.getvalue())
        again = io.StringIO()
        with redirect_stdout(again):
            apply(self.root, policy)
        self.assertEqual(len(again.getvalue().splitlines()), 6)
        self.assertEqual(again.getvalue().count('(absent'), 6)
        self.assertEqual(local.read_text(), 'hostname community\n')
