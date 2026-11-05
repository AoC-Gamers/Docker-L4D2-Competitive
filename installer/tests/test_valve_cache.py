"""Real filesystem/lock/process tests with a tiny SteamCMD fixture, never SRCDS."""
import importlib.util
from contextlib import suppress
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

INSTALLER = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('valve_cache', INSTALLER / 'lib/valve_cache.py')
cache_module = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(cache_module)
Cache = cache_module.Cache

FAKE_STEAM = '''#!/usr/bin/env python3
import json, os, pathlib, sys, time
args = sys.argv[1:]
with open(os.environ['STEAM_CALLS'], 'a') as stream:
    stream.write(json.dumps(args) + '\\n')
if '+app_update' not in args:
    sys.exit(0)
time.sleep(float(os.environ.get('STEAM_DELAY', '0')))
if os.environ.get('STEAM_FAIL') == '1':
    sys.exit(7)
root = pathlib.Path(args[args.index('+force_install_dir') + 1])
for name in ('srcds_run', 'srcds_linux', 'left4dead2/gameinfo.txt',
             'left4dead2/steam.inf', 'left4dead2/pak01_dir.vpk'):
    path = root / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text('valve fixture ' + name)
    if name.startswith('srcds'):
        path.chmod(0o755)
manifest = root / 'steamapps/appmanifest_222860.acf'
manifest.parent.mkdir(exist_ok=True)
manifest.write_text('"appid" "222860" "StateFlags" "4" "buildid" "12345"')
'''


