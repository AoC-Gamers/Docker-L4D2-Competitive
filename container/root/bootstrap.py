#!/usr/bin/python3
"""Trusted image-owned bootstrap. Never import or execute runtime code as root."""
import grp
import json
import os
from pathlib import Path
import pwd
import re
import signal
import stat
import subprocess
import sys
import tempfile
import time

ROOT = Path('/usr/local/libexec/l4d2')
STATE = Path('/run/l4d2')
SSH = Path('/var/lib/l4d2/ssh')


def run(*args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def numeric(value, name, upper=2147483647):
    if not re.fullmatch(r'[1-9][0-9]*', str(value)) or int(value) > upper:
        raise ValueError(f'{name} must be a positive numeric ID (root is forbidden)')
    return int(value)


def protected(path):
    path = Path(path)
    for p in [path, *path.parents]:
        s = p.lstat()
        if stat.S_ISLNK(s.st_mode) or s.st_uid != 0 or s.st_mode & 0o022:
            raise ValueError(f'Privileged path must be root-owned and immutable to runtime: {p}')


def runtime_command(uid, gid, command):
    return ['/usr/bin/setpriv', f'--reuid={uid}', f'--regid={gid}', '--init-groups',
            '--inh-caps=-all', '--ambient-caps=-all', '--bounding-set=-all',
            '--no-new-privs', *command]


def mount_roots():
    roots = set()
    for line in Path('/proc/self/mountinfo').read_text().splitlines():
        raw = line.split()[4]
        roots.add(re.sub(r'\\([0-7]{3})', lambda m: chr(int(m[1], 8)), raw))
    return roots


def repair_data(data, uid, gid, old_uid, old_gid, excludes):
    """One-time/explicit migration; no symlinks or nested mounts are traversed."""
    if data.is_symlink():
        raise ValueError('/data must be a physical mount root')
    excluded = {Path(p) for p in excludes if p}
    excluded |= {Path(p) for p in mount_roots() if p.startswith(str(data) + '/')}
    for directory, dirs, files in os.walk(data, followlinks=False):
        base = Path(directory)
        dirs[:] = [n for n in dirs if base/n not in excluded and not (base/n).is_symlink()]
        for p in [base, *(base/n for n in files)]:
            if p in excluded:
                continue
            s = p.lstat()
            if stat.S_ISLNK(s.st_mode):
                continue
            new_uid = uid if s.st_uid in {0, old_uid} else -1
            # Preserve SGID directories and unrelated/shared groups.
            new_gid = gid if s.st_gid in {0, old_gid} and not s.st_mode & stat.S_ISGID else -1
            if new_uid != -1 or new_gid != -1:
                os.chown(p, new_uid, new_gid, follow_symlinks=False)


def migrate_keys(source, destination):
    """Copy legacy host identity without following user-controlled symlinks."""
    if not source.exists() and not source.is_symlink():
        return
    fd = os.open(source, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        for name in ('ssh_host_ed25519_key', 'ssh_host_rsa_key', 'ssh_host_ecdsa_key'):
            target = destination/name
            if target.exists():
                continue
            try:
                keyfd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW, dir_fd=fd)
            except FileNotFoundError:
                continue
            try:
                s = os.fstat(keyfd)
                if not stat.S_ISREG(s.st_mode) or s.st_nlink != 1 or s.st_size > 16384 or s.st_mode & 0o077:
                    raise ValueError('Legacy host key is not a private regular key')
                content = os.read(keyfd, 16385)
            finally:
                os.close(keyfd)
            # Publish only a complete, validated identity; never overwrite a key.
            out, temporary = tempfile.mkstemp(prefix='.' + name + '-', dir=destination)
            try:
                with os.fdopen(out, 'wb') as stream:
                    stream.write(content)
                    stream.flush()
                    os.fsync(stream.fileno())
                run('/usr/bin/ssh-keygen', '-y', '-f', temporary, stdout=subprocess.DEVNULL)
                os.link(temporary, target, follow_symlinks=False)
                directory = os.open(destination, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
                try:
                    os.fsync(directory)
                finally:
                    os.close(directory)
            finally:
                os.unlink(temporary)
    finally:
        os.close(fd)


def protect_legacy_keys(source):
    # Preserve legacy bytes for rollback, but do not leave the same private key
    # readable by the gameserver after its protected copy has been established.
    if not source.exists() and not source.is_symlink():
        return
    directory = os.open(source, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        for name in ('ssh_host_ed25519_key', 'ssh_host_rsa_key', 'ssh_host_ecdsa_key'):
            try:
                fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW, dir_fd=directory)
            except FileNotFoundError:
                continue
            try:
                info = os.fstat(fd)
                if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1:
                    raise ValueError('Legacy host key must be a single-link regular file')
                os.fchown(fd, 0, 0)
                os.fchmod(fd, 0o600)
            finally:
                os.close(fd)
        os.fchown(directory, 0, 0)
        os.fchmod(directory, 0o700)
    finally:
        os.close(directory)


def prepare_identity(env):
    user = pwd.getpwnam('linuxgsm')
    uid = numeric(env.get('UID', user.pw_uid), 'UID')
    gid = numeric(env.get('GID', user.pw_gid), 'GID')
    if env.get('USER', 'linuxgsm') != 'linuxgsm':
        raise ValueError('The runtime account must be linuxgsm')
    if gid != user.pw_gid:
        run('/usr/sbin/groupmod', '-g', str(gid), 'linuxgsm')
    if uid != user.pw_uid:
        run('/usr/sbin/usermod', '-u', str(uid), 'linuxgsm')
    run('/usr/sbin/usermod', '-d', '/data', '-s', str(ROOT/'login-shell'), 'linuxgsm')
    # Image-owned declarative contract; descendants add groups without root hooks.
    config = ROOT/'groups.json'
    protected(config)
    for name in json.loads(config.read_text())['environment_gids']:
        if not re.fullmatch(r'[A-Z][A-Z0-9_]*', name):
            raise ValueError('Invalid supplementary-group environment name')
        value = env.get(name)
        if not value:
            continue
        extra = numeric(value, name)
        try:
            group = grp.getgrgid(extra).gr_name
        except KeyError:
            group = f'l4d2-extra-{extra}'
            run('/usr/sbin/groupadd', '-g', str(extra), group)
        if 'linuxgsm' not in grp.getgrnam(group).gr_mem:
            run('/usr/sbin/usermod', '-aG', group, 'linuxgsm')
    if uid != user.pw_uid or gid != user.pw_gid:
        repair_data(Path('/app'), uid, gid, user.pw_uid, user.pw_gid, [])
    data = Path('/data')
    data.mkdir(exist_ok=True)
    before = data.lstat()
    mode = env.get('L4D2_VOLUME_OWNERSHIP', 'auto')
    if mode not in {'auto', 'check', 'repair'}:
        raise ValueError('L4D2_VOLUME_OWNERSHIP must be auto, check or repair')
    migration = before.st_uid in {0, user.pw_uid} and (before.st_uid != uid or before.st_gid != gid)
    if mode == 'repair' or (mode == 'auto' and migration):
        print('Preparing volume ownership (initialization or explicit migration)', flush=True)
        repair_data(data, uid, gid, user.pw_uid, user.pw_gid,
                    ['/data/ssh', env.get('REPO_RESOURCES_DIR', '/data/resources'), env.get('BANSYSTEM_ARTIFACT_ROOT', '')])
    run(*runtime_command(uid, gid, ['/usr/bin/test', '-w', '/data']))
    password = env.get('LGSM_PASSWORD', '')
    if password:
        if '\n' in password or '\r' in password or '\x00' in password:
            raise ValueError('LGSM_PASSWORD must be a single line')
        run('/usr/sbin/chpasswd', input=f'linuxgsm:{password}\n', text=True)
    return uid, gid


def environment(env, uid, gid):
    result = {k: v for k, v in env.items() if re.fullmatch(r'[A-Z][A-Z0-9_]*', k) and (k.startswith(('LGSM_', 'L4D2_', 'STV_', 'GEOIPUPDATE_', 'BANSYSTEM_', 'STACK_', 'NPM_CONFIG_', 'STEAM_', 'STEAMWORKS_'))
              or k in {'GAMESERVER', 'SSH_PORT', 'SSH_KEY', 'GITHUB_TOKEN', 'AOC_TOKEN', 'REPO_RESOURCES_DIR', 'LANG', 'TERM'})}
    result.update(USER='linuxgsm', LOGNAME='linuxgsm', HOME='/data', SHELL='/bin/bash', UID=str(uid), GID=str(gid),
                  PATH='/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games')
    app = '/app'
    installer = '/data/installer'
    game = result.get('LGSM_SERVERFILES', '/data/serverfiles') + '/left4dead2'
    result.update(DIR_APP=app, DIR_TMP=app+'/tmp', DIR_INSTALLER=installer,
                  DIR_INSTALLER_BIN=installer+'/bin', DIR_INSTALLER_LIB=installer+'/lib',
                  DIR_INSTALLER_CONFIG=installer+'/config', DIR_INSTALLER_STATE=installer+'/state',
                  DIR_STACK='/data/stack', DIR_STACK_HOOKS='/data/stack/hooks', DIR_LEFT4DEAD2=game,
                  DIR_ADDONS=game+'/addons', DIR_SOURCEMOD=game+'/addons/sourcemod', DIR_CFG=game+'/cfg')
    for name, value in {'GAMESERVER':'l4d2server', 'SSH_PORT':'422', 'STACK_PROFILE':'default',
                        'L4D2_INSTALL':'normal', 'L4D2_AUTOSTART':'true', 'L4D2_UPDATER':'true',
                        'L4D2_STACK_AUTOUPDATE':'false', 'REPO_RESOURCES_DIR':'/data/resources',
                        'NPM_CONFIG_AUDIT':'false', 'GEOIPUPDATE_ENABLED':'false'}.items():
        result.setdefault(name, value)
    output = STATE/'environment.json'
    output.write_text(json.dumps(result))
    os.chown(output, 0, gid)
    output.chmod(0o640)
    # Compatibility for existing bashrc/PAM consumers: public, literal values only.
    public = {k: v for k, v in result.items() if k.startswith('DIR_') or k in {'PATH','HOME','USER','GID','SSH_PORT'}}
    Path('/etc/environment').write_text(''.join(f'{k}={json.dumps(v)}\n' for k,v in public.items()
                                               if re.fullmatch(r'[-_a-zA-Z0-9/.+:@,]*', v)))
    return result


def prepare_ssh(env):
    port = numeric(env.get('SSH_PORT', '422'), 'SSH_PORT', 65535)
    SSH.mkdir(parents=True, exist_ok=True)
    os.chown(SSH, 0, 0)
    SSH.chmod(0o700)
    protected(SSH)
    migrate_keys(Path('/data/ssh'), SSH)
    protect_legacy_keys(Path('/data/ssh'))
    if not list(SSH.glob('ssh_host_*_key')):
        run('/usr/bin/ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-f', str(SSH/'ssh_host_ed25519_key'))
        run('/usr/bin/ssh-keygen', '-q', '-t', 'rsa', '-b', '3072', '-N', '', '-f', str(SSH/'ssh_host_rsa_key'))
    keys = []
    for p in sorted(SSH.glob('ssh_host_*_key')):
        protected(p)
        p.chmod(0o600)
        keys.append(f'HostKey {p}')
    Path('/run/sshd').mkdir(exist_ok=True)
    config = STATE/'sshd_config'
    config.write_text('\n'.join([f'Port {port}', *keys, 'PidFile /run/l4d2/sshd.pid',
        'PermitRootLogin no', 'AllowUsers linuxgsm', 'PubkeyAuthentication yes',
        'PasswordAuthentication '+('yes' if env.get('LGSM_PASSWORD') else 'no'),
        'KbdInteractiveAuthentication no', 'UsePAM yes', 'StrictModes yes',
        'AuthorizedKeysFile .ssh/authorized_keys', 'PrintMotd no',
        'Subsystem sftp /usr/lib/openssh/sftp-server', '']) )
    run('/usr/sbin/sshd', '-t', '-f', str(config))
    return config


def main():
    if os.geteuid() != 0:
        raise ValueError('SSH/bootstrap preparation requires root; runtime is dropped to linuxgsm')
    protected(ROOT/'bootstrap.py')
    STATE.mkdir(mode=0o755, exist_ok=True)
    protected(STATE)
    env = dict(os.environ)
    uid, gid = prepare_identity(env)
    runtime_env = environment(env, uid, gid)
    config = prepare_ssh(env)
    clean = {'PATH': '/usr/sbin:/usr/bin:/sbin:/bin', 'LANG': 'C.UTF-8'}
    ssh = subprocess.Popen(['/usr/sbin/sshd', '-D', '-e', '-f', str(config)], env=clean)
    runtime = subprocess.Popen(runtime_command(uid, gid, ['/usr/bin/python3', '-I', '/app/container/runtime.py', *sys.argv[1:]]),
                               env=runtime_env, cwd='/app')
    (STATE/'runtime.pid').write_text(str(runtime.pid))
    stopping = False
    def stop(signum, frame):
        nonlocal stopping
        if not stopping:
            stopping = True
            if runtime.poll() is None:
                runtime.send_signal(signum)
    for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGQUIT):
        signal.signal(sig, stop)
    while runtime.poll() is None:
        if ssh.poll() is not None and not stopping:
            print('SSH exited unexpectedly; stopping runtime', flush=True)
            stop(signal.SIGTERM, None)
        time.sleep(0.2)
    ssh.terminate()
    try:
        ssh.wait(timeout=5)
    except subprocess.TimeoutExpired:
        ssh.kill()
        ssh.wait()
    return runtime.returncode


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (ValueError, OSError, subprocess.CalledProcessError) as exc:
        print(f'Bootstrap failed: {exc}', file=sys.stderr)
        sys.exit(1)
