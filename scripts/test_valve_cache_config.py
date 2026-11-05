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
    def config(self, base, enabled=False, volume=''):
        with tempfile.TemporaryDirectory() as temporary:
            project = Path(temporary)
            for example, name in [('.env.example', '.env'), ('.env.secrets.example', '.env.secrets')]:
                shutil.copyfile(ROOT / example, project / name)
            command = ['docker', 'compose', '--project-directory', str(project),
                       '--env-file', str(project / '.env'), '-f', str(ROOT / base)]
            if enabled:
                command += ['-f', str(ROOT / 'docker-compose.valve-cache.yml')]
            command += ['config', '--format', 'json']
            # No real .env/secrets, network, Docker daemon or volumes are accessed.
            environment = {k: v for k, v in os.environ.items()
                           if not k.startswith(('COMPOSE_', 'BANSYSTEM_', 'L4D2_', 'SSH_', 'DATA_VOLUME_'))}
            environment.update(L4D2_VALVE_CACHE_VOLUME=volume, SSH_KEY='')
            return subprocess.run(command, env=environment, capture_output=True, text=True, timeout=15)

    def test_disabled_default_has_no_cache_mount_or_volume(self):
        values = dict(line.split('=', 1) for line in (ROOT / '.env.example').read_text().splitlines()
                      if line.startswith('L4D2_VALVE_CACHE_VOLUME='))
        self.assertEqual(values, {'L4D2_VALVE_CACHE_VOLUME': ''})
        for base in ('docker-compose.yml', 'docker-compose.dev.yml'):
            result = self.config(base)
            self.assertEqual(result.returncode, 0, result.stderr)
            config = json.loads(result.stdout)
            self.assertNotIn('valve_cache', config['volumes'])
            self.assertFalse(any(v['target'] == '/var/cache/l4d2-valve' for v in config['services']['l4d2']['volumes']))

    def test_enabled_uses_exact_external_volume_with_no_population(self):
        for base in ('docker-compose.yml', 'docker-compose.dev.yml'):
            result = self.config(base, enabled=True, volume='shared_valve_fixture')
            self.assertEqual(result.returncode, 0, result.stderr)
            config = json.loads(result.stdout)
            self.assertEqual(config['volumes']['valve_cache'], {'external': True, 'name': 'shared_valve_fixture'})
            service = config['services']['l4d2']
            self.assertEqual(service['environment']['L4D2_VALVE_CACHE_VOLUME'], 'shared_valve_fixture')
            mount = next(v for v in service['volumes'] if v['target'] == '/var/cache/l4d2-valve')
            self.assertEqual(mount['source'], 'valve_cache')
            self.assertTrue(mount['volume']['nocopy'])
            self.assertFalse(mount.get('read_only', False))

    def test_overlay_requires_explicit_volume_name(self):
        result = self.config('docker-compose.yml', enabled=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('L4D2_VALVE_CACHE_VOLUME', result.stderr)


if __name__ == '__main__':
    unittest.main()
