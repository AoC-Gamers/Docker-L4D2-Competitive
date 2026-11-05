#!/usr/bin/env python3
"""Host-only volume preparation. No gameserver starts and no recursive chown."""
import argparse
import os
from pathlib import Path
import re
import subprocess
import sys


def settings(root):
    values = {}
    path = root / '.env'
    if path.is_file():
        for line in path.read_text().splitlines():
            match = re.fullmatch(r'(L4D2_VALVE_CACHE_VOLUME|UID|GID)\s*=\s*(.*?)\s*', line)
            if match:
                values[match[1]] = match[2].strip('"\'')
    return {**values, **os.environ}


def docker(*args, check=True):
    return subprocess.run(['docker', *args], text=True, capture_output=True, check=check)


def prepare(volume, image, uid=None, gid=None):
    if not re.fullmatch(r'[a-zA-Z0-9][a-zA-Z0-9_.-]*', volume):
        raise ValueError('Set L4D2_VALVE_CACHE_VOLUME to a Docker volume name in .env or the environment')
    if not image or image.startswith('-'):
        raise ValueError('Set VALVE_CACHE_INIT_IMAGE to a trusted gameserver image')
    if uid is None or gid is None:
        account = docker('run', '--rm', '--network', 'none', '--user', 'linuxgsm',
                         '--entrypoint', '/usr/bin/getent', image, 'passwd', 'linuxgsm').stdout.strip().split(':')
        uid = uid if uid is not None else account[2]
        gid = gid if gid is not None else account[3]
    uid, gid = str(uid), str(gid)
    if not all(re.fullmatch(r'[1-9][0-9]*', value) for value in (uid, gid)):
        raise ValueError('Cache UID/GID must be positive non-root numeric IDs')
    exists = docker('volume', 'inspect', volume, check=False).returncode == 0
    if not exists:
        docker('volume', 'create', '--label', 'com.aoc.l4d2.valve-cache=1', volume)
        # Trusted system binary only; never root code from /app or /data.
        docker('run', '--rm', '--network', 'none', '--user', '0:0', '--entrypoint', '/usr/bin/install',
               '--mount', f'type=volume,source={volume},target=/cache,volume-nocopy', image,
               '-d', '-m', '0700', '-o', uid, '-g', gid, '/cache')
    # An existing volume is checked as the runtime user, without changing ownership.
    docker('run', '--rm', '--network', 'none', '--user', f'{uid}:{gid}', '--cap-drop', 'ALL',
           '--security-opt', 'no-new-privileges', '--entrypoint', '/usr/bin/test',
           '--mount', f'type=volume,source={volume},target=/cache,volume-nocopy', image,
           '-r', '/cache', '-a', '-w', '/cache', '-a', '-x', '/cache')
    print(f'Valve cache volume {volume}: {"existing, checked" if exists else "created"}; UID:GID={uid}:{gid}')


def main():
    values = settings(Path(__file__).resolve().parents[1])
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--image', required=True)
    parser.add_argument('--uid', default=values.get('VALVE_CACHE_UID') or values.get('UID'))
    parser.add_argument('--gid', default=values.get('VALVE_CACHE_GID') or values.get('GID'))
    args = parser.parse_args()
    prepare(values.get('L4D2_VALVE_CACHE_VOLUME', ''), args.image, args.uid, args.gid)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, IndexError, OSError, subprocess.CalledProcessError) as failure:
        # Do not print captured output or any local env contents.
        print(f'Valve cache volume preparation failed: {failure}. Existing volumes are never repaired automatically.', file=sys.stderr)
        sys.exit(1)