class ValveCache(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.cache_root = self.root / 'cache'
        self.cache_root.mkdir()
        self.calls = self.root / 'calls.jsonl'
        bin_dir = self.root / 'bin'
        bin_dir.mkdir()
        (bin_dir / 'steamcmd').write_text(FAKE_STEAM)
        (bin_dir / 'steamcmd').chmod(0o755)
        self.env = dict(os.environ, PATH=str(bin_dir) + os.pathsep + os.environ['PATH'],
                        STEAM_CALLS=str(self.calls), L4D2_VALVE_CACHE_VOLUME='fixture_cache',
                        PYTHONDONTWRITEBYTECODE='1')
        self.environment = patch.dict(os.environ, self.env)
        self.environment.start()
        self.addCleanup(self.environment.stop)
        self.cache = Cache(self.cache_root, require_mount=False, poll_seconds=0.05)

    def downloads(self):
        return [json.loads(line) for line in self.calls.read_text().splitlines()
                if '+app_update' in line] if self.calls.exists() else []

    def child(self, command, target=None, **extra):
        script = ('import sys; sys.path.insert(0, sys.argv[1]); from valve_cache import Cache; '
                  'Cache(sys.argv[2], require_mount=False, poll_seconds=.05).execute('
                  'sys.argv[3], target=sys.argv[4] or None)')
        process = subprocess.Popen([sys.executable, '-c', script, str(INSTALLER / 'lib'),
                                    str(self.cache_root), command, str(target or '')],
                                   env={**self.env, **extra}, stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, text=True, start_new_session=True)
        self.addCleanup(self.stop, process)
        return process

    @staticmethod
    def stop(process):
        if process.poll() is None:
            os.killpg(process.pid, signal.SIGKILL)
        process.communicate(timeout=10)

    def await_phase(self, phase):
        end = time.monotonic() + 8
        while time.monotonic() < end:
            if self.cache.metadata.exists() and json.loads(self.cache.metadata.read_text()).get('phase') == phase:
                return
            time.sleep(0.02)
        self.fail(f'Never reached {phase}')

    def test_disabled_cli_and_enabled_without_mount_have_no_side_effects(self):
        with patch.dict(os.environ, L4D2_VALVE_CACHE_VOLUME=''), patch.object(sys, 'argv', ['cache', 'status']):
            cache_module.main()
        self.assertEqual(list(self.cache_root.iterdir()), [])
        with self.assertRaisesRegex(ValueError, 'not mounted'):
            Cache(self.cache_root)
        self.assertFalse(self.calls.exists())

    def test_one_download_and_independent_private_copies(self):
        first, second = self.root / 'first', self.root / 'second'
        self.cache.execute('seed', target=first)
        self.cache.execute('seed', target=second)
        calls = self.downloads()
        self.assertEqual(len(calls), 2)  # Windows+Linux workaround once, not per consumer.
        self.assertEqual([c[c.index('+@sSteamCmdForcePlatformType') + 1] for c in calls], ['windows', 'linux'])
        self.assertTrue(all(c[c.index('+login') + 1] == 'anonymous' for c in calls))
        payload, _ = self.cache.verify()
        for destination in (first, second):
            self.assertNotEqual((destination / 'srcds_run').stat().st_ino, (payload / 'srcds_run').stat().st_ino)
            self.assertEqual((destination / 'srcds_run').stat().st_mode & 0o777, 0o755)
        (first / 'srcds_run').write_text('local change')
        self.assertNotEqual((first / 'srcds_run').read_bytes(), (second / 'srcds_run').read_bytes())
        self.cache.execute('validate')
        self.assertEqual(len(self.downloads()), 2)
        self.assertFalse(self.cache.status()['lock_active'])

    def test_four_concurrent_consumers_download_once_and_log_waiting(self):
        processes = [self.child('seed', self.root / f'game-{i}', STEAM_DELAY='.2') for i in range(4)]
        outputs = []
        for process in processes:
            out, err = process.communicate(timeout=15)
            self.assertEqual(process.returncode, 0, out + err)
            outputs.append(err)
        self.assertEqual(len(self.downloads()), 2)
        self.assertTrue(any('waiting; status=' in output and 'phase=' in output for output in outputs))
        for i in range(4):
            self.assertTrue((self.root / f'game-{i}/srcds_run').is_file())

    def test_failed_or_killed_download_is_not_published_and_lock_is_released(self):
        with patch.dict(os.environ, STEAM_FAIL='1'):
            with self.assertRaises(subprocess.CalledProcessError):
                self.cache.execute('download')
        self.assertFalse(self.cache.current.exists())
        self.assertEqual(self.cache.status()['status'], 'failed')
        process = self.child('download', STEAM_DELAY='15')
        self.await_phase('steamcmd_windows')
        self.assertTrue(self.cache.status()['lock_active'])
        # Kill only the owner first: a surviving SteamCMD can write only its unique workspace.
        process.kill()
        process.wait(timeout=5)
        self.assertTrue(self.cache.status()['interrupted'])
        self.cache.execute('download')
        self.cache.verify()
        with suppress(ProcessLookupError):
            os.killpg(process.pid, signal.SIGKILL)
        process.communicate(timeout=5)

    def test_corruption_validation_and_explicit_rebuild(self):
        self.cache.execute('download')
        payload, _ = self.cache.verify()
        old_reference = self.cache.current.read_bytes()
        with patch.dict(os.environ, STEAM_FAIL='1'):
            with self.assertRaises(subprocess.CalledProcessError):
                self.cache.execute('download', force=True)
        self.assertEqual(self.cache.current.read_bytes(), old_reference)
        self.cache.verify()
        (payload / 'srcds_run').write_text('damaged')
        with self.assertRaisesRegex(ValueError, 'integrity'):
            self.cache.execute('validate')
        target = self.root / 'new-game'
        with self.assertRaises(ValueError):
            self.cache.execute('seed', target=target)
        self.assertFalse(target.exists())
        self.cache.execute('download', force=True)
        self.cache.execute('seed', target=target)
        self.assertTrue((target / 'srcds_run').is_file())

    def test_existing_data_and_symlinks_are_never_overwritten(self):
        target = self.root / 'existing'
        target.mkdir()
        (target / 'local.cfg').write_text('preserve')
        with self.assertRaisesRegex(ValueError, 'existing data'):
            self.cache.execute('seed', target=target)
        self.assertEqual((target / 'local.cfg').read_text(), 'preserve')
        self.assertEqual(self.downloads(), [])
        (self.root / 'link').symlink_to(target)
        with self.assertRaises(ValueError):
            self.cache.execute('seed', target=self.root / 'link')
        self.cache.execute('download')
        payload, _ = self.cache.verify()
        (payload / 'external').symlink_to('/etc/passwd')
        with self.assertRaisesRegex(ValueError, 'External symlink'):
            self.cache.execute('validate')

    def test_failed_copy_leaves_no_installed_sentinel_and_can_retry(self):
        target = self.root / 'empty'
        target.mkdir()
        self.cache.execute('download')
        with patch.object(cache_module.shutil, 'copytree', side_effect=OSError('disk full')):
            with self.assertRaisesRegex(OSError, 'disk full'):
                self.cache.execute('seed', target=target)
        self.assertEqual(list(target.iterdir()), [])
        self.assertEqual(list(self.root.glob('.valve-seed-*')), [])
        self.cache.execute('seed', target=target)
        self.assertEqual(len(self.downloads()), 2)

    def test_manifest_tampering_and_incomplete_steam_payload_are_rejected(self):
        self.cache.execute('download')
        payload, _ = self.cache.verify()
        (payload.parent / 'manifest.json').write_text('{}')
        with self.assertRaisesRegex(ValueError, 'checksum'):
            self.cache.execute('validate')
        (payload / 'steamapps/appmanifest_222860.acf').write_text('"appid" "222860" "StateFlags" "6"')
        with self.assertRaisesRegex(ValueError, 'complete L4D2'):
            cache_module.check_payload(payload)

    def test_waiter_rechecks_an_already_completed_destination(self):
        target = self.root / 'same-game'
        processes = [self.child('seed', target, STEAM_DELAY='.1') for _ in range(2)]
        for process in processes:
            out, err = process.communicate(timeout=15)
            self.assertEqual(process.returncode, 0, out + err)
        self.assertEqual(len(self.downloads()), 2)
        self.assertTrue((target / 'srcds_run').is_file())

    def test_malformed_json_is_reported_and_can_be_rebuilt_explicitly(self):
        self.cache.metadata.write_text('[]')
        self.assertEqual(self.cache.status()['status'], 'empty')
        self.cache.current.write_text('[]')
        with self.assertRaisesRegex(ValueError, 'JSON object'):
            self.cache.execute('validate')
        self.cache.execute('download', force=True)
        self.cache.execute('validate')


class InstallationRouting(unittest.TestCase):
    def run_case(self, mode, installed=False, cache=True):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            if installed:
                (root / 'serverfiles').mkdir()
                (root / 'serverfiles/srcds_run').touch()
            env = dict(os.environ, DIR_INSTALLER_BIN=str(INSTALLER / 'bin'), DIR_INSTALLER_LIB=str(INSTALLER / 'lib'),
                       DIR_INSTALLER=str(root / 'installer'), DIR_STACK=str(root / 'stack'), GAMESERVER='l4d2server',
                       LGSM_CONFIG=str(root / 'cfg'), LGSM_SERVERFILES=str(root / 'serverfiles'),
                       L4D2_INSTALL=mode, L4D2_VALVE_CACHE_VOLUME='cache' if cache else '', STEAM_USER='', STEAM_PASSWD='')
            script = '''source "$DIR_INSTALLER_BIN/deploy_stack.sh"
bash() { printf 'CALLED:%s\\n' "$*"; }
install_primary_instance
printf 'FRESH:%s\\n' "$L4D2_FRESH_INSTALL"
'''
            return subprocess.run(['bash', '-euc', script], env=env, text=True, capture_output=True, timeout=10)

    def test_new_install_uses_cache_but_disabled_retains_original_installer(self):
        for mode in ('normal', 'force'):
            result = self.run_case(mode)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('valve_cache.sh seed', result.stdout)
            self.assertIn('FRESH:true', result.stdout)
        result = self.run_case('normal', cache=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('l4d2_fix_install.sh', result.stdout)
        self.assertNotIn('valve_cache.sh', result.stdout)

    def test_skip_and_existing_install_never_call_cache(self):
        for mode, installed in [('skip', False), ('skip', True), ('normal', True), ('force', True)]:
            with self.subTest(mode=mode, installed=installed):
                result = self.run_case(mode, installed)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertNotIn('valve_cache.sh', result.stdout)
                if mode == 'force':
                    self.assertIn('l4d2_fix_install.sh', result.stdout)
