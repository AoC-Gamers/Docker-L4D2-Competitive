#!/usr/bin/env python3
"""Recoverable file publication, not a multi-directory atomic replacement.

The write-ahead journal and backup live on the destination filesystem. Mutable
paths are never snapshotted. Each rename and phase update is flushed to disk.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import sys
import zipfile
from overlay_stack import safe_path, ROOTS

RESET = ['addons/sourcemod/'+s for s in ('extensions','gamedata','configs','plugins','scripting','translations')]


def durable_json(path, data):
    path.parent.mkdir(parents=True,exist_ok=True)
    tmp=path.with_suffix('.tmp')
    with tmp.open('w') as f:
        json.dump(data,f,sort_keys=True); f.write('\n'); f.flush(); os.fsync(f.fileno())
    os.replace(tmp,path); flush_dir(path.parent)


def flush_dir(path):
    fd=os.open(path,os.O_RDONLY | os.O_DIRECTORY)
    try: os.fsync(fd)
    finally: os.close(fd)


def files(root):
    result={}
    if root.exists():
        for base,dirs,names in os.walk(root,followlinks=False):
            for name in list(dirs):
                p=Path(base)/name
                if p.is_symlink():
                    raise ValueError(f'Symlink directory in candidate/managed tree: {p}')
            for name in names:
                p=Path(base)/name
                rel=p.relative_to(root).as_posix()
                safe_path(root,rel)
                if not p.is_file(): raise ValueError(f'Unsupported managed entry: {rel}')
                result[rel]=p
    return result


def preserved(stack, config):
    paths=['addons/sourcemod/logs','bansystem']
    for filename in (stack/'preserve-paths.json',config/'instances_exclude.json'):
        if filename.exists():
            for tree, entries in json.loads(filename.read_text()).items():
                for entry in entries:
                    rel=f'addons/sourcemod/{tree}/{entry}'
                    safe_path(Path('/unused'),rel)
                    paths.append(rel)
    # Databases, exports and runtime caches are always outside static publication.
    paths += ['addons/sourcemod/data/sqlite','addons/sourcemod/data/dumps',
              'addons/sourcemod/data/bansystem_chatlog','addons/sourcemod/data/clientprefs-sqlite.sq3']
    return paths


def under(rel, prefixes):
    return any(rel==p or rel.startswith(p+'/') for p in prefixes)


def seed(tx, root, state):
    candidate=tx/'candidate/serverfiles/left4dead2'; candidate.mkdir(parents=True,exist_ok=True)
    # Optional registries need their old owned bytes for safe retirement. No Valve copy.
    overlay=state/'optional-overlays'
    if overlay.exists():
        shutil.copytree(overlay,tx/'candidate/state/optional-overlays',dirs_exist_ok=True)
        for old in overlay.glob('*.paths'):
            label=old.stem.rstrip('_'); subtree=ROOTS.get(label)
            archive_name='whitelist_sound.zip' if label=='whitelist_sound' else 'fortnite_emotes.zip'
            archive=Path(os.environ.get('REPO_RESOURCES_DIR','/data/resources'))/archive_name
            if subtree and archive.is_file():
                with zipfile.ZipFile(archive) as zf:
                    for value in old.read_text().splitlines():
                        rel=subtree+'/'+value
                        if rel.startswith(('addons/sourcemod/data/','addons/sourcemod/logs/')): continue
                        src=safe_path(root,rel,subtree)
                        if rel in zf.namelist() and src.is_file() and src.read_bytes()==zf.read(rel):
                            dst=safe_path(candidate,rel,subtree); dst.parent.mkdir(parents=True,exist_ok=True); shutil.copy2(src,dst)
        for registry in overlay.glob('*.json'):
            data=json.loads(registry.read_text())
            if data.get('schema_version')!=2: raise ValueError('Unknown optional overlay state')
            for rel in data['files']:
                if rel.startswith(('addons/sourcemod/data/','addons/sourcemod/logs/')): continue
                src=safe_path(root,rel,data['subtree'])
                if src.is_file():
                    dst=safe_path(candidate,rel,data['subtree']); dst.parent.mkdir(parents=True,exist_ok=True); shutil.copy2(src,dst)


def plan(tx, root, stack, config, state):
    candidate=tx/'candidate/serverfiles/left4dead2'
    state.mkdir(parents=True,exist_ok=True)
    if root.stat().st_dev != state.stat().st_dev:
        raise ValueError('State and serverfiles must share a filesystem for recoverable renames')
    incoming=files(candidate)
    protect=preserved(stack,config)
    previous=set()
    retained=set()
    manifest=state/'managed-files.json'
    if manifest.exists(): previous.update(json.loads(manifest.read_text())['files'])
    # First upgrade removes only the previously documented reset subtrees.
    for rel in RESET:
        directory=root/rel
        if directory.exists():
            previous.update(rel+'/'+name for name in files(directory))
    overlay=state/'optional-overlays'
    if overlay.exists():
        for registry in overlay.glob('*.json'):
            data=json.loads(registry.read_text())
            for rel, sha in data.get('files',{}).items():
                path=safe_path(root,rel,data['subtree'])
                if path.is_file() and hashlib.sha256(path.read_bytes()).hexdigest()!=sha:
                    retained.add(rel)
                else:
                    previous.add(rel)
            retained.update(data.get('retained',[]))
    candidate_overlay=tx/'candidate/state/optional-overlays'
    if candidate_overlay.exists():
        for registry in candidate_overlay.glob('*.json'):
            retained.update(json.loads(registry.read_text()).get('retained',[]))
    for rel in retained:
        incoming.pop(rel,None); previous.discard(rel)
    policy=stack/'final-policy.json'
    if policy.exists(): previous.update(json.loads(policy.read_text()).get('remove',{}))
    # Explicit removals outside left4dead2 used by the AoC hook, deferred to publish.
    runtime_remove=tx/'candidate/runtime-removals.json'
    removals=json.loads(runtime_remove.read_text()) if runtime_remove.exists() else []
    entries=[]
    for rel in sorted(previous | set(incoming)):
        if under(rel,['addons/sourcemod/logs','bansystem']): continue
        if any(under(rel,[p]) and ((root/p).exists() or (root/p).is_symlink()) for p in protect): continue
        # Existing data is live; never follow or snapshot it, even through a link.
        if rel.startswith('addons/sourcemod/data/') and ((root/rel).exists() or (root/rel).is_symlink()): continue
        active=safe_path(root,rel)
        src=incoming.get(rel)
        if src is None and not active.exists(): continue
        if active.exists() and not active.is_file(): raise ValueError(f'Expected managed file: {rel}')
        if src and active.is_file() and hashlib.sha256(src.read_bytes()).digest()==hashlib.sha256(active.read_bytes()).digest(): continue
        entries.append({'area':'game','path':rel,'install':src is not None})
    for rel in removals:
        if rel not in ('bin/libstdc++.so.6','bin/dedicated/libstdc++.so.6','bin/libgcc_s.so.1','bin/dedicated/libgcc_s.so.1'): raise ValueError('Unmanaged runtime removal')
        active=safe_path(root.parent,rel)
        if active.is_file(): entries.append({'area':'serverfiles','path':rel,'install':False})
    # Registry and source metadata participate in the same recovery journal.
    new_state=tx/'candidate/state'
    baseline_file=tx/'config-default-hashes.json'
    baseline=json.loads(baseline_file.read_text()) if baseline_file.exists() else {}
    hashes={rel:baseline.get(rel) if rel.startswith(('cfg/','addons/sourcemod/configs/')) else hashlib.sha256(path.read_bytes()).hexdigest() for rel,path in incoming.items()}
    durable_json(new_state/'managed-files.json',{'schema_version':2,'files':sorted(incoming),'hashes':hashes})
    state_files=files(new_state)
    prior_state=set()
    if (state/'optional-overlays').exists():
        prior_state.update('optional-overlays/'+p for p in files(state/'optional-overlays'))
    for rel in sorted(set(state_files) | prior_state):
        safe_path(state,rel)
        entries.append({'area':'state','path':rel,'install':rel in state_files})
    journal={'schema_version':1,'phase':'prepared','target':str(root),'state':str(state),'entries':entries,'intent':None}
    durable_json(tx/'journal.json',journal)
    return journal


def area_root(journal,area):
    return Path(journal['state']) if area=='state' else (Path(journal['target']).parent if area=='serverfiles' else Path(journal['target']))


def recover(tx):
    journal_path=tx/'journal.json'
    if not journal_path.exists(): return
    j=json.loads(journal_path.read_text())
    if j['phase'] in ('committed','rolled_back','prepared'): return
    # Every entry is logged before a destructive rename. Recovery is idempotent.
    for e in reversed(j['entries']):
        if not e.get('pending'): continue
        dest=safe_path(area_root(j,e['area']),e['path'])
        backup=tx/'backup'/e['area']/e['path']
        if backup.exists():
            if dest.is_file(): dest.unlink()
            dest.parent.mkdir(parents=True,exist_ok=True)
            os.replace(backup,dest); flush_dir(dest.parent)
        elif not e['existed'] and dest.is_file():
            dest.unlink(); flush_dir(dest.parent)
        e['pending']=False
        durable_json(journal_path,j)
    j['phase']='rolled_back'; durable_json(journal_path,j)


def publish(tx):
    journal_path=tx/'journal.json'; j=json.loads(journal_path.read_text())
    if j['phase']!='prepared': raise ValueError('Transaction not prepared')
    j['phase']='publishing'; durable_json(journal_path,j)
    for index,e in enumerate(j['entries']):
        dest=safe_path(area_root(j,e['area']),e['path'])
        e['existed']=dest.exists(); e['pending']=True
        durable_json(journal_path,j)
        backup=tx/'backup'/e['area']/e['path']
        if e['existed']:
            backup.parent.mkdir(parents=True,exist_ok=True)
            os.replace(dest,backup); flush_dir(dest.parent); flush_dir(backup.parent)
        if e['install']:
            src=tx/'candidate'/('state' if e['area']=='state' else 'serverfiles/left4dead2')/e['path']
            dest.parent.mkdir(parents=True,exist_ok=True)
            # fsync source before making it live.
            with src.open('rb') as f: os.fsync(f.fileno())
            os.replace(src,dest); flush_dir(dest.parent)
        if os.environ.get('STACK_TEST_FAIL_PUBLISH_AFTER')==str(index): raise RuntimeError('Injected publication failure')
        if os.environ.get('STACK_TEST_KILL_PUBLISH_AFTER')==str(index): os.kill(os.getppid(),9); os._exit(137)
    j['phase']='published'; durable_json(journal_path,j)


def commit(tx):
    p=tx/'journal.json'; j=json.loads(p.read_text())
    if j['phase']!='published': raise ValueError('Cannot commit incomplete publication')
    j['phase']='committed'; durable_json(p,j)


if __name__=='__main__':
    action=sys.argv[1]; tx=Path(sys.argv[2])
    if action=='seed': seed(tx,Path(sys.argv[3]),Path(sys.argv[4]))
    elif action=='plan': plan(tx,*(Path(p) for p in sys.argv[3:7]))
    elif action=='publish': publish(tx)
    elif action=='recover': recover(tx)
    elif action=='commit': commit(tx)
    else: raise ValueError('Unknown transaction action')
