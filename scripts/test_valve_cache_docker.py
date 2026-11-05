#!/usr/bin/env python3
"""Opt-in Docker mount/permission/lock smoke using fake Valve bytes, never SRCDS."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import uuid

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'installer/tests'))
from test_valve_cache import FAKE_STEAM  # noqa: E402
from test_valve_cache_config import CacheCompose  # noqa: E402


def check_main_compose(fixture, image, name):
    """Exercise the actual main Compose mount with disabled, present and missing cache."""
    for i, volume in enumerate(('', name, name + '-missing')):
        rendered = CacheCompose().config('docker-compose.yml', volume=volume)
        if rendered.returncode:
            raise RuntimeError(rendered.stderr)
        model = json.loads(rendered.stdout)
        mount = next(v for v in model['services']['l4d2']['volumes'] if v['target'] == '/var/cache/l4d2-valve')
        isolated = {'services': {'fixture': {
            'image': image, 'network_mode': 'none', 'user': 'linuxgsm',
            'read_only': True, 'cap_drop': ['ALL'], 'security_opt': ['no-new-privileges'],
            'entrypoint': ['/usr/bin/python3'], 'command': ['/fixture-lib/valve_cache.py', 'status'],
            'environment': {'L4D2_VALVE_CACHE_VOLUME': volume, 'PYTHONDONTWRITEBYTECODE': '1'},
            'volumes': [mount, {'type': 'bind', 'source': str(ROOT / 'installer/lib'),
                               'target': '/fixture-lib', 'read_only': True}]}}}
        # Keep an unused external declaration in the disabled fixture too, as in
        # the source YAML, to check the engine path rather than only config output.
        isolated['volumes'] = {'valve_cache': model['volumes'].get(
            'valve_cache', {'external': True, 'name': name + '-unused'})}
        path = fixture / f'compose-{i}.json'
        path.write_text(json.dumps(isolated))
        command = ['docker', 'compose', '-p', name + f'-compose-{i}', '-f', str(path)]
        try:
            result = subprocess.run([*command, 'run', '--rm', '--no-deps', '--pull', 'never', 'fixture'],
                                    capture_output=True, text=True, timeout=30)
            if i == 2:
                if result.returncode == 0:
                    raise RuntimeError('Enabled cache must require the external volume to exist')
                exists = subprocess.run(['docker', 'volume', 'inspect', volume], capture_output=True).returncode == 0
                if exists:
                    raise RuntimeError('Compose unexpectedly created the external cache')
            elif result.returncode:
                raise RuntimeError(result.stdout + result.stderr)
            elif not volume and json.loads(result.stdout) != {'enabled': False}:
                raise RuntimeError('Empty variable did not disable the manager')
            if not volume:
                exists = subprocess.run(['docker', 'volume', 'inspect', name + '-unused'], capture_output=True).returncode == 0
                if exists:
                    raise RuntimeError('Disabled cache unexpectedly created a shared volume')
        finally:
            # The isolated fixture never contains data/SSH volumes. External cache survives.
            subprocess.run([*command, 'down', '-v', '--remove-orphans'], check=True,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(['docker', 'volume', 'inspect', name], check=True, stdout=subprocess.DEVNULL)
    print('Main Compose smoke passed: disabled without shared volume, enabled from env, missing external rejected, cache lifecycle preserved.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--image', required=True, help='Existing local gameserver image; no image pulls')
    args = parser.parse_args()
    subprocess.run(['docker', 'image', 'inspect', args.image], check=True, stdout=subprocess.DEVNULL)
    name = 'valve-cache-fixture-' + uuid.uuid4().hex
    processes = []
    containers = []
    with tempfile.TemporaryDirectory() as temporary:
        fixture = Path(temporary)
        # Fixtures are read-only to the containers; allow a differently mapped runtime UID.
        fixture.chmod(0o755)
        (fixture / 'steamcmd').write_text(FAKE_STEAM)
        (fixture / 'steamcmd').chmod(0o755)
        environment = dict(os.environ, L4D2_VALVE_CACHE_VOLUME=name)
        try:
            for _ in range(2):
                subprocess.run(['make', 'valve-cache-volume', f'VALVE_CACHE_INIT_IMAGE={args.image}'],
                               cwd=ROOT, env=environment, check=True)
            check_main_compose(fixture, args.image, name)
            common = ['docker', 'run', '--rm', '--pull', 'never', '--network', 'none', '--user', 'linuxgsm',
                      '--cap-drop', 'ALL', '--security-opt', 'no-new-privileges', '--workdir', '/tmp',
                      '-e', f'L4D2_VALVE_CACHE_VOLUME={name}', '-e', 'PATH=/fixture:/usr/bin:/bin',
                      '-e', 'PYTHONDONTWRITEBYTECODE=1', '-e', 'STEAM_DELAY=.3',
                      '-e', 'STEAM_CALLS=/var/cache/l4d2-valve/fixture-calls.jsonl',
                      '--mount', f'type=volume,source={name},target=/var/cache/l4d2-valve,volume-nocopy',
                      '-v', f'{fixture}:/fixture:ro', '-v', f'{ROOT / "installer/lib"}:/fixture-lib:ro',
                      '--entrypoint', '/usr/bin/python3']
            for i in range(2):
                container = name + f'-{i}'
                containers.append(container)
                processes.append(subprocess.Popen([*common, '--name', container, args.image,
                                                    '/fixture-lib/valve_cache.py', 'seed', '/tmp/serverfiles'],
                                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True))
            logs = []
            for process in processes:
                out, err = process.communicate(timeout=60)
                if process.returncode:
                    raise RuntimeError(out + err)
                logs.append(err)
            if not any('waiting; status=' in output for output in logs):
                raise RuntimeError('Concurrent container did not report waiting')
            subprocess.run([*common, args.image, '/fixture-lib/valve_cache.py', 'validate'], check=True, timeout=30)
            result = subprocess.run([*common, args.image, '-c',
                                     'from pathlib import Path; print(Path("/var/cache/l4d2-valve/fixture-calls.jsonl").read_text())'],
                                    check=True, capture_output=True, text=True)
            calls = [json.loads(line) for line in result.stdout.splitlines() if line.strip()]
            if sum('+app_update' in call for call in calls) != 2:
                raise RuntimeError('Expected one Windows+Linux download across two containers')
            print('Docker cache smoke passed: idempotent Make, non-root permissions, shared lock, one download, offline validation.')
        finally:
            for container in containers:
                subprocess.run(['docker', 'rm', '-f', container], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            for process in processes:
                process.communicate(timeout=10)
            # Only this invocation's uniquely named, disposable fixture volume is removed.
            subprocess.run(['docker', 'volume', 'rm', name], check=True, stdout=subprocess.DEVNULL)


if __name__ == '__main__':
    main()
