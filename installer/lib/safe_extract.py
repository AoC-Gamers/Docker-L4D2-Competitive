#!/usr/bin/env python3
"""Reject traversal, links and special archive entries before any extraction."""
from pathlib import Path, PurePosixPath
import stat
import sys
import tarfile
import zipfile


def check(name):
    while name.startswith('./'): name=name[2:]
    if name in ('','.'): return
    if name.startswith('/') or '..' in PurePosixPath(name).parts or '\\' in name:
        raise ValueError('Unsafe archive member')


def extract(archive, destination, validate_only=False):
    if zipfile.is_zipfile(archive):
        with zipfile.ZipFile(archive) as zf:
            for item in zf.infolist():
                check(item.filename)
                if stat.S_ISLNK(item.external_attr >> 16): raise ValueError('Archive link refused')
            if not validate_only:
                destination.mkdir(parents=True,exist_ok=True); zf.extractall(destination)
    else:
        with tarfile.open(archive) as tf:
            for item in tf.getmembers():
                check(item.name)
                if not (item.isfile() or item.isdir()): raise ValueError('Archive links/special files refused')
            if not validate_only:
                destination.mkdir(parents=True,exist_ok=True); tf.extractall(destination)


if __name__=='__main__':
    extract(Path(sys.argv[1]),Path(sys.argv[2]),len(sys.argv)>3)
