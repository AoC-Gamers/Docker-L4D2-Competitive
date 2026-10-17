#!/usr/bin/env python3
"""Hash effective code/policy bytes; never hash mtime, logs or environment secrets."""
import hashlib
import json
import os
from pathlib import Path
import sys


def fingerprint(stack, lib, bin_dir, config, container):
    sha = hashlib.sha256()
    inputs = []
    for label, root, suffixes in [('hooks',stack/'hooks',{'.sh'}), ('lib',lib,{'.sh','.py'}),
                                  ('bin',bin_dir,{'.sh','.py'}),('config',config,{'.json'}),
                                  ('extensions',container/'extensions',{'.sh'})]:
        if root.exists():
            for path in sorted(root.rglob('*')):
                if path.is_file() and path.suffix in suffixes:
                    inputs.append((label+'/'+path.relative_to(root).as_posix(),path.read_bytes()))
    for name in ('preserve-paths.json','final-policy.json','extension-policy.json'):
        path=stack/name
        if path.is_file(): inputs.append((name,path.read_bytes()))
    # Values intentionally relevant to the composed tree, without tokens or paths.
    values={key:os.environ.get(key,'') for key in ('STV_STEAMWORKS_SDK_ARCHIVE',)}
    resources=Path(os.environ.get('REPO_RESOURCES_DIR','/data/resources'))
    for name in ('whitelist_sound.zip','fortnite_emotes.zip',os.environ.get('STV_STEAMWORKS_SDK_ARCHIVE','steamworks_sdk_155.zip')):
        path=resources/name
        if path.is_file(): inputs.append(('resource/'+name,hashlib.sha256(path.read_bytes()).digest()))
    inputs.append(('values',json.dumps(values,sort_keys=True).encode()))
    for label, content in sorted(inputs):
        sha.update(label.encode()+b'\0'+content+b'\0')
    return sha.hexdigest()


if __name__ == '__main__':
    print(fingerprint(*(Path(p) for p in sys.argv[1:6])))
