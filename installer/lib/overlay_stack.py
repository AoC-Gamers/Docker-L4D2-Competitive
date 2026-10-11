#!/usr/bin/env python3
"""Versioned optional overlays. Paths are relative to left4dead2, never to a ZIP."""
import hashlib
import json
from pathlib import Path, PurePosixPath
import shutil
import stat
import sys
import zipfile

ROOTS = {"whitelist_sound": "sound", "fortnite_emotes_sound": "sound",
         "fortnite_emotes_models": "models", "fortnite_emotes_addons": "addons"}


def safe_path(root, value, subtree=None):
    parts = PurePosixPath(value).parts
    if not parts or value.startswith('/') or any(p in ('..', '.') for p in value.split('/')) or '\\' in value:
        raise ValueError(f"Unsafe overlay path: {value!r}")
    if subtree and (parts[0] != subtree or len(parts) < 2):
        raise ValueError(f"Path outside overlay subtree: {value!r}")
    path = root
    for part in parts:
        path = path / part
        if path.is_symlink():
            raise ValueError(f"Symlink in managed path: {value!r}")
    return path


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def deploy(archive, extract, subtree, root, label, state_dir):
    if subtree not in ('sound', 'models', 'addons'):
        raise ValueError('Invalid overlay subtree')
    state_dir.mkdir(parents=True, exist_ok=True)
    state = state_dir / (label + '.json')
    # Older Bash tr appended an underscore for the newline. Accept both spellings.
    legacy = [state_dir / (label + s) for s in ('_.paths', '.paths')]
    incoming = {}
    if archive.is_file():
        if extract.exists():
            shutil.rmtree(extract)
        extract.mkdir(parents=True)
        with zipfile.ZipFile(archive) as zf:
            for item in zf.infolist():
                name = item.filename.rstrip('/')
                safe_path(extract, name)
                if stat.S_ISLNK(item.external_attr >> 16):
                    raise ValueError('Symlink in optional archive')
            zf.extractall(extract)
        source = extract / subtree
        if source.is_dir():
            for path in sorted(source.rglob('*')):
                if path.is_file():
                    rel = path.relative_to(extract).as_posix()
                    safe_path(root, rel, subtree)
                    incoming[rel] = digest(path)
    previous = {}
    retained = []
    if state.exists():
        data = json.loads(state.read_text())
        if data.get('schema_version') != 2 or data.get('subtree') != subtree:
            raise ValueError('Unknown overlay registry format/subtree')
        previous = data['files']
        retained = data.get('retained', [])
    for old in legacy:
        if not old.exists():
            continue
        unresolved = []
        for value in old.read_text().splitlines():
            # A label maps to exactly one subtree, but ownership still needs bytes.
            rel = subtree + '/' + value
            path = safe_path(root, rel, subtree)
            if ROOTS.get(label) == subtree and rel in incoming and path.is_file() and digest(path) == incoming[rel]:
                previous[rel] = incoming[rel]
            else:
                unresolved.append(value)
        if unresolved:
            print(f'Legacy overlay {label}: retained {len(unresolved)} unverified paths; see {old}.unresolved', file=sys.stderr)
            old.with_suffix('.paths.unresolved').write_text('\n'.join(unresolved) + '\n')
        old.rename(old.with_suffix('.paths.migrated'))
    # Validate the complete registry before any deletion.
    for rel in previous:
        safe_path(root, rel, subtree)
    for rel, sha in previous.items():
        path = safe_path(root, rel, subtree)
        if path.is_file() and digest(path) != sha:
            retained.append(rel)
        if path.is_file() and digest(path) == sha:
            path.unlink()
            parent = path.parent
            while parent != root / subtree:
                try:
                    parent.rmdir()
                except OSError:
                    break
                parent = parent.parent
    for rel, sha in incoming.items():
        path = safe_path(root, rel, subtree)
        if path.exists() and (rel not in previous or digest(path) != previous[rel]):
            if not path.is_file() or digest(path) != sha:
                raise ValueError(f'Optional overlay conflicts with unowned/modified file: {rel}')
        path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(extract / rel, path)
    tmp = state.with_suffix('.tmp')
    tmp.write_text(json.dumps({'schema_version': 2, 'subtree': subtree, 'files': incoming, 'retained': sorted(set(retained)-set(incoming))}, sort_keys=True) + '\n')
    tmp.replace(state)


if __name__ == '__main__':
    deploy(Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3], Path(sys.argv[4]), sys.argv[5], Path(sys.argv[6]))
