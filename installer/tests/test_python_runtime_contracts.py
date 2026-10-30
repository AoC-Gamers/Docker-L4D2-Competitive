"""Administrative boundaries only: no SSH listener, real volume or gameserver."""
from contextlib import ExitStack
import importlib.util
import io
import json
import os
from pathlib import Path
import runpy
import signal
import stat
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import MagicMock, patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('bootstrap_contract', ROOT/'container/root/bootstrap.py')
boot = importlib.util.module_from_spec(spec)
spec.loader.exec_module(boot)


class BootstrapContracts(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def test_protected_ancestors_reject_runtime_writes_and_symlinks(self):
        safe = SimpleNamespace(st_mode=stat.S_IFREG | 0o644, st_uid=0)
        with patch.object(Path, 'lstat', return_value=safe):
            boot.protected('/trusted/bootstrap.py')
        for mode, owner in ((stat.S_IFREG | 0o666, 0), (stat.S_IFREG | 0o644, 1000), (stat.S_IFLNK | 0o777, 0)):
            with patch.object(Path, 'lstat', return_value=SimpleNamespace(st_mode=mode, st_uid=owner)), self.assertRaises(ValueError):
                boot.protected('/trusted/bootstrap.py')

    def test_mount_paths_unescape_space(self):
        text = '1 0 1:1 / /data/shared\\040sdk rw - tmpfs tmpfs rw\n'
        with patch.object(Path, 'read_text', return_value=text):
            self.assertEqual(boot.mount_roots(), {'/data/shared sdk'})
        link = self.root/'data'
        link.symlink_to(self.root)
        with self.assertRaises(ValueError):
            boot.repair_data(link, 1000, 1000, 1000, 1000, [])

    def identity(self, env, existing=True):
        trusted = self.root/'trusted'
        trusted.mkdir(exist_ok=True)
        (trusted/'groups.json').write_text(json.dumps({'environment_gids': ['SHARED_GID']}))
        data = self.root/'data'
        data.mkdir(exist_ok=True)
        def paths(value):
            return data if value == '/data' else Path(value)
        with ExitStack() as stack:
            stack.enter_context(patch.object(boot, 'ROOT', trusted))
            stack.enter_context(patch.object(boot, 'Path', side_effect=paths))
            stack.enter_context(patch.object(boot, 'protected'))
            stack.enter_context(patch.object(boot.pwd, 'getpwnam', return_value=SimpleNamespace(pw_uid=1000, pw_gid=1000)))
            stack.enter_context(patch.object(boot.grp, 'getgrgid', side_effect=None if existing else KeyError(), return_value=SimpleNamespace(gr_name='shared')))
            stack.enter_context(patch.object(boot.grp, 'getgrnam', return_value=SimpleNamespace(gr_mem=[])))
            repair = stack.enter_context(patch.object(boot, 'repair_data'))
            run = stack.enter_context(patch.object(boot, 'run'))
            result = boot.prepare_identity(env)
        return result, run, repair

    def test_remap_preserves_explicit_shared_groups_and_restricts_data_check(self):
        result, run, repair = self.identity({'UID': '2000', 'GID': '2000', 'SHARED_GID': '10001', 'LGSM_PASSWORD': 'private', 'L4D2_VOLUME_OWNERSHIP': 'repair'}, existing=False)
        self.assertEqual(result, (2000, 2000))
        self.assertEqual(repair.call_count, 2)
        self.assertTrue(any(call.args[:2] == ('/usr/sbin/groupadd', '-g') for call in run.call_args_list))
        access = next(call.args for call in run.call_args_list if '/usr/bin/test' in call.args)
        self.assertIn('--no-new-privs', access)
        self.assertIn('--bounding-set=-all', access)
        _, run, repair = self.identity({'L4D2_VOLUME_OWNERSHIP': 'check', 'SHARED_GID': '10001'})
        repair.assert_not_called()
        self.assertTrue(any(call.args[:2] == ('/usr/sbin/usermod', '-aG') for call in run.call_args_list))

    def test_invalid_identity_or_password_fails_before_runtime_launch(self):
        for env in ({'USER': 'root'}, {'UID': '0'}, {'L4D2_VOLUME_OWNERSHIP': 'unknown'}, {'LGSM_PASSWORD': 'bad\npassword'}):
            with self.subTest(env=env), self.assertRaises(ValueError):
                self.identity(env)

    def test_ssh_configuration_keeps_root_login_disabled_with_existing_keys(self):
        ssh = self.root/'ssh'
        ssh.mkdir()
        (ssh/'ssh_host_ed25519_key').write_text('fixture')
        def paths(value):
            if value == '/run/sshd':
                return self.root/'sshd-run'
            return Path(value)
        with patch.object(boot, 'SSH', ssh), patch.object(boot, 'STATE', self.root), patch.object(boot, 'Path', side_effect=paths), patch.object(boot.os, 'chown'), patch.object(boot, 'protected'), patch.object(boot, 'migrate_keys') as migrate, patch.object(boot, 'protect_legacy_keys'), patch.object(boot, 'run') as run:
            config = boot.prepare_ssh({'SSH_PORT': '4231', 'LGSM_PASSWORD': 'private'})
            self.assertIn('PermitRootLogin no', config.read_text())
            self.assertIn('PasswordAuthentication yes', config.read_text())
            migrate.assert_called_once()
            run.assert_called_once_with('/usr/sbin/sshd', '-t', '-f', str(config))
            (ssh/'ssh_host_ed25519_key').unlink()
            boot.prepare_ssh({})
            self.assertIn('PasswordAuthentication no', config.read_text())
            self.assertTrue(any(call.args[0] == '/usr/bin/ssh-keygen' for call in run.call_args_list))

    def test_supervisor_stops_runtime_when_ssh_dies_and_reaps_stuck_ssh(self):
        runtime = MagicMock(pid=123, returncode=7)
        runtime.poll.side_effect = [None, None, 7]
        ssh = MagicMock()
        ssh.poll.return_value = 1
        ssh.wait.side_effect = [subprocess.TimeoutExpired('sshd', 5), 0]
        with patch.object(boot.os, 'geteuid', return_value=0), patch.object(boot, 'ROOT', self.root), patch.object(boot, 'STATE', self.root), patch.object(boot, 'protected'), patch.object(boot, 'prepare_identity', return_value=(1000, 1000)), patch.object(boot, 'environment', return_value={'USER': 'linuxgsm'}), patch.object(boot, 'prepare_ssh', return_value=self.root/'sshd_config'), patch.object(boot.subprocess, 'Popen', side_effect=[ssh, runtime]) as launch, patch.object(boot.signal, 'signal'), patch.object(boot.time, 'sleep'), patch.object(sys, 'argv', ['bootstrap']):
            self.assertEqual(boot.main(), 7)
        runtime.send_signal.assert_called_once_with(signal.SIGTERM)
        ssh.kill.assert_called_once()
        self.assertEqual((self.root/'runtime.pid').read_text(), '123')
        self.assertIn('--no-new-privs', launch.call_args_list[1].args[0])
        with patch.object(boot.os, 'geteuid', return_value=1000), self.assertRaises(ValueError):
            boot.main()


class RuntimeEntrypoints(unittest.TestCase):
    def test_health_drops_privileges_and_detects_dead_supervisor(self):
        env = {'UID': '1000', 'GID': '1000'}
        def text(path, *args, **kwargs):
            return json.dumps(env) if str(path).endswith('environment.json') else '123'
        with patch.object(Path, 'read_text', text), patch('os.kill') as kill, patch('os.execv') as execute:
            runpy.run_path(str(ROOT/'container/root/health.py'))
            self.assertIn('--bounding-set=-all', execute.call_args.args[1])
            kill.assert_called_once_with(123, 0)
        with patch.object(Path, 'read_text', text), patch('os.kill', side_effect=ProcessLookupError()), self.assertRaises(SystemExit):
            runpy.run_path(str(ROOT/'container/root/health.py'))

    def test_login_environment_quotes_data_and_applies_no_new_privs(self):
        data = {'UID': '1000', 'VALUE': "$(touch unsafe); a'b"}
        for args in (['environment', '--exports'], ['environment', '-c', 'id'], ['environment']):
            with patch.object(Path, 'read_text', return_value=json.dumps(data)), patch.object(sys, 'argv', args), patch('os.execv') as execute, patch.dict(os.environ, {}, clear=True), patch('sys.stdout', new_callable=io.StringIO) as output:
                runpy.run_path(str(ROOT/'container/root/environment.py'), run_name='__main__')
                if '--exports' in args:
                    self.assertNotIn('export UID=', output.getvalue())
                    self.assertIn('export VALUE=', output.getvalue())
                    execute.assert_not_called()
                else:
                    self.assertIn('--no-new-privs', execute.call_args.args[1])
                    self.assertEqual(os.environ['VALUE'], data['VALUE'])

    def test_runtime_shutdown_preserves_failure_status_and_stops_all_instances(self):
        child = MagicMock(pid=123, returncode=1)
        child.poll.side_effect = [None, 1, 1]
        handlers = {}
        def register(sig, handler):
            handlers[sig] = handler
        def sleep(_):
            handlers[signal.SIGTERM](signal.SIGTERM, None)
        with patch.object(sys, 'argv', ['runtime']), patch('signal.signal', side_effect=register), patch('subprocess.Popen', return_value=child), patch('subprocess.run', return_value=SimpleNamespace(returncode=0)) as run, patch('time.sleep', side_effect=sleep), patch('os.killpg'), patch.dict(os.environ, {'DIR_INSTALLER_BIN': '/fixture/bin'}), self.assertRaises(SystemExit) as exited:
            runpy.run_path(str(ROOT/'container/runtime.py'))
        self.assertEqual(exited.exception.code, 0)
        self.assertEqual(run.call_args.args[0], ['/bin/bash', '/fixture/bin/runtime_intent.sh', 'shutdown'])
