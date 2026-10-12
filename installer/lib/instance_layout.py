#!/usr/bin/env python3
"""Refresh shared links in place; private instance files never leave sourcemodN."""
import json
import os
from pathlib import Path
import shutil
import sys
import re

FOLDERS = ('bin', 'configs', 'data', 'extensions', 'gamedata', 'plugins', 'translations')


def exists(path):
    return path.exists() or path.is_symlink()


def validate_policy(policy):
    for folder, entries in policy.items():
        if folder not in FOLDERS or not isinstance(entries, list):
            raise ValueError('Invalid instance exclusion folder')
        for rel in entries:
            if not isinstance(rel, str) or not rel or rel.startswith('/') or any(p in ('', '.', '..') for p in rel.split('/')):
                raise ValueError('Invalid instance exclusion path')


def restore_private(source, destination):
    """Idempotent rename; a crash between unlink and rename leaves the source."""
    if not exists(source):
        return
    if source.is_symlink():
        raise ValueError(f'Unexpected private storage symlink: {source}')
    if destination.is_symlink():
        if destination.resolve() != source.resolve():
            raise ValueError(f'Conflicting private link: {destination}')
        destination.unlink()
    if exists(destination):
        raise ValueError(f'Conflicting physical private paths: {destination} and {source}')
    destination.parent.mkdir(parents=True, exist_ok=True)
    os.replace(source, destination)


def remove_links_only(root):
    if not exists(root):
        return
    if root.is_symlink():
        root.unlink()
        return
    for base, dirs, names in os.walk(root, followlinks=False):
        for name in names:
            if not (Path(base)/name).is_symlink():
                raise ValueError(f'Physical file in legacy layout; inspect before removal: {Path(base)/name}')
    shutil.rmtree(root)


def migrate(destination, policy):
    if destination.is_symlink():
        raise ValueError(f'Instance root cannot be a symlink: {destination}')
    previous=Path(str(destination)+'.previous')
    if not exists(destination) and previous.is_dir() and not previous.is_symlink():
        os.replace(previous, destination)
    stable=destination.parent/'.instance-data'/destination.name
    if stable.is_symlink() or stable.parent.is_symlink():
        raise ValueError('Legacy private storage cannot be a symlink')
    for folder in ('data', 'logs', 'configs'):
        restore_private(stable/folder, destination/folder)
    for folder, entries in policy.items():
        for rel in entries:
            source=stable/'overrides'/folder/rel
            if exists(source):
                reject_symlink_parents(source,stable)
                # No traversing a shared parent while migrating an override.
                parent=destination/folder
                if any(p.is_symlink() for p in (destination/folder/rel).parents if p==destination or destination in p.parents):
                    raise ValueError(f'Shared parent hides private override: {parent}')
                restore_private(source, destination/folder/rel)
    # Remove empty migration containers only. Unrecognized private files survive
    # with an actionable failure instead of being swept away by rmtree.
    if stable.exists():
        for base, dirs, names in os.walk(stable, topdown=False):
            directory=Path(base)
            if not any(directory.iterdir()): directory.rmdir()
        if stable.exists():
            raise ValueError(f'Unclassified legacy instance data retained: {stable}')
    container=stable.parent
    if container.exists() and not any(container.iterdir()): container.rmdir()
    remove_links_only(previous)
    remove_links_only(Path(str(destination)+'.next'))


def link(source, destination):
    if destination.is_symlink():
        if os.readlink(destination) == str(source): return
        destination.unlink()
    elif exists(destination):
        raise ValueError(f'Physical path cannot be replaced by a shared link: {destination}')
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.symlink_to(source, target_is_directory=source.is_dir())


def private_default(source, destination, empty=False):
    if exists(destination):
        # A declared private route must not continue pointing at the primary.
        if destination.is_symlink():
            raise ValueError(f'Private exclusion is still linked; migrate it explicitly: {destination}')
        return
    destination.parent.mkdir(parents=True, exist_ok=True)
    if empty:
        # Never clone a live private file from the primary. Its plugin creates
        # the per-instance file when needed; only private directories start empty.
        if source.is_file(): return
        destination.mkdir()
    elif not source.exists():
        return
    elif source.is_dir():
        shutil.copytree(source, destination, symlinks=True)
    else:
        shutil.copy2(source, destination)


