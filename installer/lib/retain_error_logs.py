#!/usr/bin/env python3
"""Optional retention for dated SourceMod logs; dry-run unless --apply is given."""
import argparse
import datetime
import gzip
from pathlib import Path
import re
import shutil
import time


def retain(root, days=90, apply=False, now=None):
    if days < 3:
        raise ValueError('Retention must be at least three days')
    now = time.time() if now is None else now
    actions = []
    if root.is_symlink():
        raise ValueError('Log directory must not be a symlink')
    for path in sorted(root.iterdir()):
        match = re.fullmatch(r'errors_(\d{8})\.log(\.gz)?', path.name)
        if not match or path.is_symlink() or not path.is_file():
            continue
        try:
            day = datetime.datetime.strptime(match[1], '%Y%m%d').replace(tzinfo=datetime.timezone.utc).timestamp()
        except ValueError:
            continue
        # Both the filename date and last write must be old; never touch active logs.
        age = min(now - day, now - path.stat().st_mtime)
        if age < 2 * 86400:
            continue
        if age > days * 86400:
            actions.append(('remove', path.name))
            if apply:
                path.unlink()
        elif not match[2] and not path.with_suffix('.log.gz').exists():
            actions.append(('compress', path.name))
            if apply:
                target = path.with_suffix('.log.gz')
                temporary = target.with_suffix('.gz.pending')
                with path.open('rb') as source, temporary.open('xb') as output:
                    with gzip.GzipFile(fileobj=output, mode='wb', mtime=int(path.stat().st_mtime)) as compressed:
                        shutil.copyfileobj(source, compressed)
                shutil.copystat(path, temporary)
                temporary.replace(target)
                path.unlink()
    return actions


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    parser.add_argument('--days', type=int, default=90)
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    for action, filename in retain(args.directory, args.days, args.apply):
        print(action, filename)
