#!/usr/bin/env python3
"""Staged publication with explicit manual retry, without automatic backups.

The candidate survives an incomplete publication. Only each individual file
replacement is atomic; a multi-file publication can leave a mixed installation.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import sys
import zipfile
import uuid
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
        entries.append({'area':'game','path':rel,'install':src is not None})
    for rel in removals:
        if rel not in ('bin/libstdc++.so.6','bin/dedicated/libstdc++.so.6','bin/libgcc_s.so.1','bin/dedicated/libgcc_s.so.1'): raise ValueError('Unmanaged runtime removal')
        active=safe_path(root.parent,rel)
        if active.is_file(): entries.append({'area':'serverfiles','path':rel,'install':False})
    # Metadata is installed last; deployment ready is written only after commit.
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
    for entry in entries:
        if entry['install']:
            src=tx/'candidate'/('state' if entry['area']=='state' else 'serverfiles/left4dead2')/entry['path']
            entry['sha256']=hashlib.sha256(src.read_bytes()).hexdigest()
            entry['mode']=src.stat().st_mode & 0o777
            if entry['area']=='game' and entry['path'].startswith(('cfg/','addons/sourcemod/configs/')):
                active=safe_path(root,entry['path'])
                entry['previous_sha256']=hashlib.sha256(active.read_bytes()).hexdigest() if active.is_file() else None
    confirmed={name:json.loads((state/name).read_text()) if (state/name).exists() else None
               for name in ('source-lock.json','hook-assets.json')}
    deploy_state=state/'current/deploy-state.json'
    deployment_id=json.loads(deploy_state.read_text()).get('deployment_id') if deploy_state.is_file() else None
    finalizes_deploy_state=os.environ.get('STACK_PUBLICATION_FINALIZES_DEPLOY_STATE') == 'true'
    journal={'schema_version':2,'phase':'prepared','target':str(root),'state':str(state),'entries':entries,
             'confirmed_sources':confirmed,
             'deployment_id':deployment_id,
             'finalizes_deploy_state':finalizes_deploy_state,
             'logic_sha256':os.environ.get('STACK_PREPARATION_LOGIC_SHA','')}
    durable_json(tx/'journal.json',journal)
    return journal


def area_root(journal,area):
    return Path(journal['state']) if area=='state' else (Path(journal['target']).parent if area=='serverfiles' else Path(journal['target']))


def recover_legacy(tx):
    """One-time compatibility for interrupted v1 journals; no new backups."""
    journal_path=tx/'journal.json'
    if not journal_path.exists(): return
    j=json.loads(journal_path.read_text())
    if j.get('schema_version') != 1:
        raise ValueError('New publications have no rollback; retry explicitly instead')
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
    if j.get('schema_version') != 2 or j['phase'] not in ('prepared','publishing','published'):
        raise ValueError('Publication cannot be retried in this phase')
    # Validate the entire retained candidate before the first change, including
    # on retry. Publication copies, rather than consumes, this material.
    for e in j['entries']:
        if e['install']:
            src=safe_path(tx/'candidate'/('state' if e['area']=='state' else 'serverfiles/left4dead2'),e['path'])
            if hashlib.sha256(src.read_bytes()).hexdigest()!=e['sha256']:
                raise ValueError('Prepared candidate changed; rebuild it explicitly')
        safe_path(area_root(j,e['area']),e['path'])
        if 'previous_sha256' in e:
            dest=safe_path(area_root(j,e['area']),e['path'])
            if dest.is_file() and hashlib.sha256(dest.read_bytes()).hexdigest() not in (e['sha256'],e['previous_sha256']):
                raise ValueError('Local config changed after preparation; rebuild explicitly to preserve it')
    j['phase']='publishing'; durable_json(journal_path,j)
    progress_path=tx/'progress.json'
    if progress_path.exists():
        progress=json.loads(progress_path.read_text())
        temporary=progress.get('temporary')
        if temporary:
            index=progress['index']
            if not isinstance(index,int) or not 0 <= index < len(j['entries']):
                raise ValueError('Invalid publication progress index')
            if not temporary.startswith('.stack-publish-') or '/' in temporary:
                raise ValueError('Invalid publication temporary path')
            entry=j['entries'][index]
            dest=safe_path(area_root(j,entry['area']),entry['path'])
            leftover=safe_path(dest.parent,temporary)
            if leftover.exists(): leftover.unlink()
    for index,e in enumerate(j['entries']):
        dest=safe_path(area_root(j,e['area']),e['path'])
        if e['install']:
            src=tx/'candidate'/('state' if e['area']=='state' else 'serverfiles/left4dead2')/e['path']
            if dest.is_file() and dest.stat().st_mode & 0o777==e['mode'] and hashlib.sha256(dest.read_bytes()).hexdigest()==e['sha256']:
                continue
            dest.parent.mkdir(parents=True,exist_ok=True)
            temporary_name='.stack-publish-'+uuid.uuid4().hex
            durable_json(progress_path,{'index':index,'temporary':temporary_name})
            temporary=dest.parent/temporary_name
            try:
                with temporary.open('xb') as output, src.open('rb') as source:
                    shutil.copyfileobj(source,output)
                    output.flush(); os.fchmod(output.fileno(),e['mode']); os.fsync(output.fileno())
                os.replace(temporary,dest); flush_dir(dest.parent)
            finally:
                if temporary.exists(): temporary.unlink()
        elif dest.exists():
            dest.unlink(); flush_dir(dest.parent)
        durable_json(progress_path,{'completed':index+1})
        if os.environ.get('STACK_TEST_FAIL_PUBLISH_AFTER')==str(index): raise RuntimeError('Injected publication failure')
        if os.environ.get('STACK_TEST_KILL_PUBLISH_AFTER')==str(index): os.kill(os.getppid(),9); os._exit(137)
    j['phase']='published'; durable_json(journal_path,j)


def commit(tx):
    p=tx/'journal.json'; j=json.loads(p.read_text())
    if j['phase']!='published': raise ValueError('Cannot commit incomplete publication')
    j['phase']='committed'; j['resume_pending']=True; durable_json(p,j)
    cleanup(tx)


def resumed(tx):
    p=tx/'journal.json'; j=json.loads(p.read_text())
    j['resume_pending']=False; durable_json(p,j)


def quiescing(tx):
    p=tx/'journal.json'; j=json.loads(p.read_text())
    j['resume_pending']=True; durable_json(p,j)


def abandon(tx):
    """Explicit rebuild restores provenance only, never operational files."""
    path=tx/'journal.json'; j=json.loads(path.read_text())
    if j.get('schema_version')!=2 or j['phase']=='committed':
        raise ValueError('No new incomplete publication to abandon')
    # A partial state publication must not silently advance reuse-only sources.
    # These tiny provenance receipts are not backups of game/runtime data.
    for name,data in j['confirmed_sources'].items():
        if name not in ('source-lock.json','hook-assets.json'): raise ValueError('Invalid provenance receipt')
        destination=Path(j['state'])/name
        if data is None: destination.unlink(missing_ok=True)
        else: durable_json(destination,data)
    j['phase']='abandoned'; j['resume_pending']=True; durable_json(path,j)


def cleanup(tx):
    """Only a committed publication can discard its prepared payload."""
    journal = tx/'journal.json'
    if not journal.exists() or json.loads(journal.read_text())['phase'] != 'committed':
        raise ValueError('Refusing to discard an incomplete publication')
    for name in ('candidate', 'backup', 'sources'):
        path = tx/name
        if path.exists(): shutil.rmtree(path)
    for pattern in ('*.before.json', '*.exclusions'):
        for path in tx.glob(pattern): path.unlink()
    (tx/'progress.json').unlink(missing_ok=True)
    data=json.loads(journal.read_text())
    if data.get('schema_version')==2 and data.get('entries'):
        data['entry_count']=len(data['entries']); data['entries']=[]
        data.pop('confirmed_sources',None)
        durable_json(journal,data)
    flush_dir(tx)


def migrate(tx, root, state):
    """Move old receipts outside the game; never discard a pending v1 backup."""
    legacy=root.parent/'.stack-transaction'
    previous=root.parent/'.stack-transaction.last'
    for source in (legacy,previous):
        if not source.exists(): continue
        if source.is_symlink(): raise ValueError('Legacy transaction path is a symlink')
        journal=source/'journal.json'
        data=json.loads(journal.read_text()) if journal.exists() else {}
        if data and Path(data['target']).resolve()!=root.resolve():
            raise ValueError('Legacy journal belongs to a different destination')
        if source==previous and data.get('phase') in ('publishing','published'):
            raise ValueError('An older publication is incomplete; inspect it before migration')
        if data.get('phase')=='committed': cleanup(source)
        if source==legacy and not tx.exists():
            tx.parent.mkdir(parents=True,exist_ok=True)
            shutil.move(str(source),str(tx))
        else:
            if data.get('phase') in ('publishing','published'):
                raise ValueError('Conflicting incomplete publication journals')
            archive=state/'history/legacy-publications'/uuid.uuid4().hex
            archive.parent.mkdir(parents=True,exist_ok=True)
            shutil.move(str(source),str(archive))


if __name__=='__main__':
    action=sys.argv[1]; tx=Path(sys.argv[2])
    if action=='seed': seed(tx,Path(sys.argv[3]),Path(sys.argv[4]))
    elif action=='plan': plan(tx,*(Path(p) for p in sys.argv[3:7]))
    elif action=='publish': publish(tx)
    elif action=='recover-legacy': recover_legacy(tx)
    elif action=='migrate': migrate(tx,Path(sys.argv[3]),Path(sys.argv[4]))
    elif action=='commit': commit(tx)
    elif action=='cleanup': cleanup(tx)
    elif action=='resumed': resumed(tx)
    elif action=='quiescing': quiescing(tx)
    elif action=='abandon': abandon(tx)
    else: raise ValueError('Unknown transaction action')
