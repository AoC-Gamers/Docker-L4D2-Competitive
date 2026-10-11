#!/usr/bin/env python3
"""Cache declared deterministic hook effects, never the active installation.

Keys include the ordered candidate input. Deltas preserve layering/deletions;
only candidate files are replayed. Unknown/stateful hooks remain uncached.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile
from overlay_stack import safe_path
from transaction_stack import files, durable_json


def file_sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def inventory(root):
    return {rel: {'sha256': file_sha(p),
                  'mode': p.stat().st_mode & 0o777}
            for rel, p in sorted(files(root).items()) if rel != 'state/source-lock.json'}


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def key(root, component, source, logic, mode):
    return digest({'schema': 1, 'component': component, 'source': source,
                   'logic': logic, 'mode': mode, 'profile': os.environ.get('STACK_PROFILE',''), 'input': inventory(root),
                   'env': {name: os.environ.get(name, '') for name in component.get('prepare_env', [])}})


def store(root, before, destination, exclusions):
    after = inventory(root)
    changed = {p: info for p, info in after.items() if before.get(p) != info}
    removed = sorted(before.keys() - after.keys())
    destination.parent.mkdir(parents=True, exist_ok=True)
    temp = Path(tempfile.mkdtemp(prefix='.pending-', dir=destination.parent))
    try:
        for rel in changed:
            dst = safe_path(temp/'files', rel); dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(safe_path(root, rel), dst)
        manifest = {'schema': 1, 'changed': changed, 'removed': removed,
                    'exclusions': exclusions.read_text().splitlines() if exclusions.exists() else []}
        # Manifest written last; incomplete directories can never be cache hits.
        durable_json(temp/'manifest.json', manifest)
        if destination.exists(): shutil.rmtree(destination)
        os.replace(temp, destination)
    finally:
        if temp.exists(): shutil.rmtree(temp)


def replay(root, entry):
    try:
        data = json.loads((entry/'manifest.json').read_text())
        if data['schema'] != 1: return False
        # Validate everything before applying any effect.
        for rel in data['removed']:
            safe_path(root, rel)
        for rel, info in data['changed'].items():
            path = safe_path(entry/'files', rel)
            safe_path(root, rel)
            if not path.is_file() or file_sha(path) != info['sha256']:
                return False
    except (OSError, ValueError, KeyError, TypeError):
        return False
    # After validation, an I/O failure is fatal to preparation. Never classify a
    # partially replayed delta as a cache miss and continue from a mixed input.
    for rel in data['removed']:
        path = safe_path(root, rel)
        if path.is_file(): path.unlink()
    for rel, info in data['changed'].items():
        path = safe_path(root, rel); path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(safe_path(entry/'files', rel), path); path.chmod(info['mode'])
    for line in data['exclusions']:
        print('Excluded path from deployment: '+line+' [prepared cache]')
    return True


if __name__ == '__main__':
    action, root = sys.argv[1], Path(sys.argv[2])
    if action == 'key':
        print(key(root, json.loads(sys.argv[3]), json.loads(sys.argv[4]), sys.argv[5], sys.argv[6]))
    elif action == 'inventory':
        Path(sys.argv[3]).write_text(json.dumps(inventory(root), sort_keys=True))
    elif action == 'store':
        store(root, json.loads(Path(sys.argv[3]).read_text()), Path(sys.argv[4]), Path(sys.argv[5]))
    elif action == 'replay':
        try:
            sys.exit(0 if replay(root, Path(sys.argv[3])) else 1)
        except Exception as error:
            print(f'Prepared cache replay failed: {error}', file=sys.stderr)
            sys.exit(2)
