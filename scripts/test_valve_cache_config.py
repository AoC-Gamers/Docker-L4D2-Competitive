"""Compose contract for the optional seed, reusable in the derived repositories."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('docker'), 'Compose CLI unavailable in inherited runtime fixture')
class CacheCompose(unittest.TestCase):
    def config(self, base, volume='', env_volume=None):
        with tempfile.TemporaryDirectory() as temporary:
            project = Path(temporary)
            for example, name in [('.env.example', '.env'), ('.env.secrets.example', '.env.secrets')]:
                shutil.copyfile(ROOT / example, project / name)
            if env_volume is not None:
                env = project / '.env'
                env.write_text(env.read_text().replace('L4D2_VALVE_CACHE_VOLUME=\n',
                                                       'L4D2_VALVE_CACHE_VOLUME=' + env_volume + '\n'))
            command = ['docker', 'compose', '--project-directory', str(project),
                       '--env-file', str(project / '.env'), '-f', str(ROOT / base)]
            command += ['config', '--format', 'json']
            # No real .env/secrets, network, Docker daemon or volumes are accessed.
            environment = {k: v for k, v in os.environ.items()
                           if not k.startswith(('COMPOSE_', 'BANSYSTEM_', 'L4D2_', 'SSH_', 'DATA_VOLUME_'))}
            environment['SSH_KEY'] = ''
            if volume is not None:
                environment['L4D2_VALVE_CACHE_VOLUME'] = volume
            return subprocess.run(command, env=environment, capture_output=True, text=True, timeout=15)

    def test_disabled_default_needs_no_shared_volume(self):
        values = dict(line.split('=', 1) for line in (ROOT / '.env.example').read_text().splitlines()
                      if line.startswith('L4D2_VALVE_CACHE_VOLUME='))
        self.assertEqual(values, {'L4D2_VALVE_CACHE_VOLUME': ''})
        for base in ('docker-compose.yml', 'docker-compose.dev.yml'):
            for volume in ('', None):
                result = self.config(base, volume=volume)
                self.assertEqual(result.returncode, 0, result.stderr)
                config = json.loads(result.stdout)
                self.assertNotIn('valve_cache', config['volumes'])
                service = config['services']['l4d2']
                self.assertEqual(service['environment']['L4D2_VALVE_CACHE_VOLUME'], '')
                mount = next(v for v in service['volumes'] if v['target'] == '/var/cache/l4d2-valve')
                self.assertNotIn('source', mount)  # Anonymous, empty, never a shared cache.
                self.assertTrue(mount['volume']['nocopy'])

    def test_enabled_uses_exact_external_volume_with_no_population(self):
        for base in ('docker-compose.yml', 'docker-compose.dev.yml'):
            result = self.config(base, volume='shared_valve_fixture')
            self.assertEqual(result.returncode, 0, result.stderr)
            config = json.loads(result.stdout)
            self.assertEqual(config['volumes']['valve_cache'], {'external': True, 'name': 'shared_valve_fixture'})
            service = config['services']['l4d2']
            self.assertEqual(service['environment']['L4D2_VALVE_CACHE_VOLUME'], 'shared_valve_fixture')
            mount = next(v for v in service['volumes'] if v['target'] == '/var/cache/l4d2-valve')
            self.assertEqual(mount['source'], 'valve_cache')
            self.assertTrue(mount['volume']['nocopy'])
            self.assertFalse(mount.get('read_only', False))

    def test_env_file_alone_enables_cache_and_shell_override_stays_consistent(self):
        for base in ('docker-compose.yml', 'docker-compose.dev.yml'):
            for override in (None, 'shell_cache'):
                result = self.config(base, volume=override, env_volume='env_file_cache')
                self.assertEqual(result.returncode, 0, result.stderr)
                config = json.loads(result.stdout)
                expected = override or 'env_file_cache'
                service = config['services']['l4d2']
                self.assertEqual(service['environment']['L4D2_VALVE_CACHE_VOLUME'], expected)
                mount = next(v for v in service['volumes'] if v['target'] == '/var/cache/l4d2-valve')
                self.assertEqual(mount['source'], 'valve_cache')
                self.assertEqual(config['volumes']['valve_cache']['name'], expected)


if __name__ == '__main__':
    unittest.main()
