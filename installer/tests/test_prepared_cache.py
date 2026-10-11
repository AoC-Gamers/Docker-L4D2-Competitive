"""Ordered preparation cache: replay only validated candidate effects."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

LIB=Path(__file__).resolve().parents[1]/'lib'
sys.path.insert(0,str(LIB))
import prepared_cache as cache
from validate_stack import validate
import transaction_stack as tx

class PreparedCache(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name); self.candidate=self.root/'candidate'; self.candidate.mkdir()

    def write(self,rel,content):
        p=self.candidate/rel; p.parent.mkdir(parents=True,exist_ok=True); p.write_text(content); return p

    def test_delta_replays_replacement_and_deletion_without_unrelated_data(self):
        old=self.write('serverfiles/left4dead2/plugins/excluded.smx','previous layer')
        keep=self.write('serverfiles/left4dead2/plugins/community.smx','community')
        before=cache.inventory(self.candidate); old.unlink()
        payload=self.write('serverfiles/left4dead2/plugins/final.smx','normalized')
        record=self.root/'exclusions'; record.write_text('plugins/excluded.smx (removed)\n')
        entry=self.root/'cache'; cache.store(self.candidate,before,entry,record)
        self.assertFalse((entry/'files'/keep.relative_to(self.candidate)).exists())
        old.write_text('previous layer'); payload.unlink()
        self.assertTrue(cache.replay(self.candidate,entry))
        self.assertFalse(old.exists()); self.assertEqual(payload.read_text(),'normalized')
        self.assertEqual(keep.read_text(),'community')

    def test_corruption_validates_all_files_before_any_candidate_mutation(self):
        old=self.write('plugins/excluded.smx','old'); before=cache.inventory(self.candidate); old.unlink()
        payload=self.write('plugins/new.smx','new')
        entry=self.root/'cache'; cache.store(self.candidate,before,entry,self.root/'absent')
        (entry/'files/plugins/new.smx').write_text('bad bytes'); old.write_text('old'); payload.unlink()
        self.assertFalse(cache.replay(self.candidate,entry)); self.assertEqual(old.read_text(),'old')
        self.assertFalse(payload.exists())

    def test_candidate_input_mode_and_content_are_keyed_but_not_mtime(self):
        p=self.write('plugins/a.smx','a')
        args=(self.candidate,{'prepare_env':[]},{'commit':'one'},'logic','update')
        first=cache.key(*args); os.utime(p,None); self.assertEqual(first,cache.key(*args))
        p.chmod(0o755); self.assertNotEqual(first,cache.key(*args))
        p.write_text('b'); self.assertNotEqual(first,cache.key(*args))
        self.assertNotEqual(cache.key(*args),cache.key(self.candidate,{'prepare_env':[]},{'commit':'two'},'logic','update'))

    def test_invalid_cache_contract_and_direct_archive_rejected(self):
        hooks=self.root/'hooks'; hooks.mkdir(); (hooks/'demo.default.sh').write_text('#!/bin/bash\n')
        base={'folder':'demo','source_type':'git','repo_url':'https://example.invalid/repo'}
        for fields in ({'prepare_cache':'true'},{'prepare_env':['GITHUB_TOKEN']},{'prepare_env':'FLAVOR'},
                       {'source_type':'archive','url':'https://example.invalid/a.zip'},
                       {'prepare_downloads':[{'name':'../../escape','url':'https://example.invalid'}]}):
            with self.subTest(fields=fields),self.assertRaises(ValueError): validate([base|fields],hooks)

    def test_source_state_names_match_exactly(self):
        env=dict(os.environ,DIR_INSTALLER_LIB=str(LIB),CACHE_FILE=str(self.root/'cache.log'),CACHE_LOCK_FILE=str(self.root/'cache.lock'))
        result=subprocess.run(['bash','-c','''set -euo pipefail
source "$DIR_INSTALLER_LIB/tools_stack.sh"
source "$DIR_INSTALLER_LIB/install_stack_runtime.sh"
save_component_state sourcetv original
save_component_state lilac_sourcetv other
save_component_state sourcetv updated
test "$(get_component_cached_state sourcetv)" = updated
test "$(get_component_cached_state lilac_sourcetv)" = other
'''],env=env,capture_output=True,text=True)
        self.assertEqual(result.returncode,0,result.stderr)

    def test_uncommitted_transaction_payload_cannot_be_discarded(self):
        txdir=self.root/'transaction'; txdir.mkdir()
        (txdir/'journal.json').write_text('{"phase":"publishing"}')
        backup=txdir/'backup'; backup.mkdir(); (backup/'proof').write_text('old')
        with self.assertRaises(ValueError): tx.cleanup(txdir)
        self.assertEqual((backup/'proof').read_text(),'old')

    def test_replay_io_failure_is_fatal_instead_of_cache_miss(self):
        from unittest.mock import patch
        before=cache.inventory(self.candidate)
        self.write('plugins/new.smx','new')
        entry=self.root/'cache'; cache.store(self.candidate,before,entry,self.root/'absent')
        with patch.object(cache.shutil,'copy2',side_effect=OSError('simulated storage failure')):
            with self.assertRaises(OSError): cache.replay(self.candidate,entry)

    def test_commit_retains_pending_resume_until_it_is_acknowledged(self):
        txdir=self.root/'transaction'; txdir.mkdir()
        (txdir/'journal.json').write_text('{"phase":"published","entries":[]}')
        (txdir/'candidate').mkdir(); (txdir/'backup').mkdir()
        (txdir/'running-instances').write_text('l4d2server\n')
        tx.commit(txdir)
        self.assertTrue(json.loads((txdir/'journal.json').read_text())['resume_pending'])
        self.assertFalse((txdir/'backup').exists())
        self.assertEqual((txdir/'running-instances').read_text(),'l4d2server\n')
        tx.resumed(txdir)
        self.assertFalse(json.loads((txdir/'journal.json').read_text())['resume_pending'])
