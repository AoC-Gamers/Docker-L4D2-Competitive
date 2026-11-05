"""Host helper preserves existing volumes and treats env files as literal data."""
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('volume_helper', ROOT / 'scripts/valve_cache_volume.py')
helper = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(helper)


class VolumePreparation(unittest.TestCase):
    def test_existing_volume_is_only_checked_without_privileged_repair(self):
        with patch.object(helper, 'docker', return_value=subprocess.CompletedProcess([], 0, '', '')) as docker:
            helper.prepare('existing_cache', 'fixture:local', 1000, 1000)
        commands = [call.args for call in docker.call_args_list]
        self.assertEqual(len(commands), 2)
        self.assertEqual(commands[0], ('volume', 'inspect', 'existing_cache'))
        self.assertNotIn('/usr/bin/install', commands[1])
        self.assertIn('1000:1000', commands[1])

    def test_new_volume_initializes_only_root_and_then_checks_runtime_access(self):
        def run(*args, **kwargs):
            return subprocess.CompletedProcess([], 1 if args[:2] == ('volume', 'inspect') else 0, '', '')
        with patch.object(helper, 'docker', side_effect=run) as docker:
            helper.prepare('new_cache', 'fixture:local', 1200, 1300)
        commands = [call.args for call in docker.call_args_list]
        self.assertEqual(len(commands), 4)
        self.assertEqual(commands[1][:2], ('volume', 'create'))
        self.assertIn('/usr/bin/install', commands[2])
        self.assertNotIn('-R', commands[2])
        self.assertIn('1200:1300', commands[3])

    def test_invalid_or_missing_configuration_does_not_call_docker(self):
        for volume, uid, gid in [('', 1000, 1000), ('../data', 1000, 1000), ('valid', 0, 1000)]:
            with self.subTest(volume=volume), patch.object(helper, 'docker') as docker:
                with self.assertRaises(ValueError):
                    helper.prepare(volume, 'fixture:local', uid, gid)
                docker.assert_not_called()

    def test_env_is_not_executed_and_environment_wins(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            marker = root / 'executed'
            (root / '.env').write_text(f'IGNORED=$(touch {marker})\nL4D2_VALVE_CACHE_VOLUME=literal_cache\n')
            with patch.dict(helper.os.environ, {'L4D2_VALVE_CACHE_VOLUME': 'environment_cache'}):
                self.assertEqual(helper.settings(root)['L4D2_VALVE_CACHE_VOLUME'], 'environment_cache')
            self.assertFalse(marker.exists())
