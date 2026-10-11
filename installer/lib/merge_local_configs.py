#!/usr/bin/env python3
"""Keep local config edits; record template hashes rather than adopting local bytes."""
import hashlib
import json
from pathlib import Path
import shutil
import sys
from transaction_stack import files, durable_json

LOADERS={'cfg/sharedplugins.cfg','cfg/sharedplugins1.cfg'}


def merge(candidate,active,state,baseline_file):
    current=files(candidate)
    baseline={rel:hashlib.sha256(path.read_bytes()).hexdigest() for rel,path in current.items()}
    old_manifest=state/'managed-files.json'
    old=json.loads(old_manifest.read_text()).get('hashes',{}) if old_manifest.exists() else {}
    for tree in ('cfg','addons/sourcemod/configs'):
        for rel,path in files(active/tree).items():
            full=tree+'/'+rel
            if full in LOADERS: continue # Explicit stack-owned loaders must track the new artifact.
            actual=hashlib.sha256(path.read_bytes()).hexdigest()
            if old.get(full)!=actual:
                target=candidate/full; target.parent.mkdir(parents=True,exist_ok=True); shutil.copy2(path,target)
    durable_json(baseline_file,baseline)

if __name__=='__main__': merge(*(Path(p) for p in sys.argv[1:5]))
