#!/usr/bin/env python3
import hashlib
import os
from pathlib import Path
import stat
import sys


def tree_sha(root, ignore_marker=False, ignore_git=False):
    sha=hashlib.sha256()
    for base,dirs,names in os.walk(root):
        if ignore_git:
            dirs[:]=[name for name in dirs if name != '.git']
            names=[name for name in names if name != '.git']
        dirs.sort(); names.sort()
        for name in names:
            if ignore_marker and name == ".stack-source.json": continue
            path=Path(base)/name
            sha.update(path.relative_to(root).as_posix().encode()+b'\0')
            if path.is_symlink(): sha.update(b'link\0'+os.readlink(path).encode())
            else:
                with path.open('rb') as f:
                    while chunk:=f.read(1024*1024): sha.update(chunk)
            sha.update(b'\0')
    return sha.hexdigest()


def archive_tree_sha(root):
    """Hash extracted archive filesystem semantics, excluding timestamps.

    Legacy source and pinned-snapshot identities intentionally keep their
    historical bytes-only format. Archive expansions need modes and directory
    entries because hooks can observe executable bits and empty directories.
    The domain prefix also makes every old expansion marker miss once so it is
    rebuilt from the already-verified original archive.
    """
    root = Path(root)
    sha = hashlib.sha256()
    sha.update(b'archive-filesystem-v1\0')

    def field(digest, value):
        digest.update(len(value).to_bytes(8, 'big'))
        digest.update(value)

    def entry_digest(relative, path):
        info = path.lstat()
        mode = stat.S_IMODE(info.st_mode)
        if stat.S_ISLNK(info.st_mode):
            kind, payload = b'link', os.readlink(path).encode()
        elif stat.S_ISDIR(info.st_mode):
            kind, payload = b'directory', b''
        elif stat.S_ISREG(info.st_mode):
            kind, payload = b'file', None
        else:
            kind, payload = b'special', b''

        entry = hashlib.sha256()
        field(entry, relative)
        field(entry, kind)
        field(entry, f'{mode:04o}'.encode())
        if payload is None:
            content = hashlib.sha256()
            size = 0
            with path.open('rb') as stream:
                while chunk := stream.read(1024 * 1024):
                    content.update(chunk)
                    size += len(chunk)
            field(entry, size.to_bytes(8, 'big'))
            field(entry, content.digest())
        else:
            field(entry, payload)
        return entry.digest(), info

    # cp -a expanded/. workspace/ carries the expansion root's mode too, so
    # include it as a filesystem entry instead of hashing only its children.
    root_entry, root_info = entry_digest(b'.', root)
    sha.update(root_entry)
    if not stat.S_ISDIR(root_info.st_mode):
        return sha.hexdigest()

    for base, dirs, names in os.walk(root, topdown=True, followlinks=False):
        dirs.sort()
        names.sort()
        entries = sorted([(name, True) for name in dirs] + [(name, False) for name in names])
        for name, is_dir_entry in entries:
            path = Path(base) / name
            relative = path.relative_to(root).as_posix().encode()
            entry, info = entry_digest(relative, path)
            sha.update(entry)

            # Do not recurse through a directory symlink even if a caller
            # supplies a tree that did not come from safe_extract.py.
            if is_dir_entry and stat.S_ISLNK(info.st_mode):
                dirs.remove(name)
    return sha.hexdigest()


if __name__ == '__main__':
    root = Path(sys.argv[1])
    option = sys.argv[2] if len(sys.argv) > 2 else ''
    if option == '--archive-tree-v1':
        print(archive_tree_sha(root))
    else:
        print(tree_sha(root, option == '--payload', option == '--git-payload'))
