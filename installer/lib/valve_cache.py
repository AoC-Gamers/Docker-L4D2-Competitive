"""Optional, host-local Valve installation seed. Never updates a live server."""
import argparse
from contextlib import contextmanager
from datetime import datetime, timezone
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import time
import uuid

CACHE_ROOT = Path('/var/cache/l4d2-valve')
APPID = 222860
REQUIRED = ('srcds_run', 'srcds_linux', 'left4dead2/gameinfo.txt',
            'left4dead2/steam.inf', 'left4dead2/pak01_dir.vpk',
            'steamapps/appmanifest_222860.acf')


def now():
    return datetime.now(timezone.utc).isoformat()


def log(message):
    print(f'Valve cache: {message}', file=sys.stderr, flush=True)


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def atomic_json(path, value):
    fd, temporary = tempfile.mkstemp(prefix=f'.{path.name}-', dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as stream:
            json.dump(value, stream, sort_keys=True)
            stream.write('\n')
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        directory = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def read_json(path):
    if path.is_symlink() or not path.is_file():
        raise ValueError(f'Missing or unsafe metadata: {path}')
    with path.open() as stream:
        value = json.load(stream)
    if not isinstance(value, dict):
        raise ValueError(f'Metadata must be a JSON object: {path}')
    return value


def inventory(root):
    """Hash all bytes and executable modes, preserving only internal relative links."""
    entries = {}
    for directory, directories, files in os.walk(root, followlinks=False):
        for name in sorted(directories + files):
            path = Path(directory) / name
            relative = path.relative_to(root).as_posix()
            info = path.lstat()
            if stat.S_ISLNK(info.st_mode):
                link = os.readlink(path)
                if os.path.isabs(link) or not path.resolve().is_relative_to(root.resolve()):
                    raise ValueError(f'External symlink in Valve payload: {relative}')
                if not path.exists():
                    raise ValueError(f'Broken symlink in Valve payload: {relative}')
                entries[relative] = {'type': 'link', 'target': link}
            elif stat.S_ISREG(info.st_mode):
                entries[relative] = {'type': 'file', 'size': info.st_size,
                                     'mode': stat.S_IMODE(info.st_mode), 'sha256': digest(path)}
            elif stat.S_ISDIR(info.st_mode):
                entries[relative] = {'type': 'directory'}
            else:
                raise ValueError(f'Special file in Valve payload: {relative}')
    return entries


def check_payload(payload):
    for name in REQUIRED:
        path = payload / name
        if path.is_symlink() or not path.is_file() or path.stat().st_size == 0:
            raise ValueError(f'Incomplete Valve payload: {name}')
    manifest = (payload / REQUIRED[-1]).read_text()
    fields = dict(re.findall(r'"(appid|StateFlags|buildid)"\s+"([0-9]+)"', manifest))
    if fields.get('appid') != str(APPID) or fields.get('StateFlags') != '4' or not int(fields.get('buildid', '0')):
        raise ValueError('Steam appmanifest does not confirm a complete L4D2 installation')
    return fields['buildid']


class Cache:
    def __init__(self, root=CACHE_ROOT, *, require_mount=True, poll_seconds=5):
        self.root = Path(root)
        self.poll_seconds = poll_seconds
        if self.root.is_symlink() or self.root.resolve() != self.root:
            raise ValueError('Cache mount must be a physical absolute path')
        if require_mount:
            mounts = {re.sub(r'\\([0-7]{3})', lambda m: chr(int(m[1], 8)), line.split()[4])
                      for line in Path('/proc/self/mountinfo').read_text().splitlines()}
            if str(self.root) not in mounts:
                raise ValueError('Cache volume is not mounted at /var/cache/l4d2-valve; use the cache Compose override')
        if not self.root.is_dir() or not os.access(self.root, os.R_OK | os.W_OK | os.X_OK):
            raise ValueError('Cache volume must exist and be writable by linuxgsm; prepare its UID/GID permissions')
        self.metadata = self.root / 'metadata.json'
        self.current = self.root / 'current.json'
        self.operation = {}

    def lock_fd(self):
        fd = os.open(self.root / '.lock', os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
        if not stat.S_ISREG(os.fstat(fd).st_mode):
            os.close(fd)
            raise ValueError('Cache lock must be a regular file')
        return fd

    def status(self):
        try:
            metadata = read_json(self.metadata)
        except (ValueError, OSError):
            metadata = {'schema_version': 1, 'appid': APPID, 'status': 'empty'}
        metadata.setdefault('status', 'unknown')
        fd = self.lock_fd()
        try:
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                locked = False
            except BlockingIOError:
                locked = True
        finally:
            os.close(fd)
        # A PID, timestamp or leftover .lock file never determines ownership.
        return {**metadata, 'lock_active': locked,
                'interrupted': not locked and metadata.get('status') in {'downloading', 'validating', 'copying'}}

    @contextmanager
    def locked(self):
        fd = self.lock_fd()
        try:
            while True:
                try:
                    fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    break
                except BlockingIOError:
                    status = self.status()
                    log(f"waiting; status={status['status']} phase={status.get('phase', 'unknown')} "
                        f"since={status.get('started_at', 'unknown')}")
                    time.sleep(self.poll_seconds)
            yield
        finally:
            os.close(fd)

    def phase(self, status, phase, **extra):
        self.operation.update(schema_version=1, appid=APPID, status=status, phase=phase,
                              updated_at=now(), **extra)
        atomic_json(self.metadata, self.operation)

    def begin(self):
        self.operation = {'started_at': now(), 'last_error': None}

    def generation(self):
        reference = read_json(self.current)
        if reference.get('schema_version') != 1 or reference.get('appid') != APPID:
            raise ValueError('Unsupported cache reference')
        generation = reference.get('generation', '')
        if not isinstance(generation, str) or not re.fullmatch(r'[a-f0-9]{32}', generation):
            raise ValueError('Unsafe cache generation')
        parent = self.root / 'versions'
        directory = parent / generation
        if parent.is_symlink() or directory.is_symlink() or (directory / 'payload').is_symlink():
            raise ValueError('Unsafe cache generation path')
        manifest_path = directory / 'manifest.json'
        if manifest_path.is_symlink() or digest(manifest_path) != reference.get('manifest_sha256'):
            raise ValueError('Cache manifest checksum mismatch')
        manifest = read_json(manifest_path)
        if manifest.get('schema_version') != 1 or manifest.get('appid') != APPID:
            raise ValueError('Unsupported cache manifest')
        return directory / 'payload', manifest

    def verify(self):
        payload, manifest = self.generation()
        if check_payload(payload) != manifest['build_id'] or inventory(payload) != manifest['files']:
            raise ValueError('Valve cache integrity check failed; run validate and download --force')
        return payload, manifest

    def steam(self, *arguments):
        # SteamCMD's HOME remains private to each container, outside the shared payload.
        subprocess.run(['steamcmd', *arguments], check=True)

    def download(self, force=False):
        if self.current.exists() and not force:
            self.begin()
            self.phase('validating', 'cached_integrity')
            result = self.verify()
            self.phase('ready', 'complete', build_id=result[1]['build_id'])
            log('complete copy already available; download skipped')
            return result
        self.begin()
        generation = uuid.uuid4().hex
        workspace = self.root / f'.work-{generation}'
        workspace.mkdir()
        payload = workspace / 'payload'
        payload.mkdir()
        self.phase('downloading', 'steamcmd_bootstrap')
        self.steam('+login', 'anonymous', '+quit')
        for platform in ('windows', 'linux'):
            self.phase('downloading', f'steamcmd_{platform}')
            self.steam('+force_install_dir', str(payload), '+login', 'anonymous',
                       '+@sSteamCmdForcePlatformType', platform, '+app_update', str(APPID), 'validate', '+quit')
        self.phase('validating', 'download_integrity')
        build = check_payload(payload)
        manifest = {'schema_version': 1, 'appid': APPID, 'build_id': build,
                    'created_at': now(), 'platforms': ['windows', 'linux'], 'files': inventory(payload)}
        atomic_json(workspace / 'manifest.json', manifest)
        versions = self.root / 'versions'
        if versions.is_symlink():
            raise ValueError('Unsafe cache versions path')
        versions.mkdir(exist_ok=True)
        os.rename(workspace, versions / generation)
        atomic_json(self.current, {'schema_version': 1, 'appid': APPID, 'generation': generation,
                                 'manifest_sha256': digest(versions / generation / 'manifest.json')})
        self.phase('ready', 'complete', generation=generation, build_id=build)
        log(f'clean copy available; build={build}')
        return versions / generation / 'payload', manifest

    def seed(self, target):
        target = Path(target)
        # Recheck after waiting: another installer may have finished this destination.
        if (target / 'srcds_run').is_file():
            log('game already installed; cache skipped')
            return
        if target.is_symlink() or target.resolve() != target.absolute():
            raise ValueError('Installation destination must be a physical absolute path')
        if target.is_relative_to(self.root) or self.root.is_relative_to(target):
            raise ValueError('Cache and private installation must not overlap')
        if target.exists() and (not target.is_dir() or any(target.iterdir())):
            raise ValueError('Cache only seeds an absent or empty serverfiles directory; existing data is preserved')
        payload, manifest = self.download()
        self.begin()
        self.phase('copying', 'private_installation', build_id=manifest['build_id'])
        # Prime private Steam runtime libraries even when the game bytes come from cache.
        self.steam('+login', 'anonymous', '+quit')
        target.parent.mkdir(parents=True, exist_ok=True)
        staging = Path(tempfile.mkdtemp(prefix='.valve-seed-', dir=target.parent))
        try:
            destination = staging / 'serverfiles'
            shutil.copytree(payload, destination, symlinks=True)
            if inventory(destination) != manifest['files']:
                raise ValueError('Private Valve copy failed integrity verification')
            if target.exists():
                target.rmdir()  # Fails safely if another actor populated it.
            os.rename(destination, target)
        finally:
            shutil.rmtree(staging)
        self.phase('ready', 'complete', build_id=manifest['build_id'])
        log(f'private installation copied to {target}')

    def execute(self, command, *, force=False, target=None):
        if command == 'status':
            return self.status()
        with self.locked():
            try:
                if command == 'download':
                    self.download(force)
                elif command == 'validate':
                    self.begin()
                    self.phase('validating', 'cached_integrity')
                    _, manifest = self.verify()
                    self.phase('ready', 'complete', build_id=manifest['build_id'])
                    log('integrity verified (offline; no Steam download)')
                elif command == 'seed':
                    self.seed(target)
            except Exception as error:
                self.phase('failed', 'error', last_error=str(error))
                raise
        return None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    commands.add_parser('status')
    commands.add_parser('validate')
    download = commands.add_parser('download')
    download.add_argument('--force', action='store_true')
    seed = commands.add_parser('seed', help='installer integration; empty destinations only')
    seed.add_argument('target', type=Path)
    args = parser.parse_args()
    # An installed game must never wait for, or require, the cache mount.
    if args.command == 'seed' and (args.target / 'srcds_run').is_file():
        log('game already installed; cache skipped')
        return
    volume = os.environ.get('L4D2_VALVE_CACHE_VOLUME', '')
    if not volume:
        if args.command == 'status':
            print(json.dumps({'enabled': False}))
            return
        parser.error('L4D2_VALVE_CACHE_VOLUME is empty; cache is disabled')
    if not re.fullmatch(r'[a-zA-Z0-9][a-zA-Z0-9_.-]*', volume):
        parser.error('L4D2_VALVE_CACHE_VOLUME must be a Docker volume name')
    if os.geteuid() == 0:
        parser.error('Run the cache lifecycle as linuxgsm, never as root')
    result = Cache().execute(args.command, force=getattr(args, 'force', False), target=getattr(args, 'target', None))
    if result is not None:
        print(json.dumps(result, indent=2, sort_keys=True))


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as failure:
        log(str(failure))
        sys.exit(1)
