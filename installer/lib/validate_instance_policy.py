#!/usr/bin/env python3
"""Read-only check of final exclusions through each instance's effective plugin path."""
import json
from pathlib import Path
import re
import sys


def validate(sm,policy):
    if not policy.is_file(): return
    forbidden=[p.removeprefix('addons/sourcemod/') for p in json.loads(policy.read_text()).get('remove',{}) if p.startswith('addons/sourcemod/plugins/')]
    for instance in sm.parent.glob(sm.name+'*'):
        suffix=instance.name[len(sm.name):]
        if suffix and not re.fullmatch(r'[0-9]+',suffix): continue
        for rel in forbidden:
            if (instance/rel).exists() or (instance/rel).is_symlink(): raise ValueError(f'Excluded binary remains in effective instance: {instance.name}/{rel}')

if __name__=='__main__': validate(Path(sys.argv[1]),Path(sys.argv[2]))
