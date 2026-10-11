#!/usr/bin/env python3
"""Repair historical chmod-only damage without accepting modified Git content."""
import os
from pathlib import Path
import subprocess
import sys


def restore_modes(root):
    env = dict(os.environ, GIT_OPTIONAL_LOCKS='0')
    git = ['git', '-C', str(root)]
    if subprocess.run(git + ['-c', 'core.fileMode=false', 'diff', '--quiet', 'HEAD', '--'], env=env).returncode:
        return False
    if subprocess.check_output(git + ['ls-files', '--others', '--exclude-standard'], env=env):
        return False
    entries = subprocess.check_output(git + ['ls-tree', '-rz', 'HEAD'], env=env)
    for entry in entries.split(b'\0'):
        if not entry:
            continue
        meta, relative = entry.split(b'\t', 1)
        mode = meta.split()[0]
        path = root / os.fsdecode(relative)
        if mode not in (b'100644', b'100755') or path.is_symlink():
            continue
        # Do not follow a replaced parent directory into another tree.
        if any(parent.is_symlink() for parent in path.parents if parent != root and root in parent.parents):
            return False
        current = path.stat().st_mode & 0o777
        desired = current | 0o111 if mode == b'100755' else current & ~0o111
        if current != desired:
            path.chmod(desired)
    return subprocess.run(git + ['diff', '--quiet', 'HEAD', '--'], env=env).returncode == 0


if __name__ == '__main__':
    sys.exit(0 if restore_modes(Path(sys.argv[1])) else 1)
