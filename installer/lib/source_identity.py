#!/usr/bin/env python3
import hashlib
import os
from pathlib import Path
import sys


def tree_sha(root):
    sha=hashlib.sha256()
    for base,dirs,names in os.walk(root):
        dirs.sort(); names.sort()
        for name in names:
            path=Path(base)/name
            sha.update(path.relative_to(root).as_posix().encode()+b'\0')
            if path.is_symlink(): sha.update(b'link\0'+os.readlink(path).encode())
            else:
                with path.open('rb') as f:
                    while chunk:=f.read(1024*1024): sha.update(chunk)
            sha.update(b'\0')
    return sha.hexdigest()

if __name__=='__main__': print(tree_sha(Path(sys.argv[1])))
