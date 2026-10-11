#!/usr/bin/env python3
"""Every active global plugin load must exist in the fully composed candidate."""
from pathlib import Path
import re
import sys
from overlay_stack import safe_path


def validate(root):
    for name in ('sharedplugins.cfg','sharedplugins1.cfg'):
        cfg=root/'cfg'/name
        if not cfg.is_file(): continue
        for number,line in enumerate(cfg.read_text().splitlines(),1):
            command=line.split('//',1)[0].strip()
            match=re.fullmatch(r'sm\s+plugins\s+load\s+"?([^"\s;]+\.smx)"?\s*;?',command)
            if match:
                path=safe_path(root,'addons/sourcemod/plugins/'+match[1])
                if not path.is_file(): raise ValueError(f'Missing required composed plugin: {name}:{number}: {match[1]}')

if __name__=='__main__': validate(Path(sys.argv[1]))
