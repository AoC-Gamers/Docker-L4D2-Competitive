#!/usr/bin/env python3
import json
from pathlib import Path
import re
import sys


def validate(components, hooks):
    folders=set()
    for c in components:
        folder=c.get('folder',''); variant=c.get('hook_variant',c.get('branch','default'))
        for value in (folder,variant):
            if not isinstance(value,str) or not re.fullmatch(r'[A-Za-z0-9_][A-Za-z0-9_.-]*',value) or '..' in value:
                raise ValueError('Invalid component folder/hook variant')
        if folder in folders: raise ValueError('Duplicate component folder')
        folders.add(folder)
        kind=c.get('source_type','git')
        required=c.get('hook_required',True)
        if not isinstance(required,bool): raise ValueError('hook_required must be boolean')
        if not isinstance(c.get('prepare_cache',False),bool): raise ValueError('prepare_cache must be boolean')
        names=c.get('prepare_env',[])
        if not isinstance(names,list) or any(not isinstance(n,str) or not re.fullmatch(r'[A-Z_][A-Z_0-9]*',n) or re.search('TOKEN|SECRET|PASSWORD|PASSWD|KEY|CREDENTIAL',n) for n in names):
            raise ValueError('prepare_env must list non-secret environment variable names')
        if kind not in ('git','github_release','archive','hook_only'): raise ValueError('Unsupported source type')
        if kind=='git' and not c.get('repo_url'): raise ValueError('Missing Git repository')
        if kind=='github_release' and not (c.get('github_repo') and c.get('release_tag') and (c.get('asset_name') or c.get('asset_name_glob'))):
            raise ValueError('Incomplete GitHub release source')
        if kind=='archive' and not (c.get('url') and c.get('sha256')): raise ValueError('Direct archives require url and sha256')
        if kind=='archive' and not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._+-]*',c.get('archive_name','artifact.zip')): raise ValueError('Invalid archive name')
        downloads=c.get('prepare_downloads',[])
        if not isinstance(downloads,list) or (downloads and kind!='hook_only'): raise ValueError('prepare_downloads requires hook_only')
        for asset in downloads:
            if not isinstance(asset,dict) or not re.fullmatch(r'[A-Za-z0-9_][A-Za-z0-9_.-]*',asset.get('name','')) or not asset.get('url','').startswith('https://') or re.search(r'https?://[^/]*@|[?&](token|key|password)=',asset['url'],re.I):
                raise ValueError('Invalid declared hook download')
        if c.get('sha256') and not re.fullmatch('[a-f0-9]{64}',c['sha256']): raise ValueError('Invalid expected sha256')
        if required and not (hooks/f'{folder}.{variant}.sh').is_file(): raise ValueError(f'Required hook missing: {folder}.{variant}')
        # Tokens belong in environment variables, never in recorded source URLs.
        url=c.get('repo_url',c.get('url',''))
        if re.search(r'https?://[^/]*@',url) or '?' in url: raise ValueError('Credential/query-bearing source URLs are forbidden; use credential helpers')


if __name__=='__main__': validate(json.load(sys.stdin),Path(sys.argv[1]))