def reject_symlink_parents(path, root):
    """Do not create an instance-private route through an unverified link."""
    parent=path.parent
    while parent != root:
        if root not in parent.parents:
            raise ValueError(f'Private path escapes instance root: {path}')
        if parent.is_symlink():
            raise ValueError(f'Private path has a symlink parent; inspect before retry: {parent}')
        parent=parent.parent


def refresh(source, destination, exclusions, relative='', mutable=False, empty_private=False, keep_local=False):
    if relative in exclusions:
        private_default(source, destination, empty=empty_private)
        return
    nested=any(p.startswith(relative+'/') for p in exclusions) if relative else bool(exclusions)
    # data is a physical per-instance directory; its existing files are live.
    # Existing physical configs/overrides also remain physical during refresh.
    physical=destination.is_dir() and not destination.is_symlink()
    if source.is_dir() and (nested or physical or mutable):
        if destination.is_symlink():
            if destination.resolve() != source.resolve():
                raise ValueError(f'Unverified symlink blocks private instance layout: {destination}')
            destination.unlink()
        destination.mkdir(parents=True, exist_ok=True)
        names={p.name for p in source.iterdir()}
        for p in list(destination.iterdir()):
            rel=relative+'/'+p.name if relative else p.name
            protected=rel in exclusions or any(e.startswith(rel+'/') for e in exclusions)
            if p.name in names or protected: continue
            if keep_local:
                # Only retire links owned by this shared layout. Foreign/local
                # data links and physical configuration remain untouched.
                if p.is_symlink() and os.readlink(p)==str(source/p.name): p.unlink()
            elif p.is_symlink() or p.is_file():
                p.unlink()
            else:
                shutil.rmtree(p)
        for child in sorted(source.iterdir()):
            rel=relative+'/'+child.name if relative else child.name
            target=destination/child.name
            if mutable and exists(target) and not target.is_symlink() and not any(p.startswith(rel+'/') for p in exclusions): continue
            refresh(child,target,exclusions,rel,mutable=False,empty_private=empty_private,keep_local=keep_local)
        # Private data paths exist even when the primary has no such directory.
        for rel in exclusions:
            if relative: continue
            target=destination/rel
            reject_symlink_parents(target,destination)
            if not exists(target):
                private_default(source/rel,target,empty=mutable)
        if not keep_local and not nested:
            # Collapse old physical shared copies back to the canonical link.
            remove_links_only(destination)
            link(source,destination)
    elif physical:
        if keep_local: return
        raise ValueError(f'Expected shared file, found physical directory: {destination}')
    elif exists(destination) and not destination.is_symlink():
        if keep_local: return
        # Non-private static files follow the primary, as the JSON contract says.
        destination.unlink()
        link(source,destination)
    else:
        link(source,destination)


def synchronize(source, destination, policy_file):
    policy=json.loads(policy_file.read_text()) if policy_file.exists() else {}
    validate_policy(policy)
    if source.is_symlink() or destination.is_symlink():
        raise ValueError('SourceMod roots must be physical directories')
    migrate(destination,policy)
    destination.mkdir(parents=True, exist_ok=True)
    logs=destination/'logs'
    if logs.is_symlink(): raise ValueError('Instance logs must not point to shared storage')
    logs.mkdir(exist_ok=True)
    for folder in FOLDERS:
        src=source/folder; dest=destination/folder
        if folder=='data' and dest.is_symlink():
            # Legacy fully shared data: keep the primary untouched, start a
            # physical container with links and empty explicitly private routes.
            if dest.resolve()!=src.resolve(): raise ValueError('Unknown instance data link')
            dest.unlink()
        if src.is_dir(): refresh(src,dest,policy.get(folder,[]),mutable=folder=='data',empty_private=folder=='data',keep_local=folder in ('data','configs'))


if __name__ == '__main__':
    if sys.argv[1]=='--migrate-all':
        source,policy_file=map(Path,sys.argv[2:4])
        if source.is_symlink() or not source.is_dir():
            raise ValueError(f'SourceMod root must be a physical directory: {source}')
        policy=json.loads(policy_file.read_text()) if policy_file.exists() else {}
        validate_policy(policy)
        container=source.parent/'.instance-data'
        if container.is_symlink(): raise ValueError('Legacy storage root cannot be a symlink')
        if container.is_dir():
            for child in sorted(container.iterdir()):
                if not re.fullmatch(re.escape(source.name)+r'[1-9][0-9]*',child.name):
                    raise ValueError(f'Unknown legacy instance data retained: {child}')
                migrate(source.parent/child.name,policy)
    else:
        synchronize(*(Path(p) for p in sys.argv[1:4]))
