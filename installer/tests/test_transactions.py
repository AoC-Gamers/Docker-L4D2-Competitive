import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

LIB=Path(__file__).resolve().parents[1]/'lib'
sys.path.insert(0,str(LIB))
import transaction_stack as tx
from materialization import fingerprint

class Transactions(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.base=Path(self.temp.name); self.root=self.base/'serverfiles/left4dead2'; self.root.mkdir(parents=True)
        self.transaction=self.base/'state/publication/test'
        self.stack=self.base/'stack'; self.stack.mkdir()
        self.config=self.base/'config'; self.config.mkdir()
        self.state=self.base/'state'; self.state.mkdir()
        (self.stack/'preserve-paths.json').write_text(json.dumps({'configs':['hostname.cfg'],'data':['sqlite','dumps']}))
        (self.config/'instances_exclude.json').write_text(json.dumps({'data':['bansystem_chatlog']}))

    def write(self,root,rel,text):
        p=root/rel; p.parent.mkdir(parents=True,exist_ok=True); p.write_text(text); return p

    def prepare(self):
        tx.seed(self.transaction,self.root,self.state)
        c=self.transaction/'candidate/serverfiles/left4dead2'
        self.write(c,'addons/sourcemod/plugins/new.smx','new')
        self.write(c,'addons/sourcemod/configs/hostname.cfg','default')
        self.write(c,'addons/sourcemod/data/sqlite/db.sq3','invalid default')
        tx.plan(self.transaction,self.root,self.stack,self.config,self.state)
        return c

    def test_live_data_preserved_failed_publication_keeps_candidate_without_backup(self):
        old=self.write(self.root,'addons/sourcemod/plugins/old.smx','old')
        hostname=self.write(self.root,'addons/sourcemod/configs/hostname.cfg','local')
        db=self.write(self.root,'addons/sourcemod/data/sqlite/db.sq3','live')
        log=self.write(self.root,'addons/sourcemod/logs/errors_1.log','evidence')
        c=self.prepare(); self.assertEqual(old.read_text(),'old')
        self.assertFalse((c/'addons/sourcemod/data/sqlite/db.sq3').read_text()=='live')
        os.environ['STACK_TEST_FAIL_PUBLISH_AFTER']='0'
        try:
            with self.assertRaises(RuntimeError): tx.publish(self.transaction)
        finally: os.environ.pop('STACK_TEST_FAIL_PUBLISH_AFTER')
        self.assertEqual(json.loads((self.transaction/'journal.json').read_text())['phase'],'publishing')
        self.assertTrue((c/'addons/sourcemod/plugins/new.smx').is_file())
        self.assertFalse((self.transaction/'backup').exists())
        # The first entry was published; it is deliberately not rolled back.
        self.assertTrue((self.root/'addons/sourcemod/plugins/new.smx').exists())
        tx.publish(self.transaction); tx.commit(self.transaction)
        self.assertFalse(old.exists())
        self.assertEqual(hostname.read_text(),'local'); self.assertEqual(db.read_text(),'live'); self.assertEqual(log.read_text(),'evidence')
        self.assertFalse(any((self.transaction/'backup').rglob('*.sq3')))

    def test_success_equivalence_clean_and_update(self):
        self.write(self.root,'addons/sourcemod/plugins/stale.smx','stale')
        self.prepare(); tx.publish(self.transaction); tx.commit(self.transaction)
        self.assertEqual((self.root/'addons/sourcemod/configs/hostname.cfg').read_text(),'default')
        plugins=self.root/'addons/sourcemod/plugins'
        self.assertEqual(sorted(p.name for p in plugins.iterdir()),['new.smx'])
        clean=self.base/'clean/left4dead2'; clean.mkdir(parents=True)
        clean_tx=self.base/'clean-state/publication/test'
        tx.seed(clean_tx,clean,self.state)
        self.write(clean_tx/'candidate/serverfiles/left4dead2','addons/sourcemod/plugins/new.smx','new')
        tx.plan(clean_tx,clean,self.stack,self.config,self.base/'clean-state'); tx.publish(clean_tx); tx.commit(clean_tx)
        self.assertEqual({p.name:p.read_bytes() for p in plugins.iterdir()}, {p.name:p.read_bytes() for p in (clean/'addons/sourcemod/plugins').iterdir()})

    def test_retired_component_binary_is_removed_and_live_data_survives_repeated_updates(self):
        retired='addons/sourcemod/plugins/anticheat/retired.smx'
        binary=self.write(self.root,retired,'retired component')
        data=self.write(self.root,'addons/sourcemod/data/sqlite/retired.sq3','live data')
        self.write(self.state,'managed-files.json',json.dumps({'files':[retired]}))
        for _ in range(2):
            self.prepare()
            tx.publish(self.transaction); tx.commit(self.transaction)
            self.assertFalse(binary.exists())
            self.assertEqual(data.read_text(),'live data')
            self.assertTrue((self.root/'addons/sourcemod/plugins/new.smx').is_file())
            self.assertNotIn(retired,json.loads((self.state/'managed-files.json').read_text())['files'])
            tx.cleanup(self.transaction)

    def test_sigkill_retains_candidate_for_explicit_retry(self):
        old=self.write(self.root,'addons/sourcemod/plugins/old.smx','old')
        self.prepare()
        code='import sys,os; from pathlib import Path; sys.path.insert(0,sys.argv[1]); import transaction_stack as t; t.publish(Path(sys.argv[2]))'
        # Kill after an actual file replacement, bypassing all Bash traps.
        code=code.replace('t.publish(Path(sys.argv[2]))', 'original=t.flush_dir\ndef kill_after(p):\n original(p)\n if str(p).endswith("plugins"): os.kill(os.getpid(),9)\nt.flush_dir=kill_after\nt.publish(Path(sys.argv[2]))')
        result=subprocess.run(['python3','-c',code,str(LIB),str(self.transaction)])
        self.assertEqual(result.returncode,-9)
        self.assertEqual(json.loads((self.transaction/'journal.json').read_text())['phase'],'publishing')
        self.assertFalse((self.transaction/'backup').exists())
        tx.publish(self.transaction); tx.commit(self.transaction)
        self.assertFalse(old.exists())
        self.assertEqual((self.root/'addons/sourcemod/plugins/new.smx').read_text(),'new')

    def test_copy_error_does_not_truncate_live_file_and_retry_reuses_candidate(self):
        active=self.write(self.root,'addons/sourcemod/plugins/new.smx','old bytes')
        self.prepare()
        def fail(source,destination):
            destination.write(b'partial')
            raise OSError('simulated full disk')
        with patch.object(tx.shutil,'copyfileobj',fail), self.assertRaises(OSError):
            tx.publish(self.transaction)
        self.assertEqual(active.read_text(),'old bytes')
        self.assertEqual(list(active.parent.glob('.stack-publish-*')),[])
        tx.publish(self.transaction); tx.commit(self.transaction)
        self.assertEqual(active.read_text(),'new')

    def test_modified_candidate_is_rejected_before_first_publish(self):
        old=self.write(self.root,'addons/sourcemod/plugins/old.smx','old')
        candidate=self.prepare()
        (candidate/'addons/sourcemod/plugins/new.smx').write_text('changed after validation')
        with self.assertRaisesRegex(ValueError,'candidate changed'): tx.publish(self.transaction)
        self.assertEqual(old.read_text(),'old')

    def test_manual_config_edit_after_preparation_is_not_overwritten_on_retry(self):
        old=self.write(self.root,'addons/sourcemod/plugins/old.smx','old')
        config=self.write(self.root,'cfg/local.cfg','previous settings')
        candidate=self.prepare()
        self.write(candidate,'cfg/local.cfg','previous settings')
        tx.plan(self.transaction,self.root,self.stack,self.config,self.state)
        config.write_text('operator repaired settings')
        with self.assertRaisesRegex(ValueError,'Local config changed'): tx.publish(self.transaction)
        self.assertEqual(config.read_text(),'operator repaired settings')
        self.assertEqual(old.read_text(),'old')

    def test_committed_legacy_receipts_move_outside_game_and_pending_backup_survives(self):
        legacy=self.root.parent/'.stack-transaction'
        previous=self.root.parent/'.stack-transaction.last'
        for path in (legacy,previous):
            self.write(path,'journal.json',json.dumps({'schema_version':1,'target':str(self.root),'phase':'committed','entries':[]}))
            self.write(path,'backup/old.smx','old')
        tx.migrate(self.transaction,self.root,self.state)
        self.assertFalse(legacy.exists()); self.assertFalse(previous.exists())
        self.assertFalse((self.transaction/'backup').exists())
        self.assertEqual(len(list((self.state/'history/legacy-publications').iterdir())),1)
        import shutil
        shutil.rmtree(self.transaction)
        self.write(legacy,'journal.json',json.dumps({'schema_version':1,'target':str(self.root),'phase':'publishing','entries':[]}))
        self.write(legacy,'backup/old.smx','keep recovery evidence')
        tx.migrate(self.transaction,self.root,self.state)
        self.assertEqual((self.transaction/'backup/old.smx').read_text(),'keep recovery evidence')

    def test_legacy_rollback_only_for_old_interrupted_journal(self):
        active=self.write(self.root,'addons/sourcemod/plugins/new.smx','new')
        self.write(self.transaction,'backup/game/addons/sourcemod/plugins/new.smx','old')
        self.write(self.transaction,'journal.json',json.dumps({'schema_version':1,'phase':'publishing','target':str(self.root),'state':str(self.state),'entries':[{'area':'game','path':'addons/sourcemod/plugins/new.smx','pending':True,'existed':True}]}))
        tx.recover_legacy(self.transaction); tx.recover_legacy(self.transaction)
        self.assertEqual(active.read_text(),'old')

    def test_symlink_refused_before_publish(self):
        outside=self.base/'outside'; outside.mkdir()
        (self.root/'addons').symlink_to(outside)
        with self.assertRaises(ValueError): self.prepare()
        self.assertFalse(any(outside.iterdir()))

    def test_fingerprint_code_policy_not_mtime_log(self):
        lib=self.base/'lib'; lib.mkdir(); script=self.write(lib,'x.sh','one')
        args=(self.stack,lib,self.base/'bin',self.config,self.base/'container')
        one=fingerprint(*args); os.utime(script,None); self.write(lib,'errors.log','noise')
        self.assertEqual(one,fingerprint(*args))
        script.write_text('two'); self.assertNotEqual(one,fingerprint(*args))
        two=fingerprint(*args); self.write(self.stack,'final-policy.json','{}'); self.assertNotEqual(two,fingerprint(*args))

    def test_destination_lock_nested_and_parallel(self):
        env=dict(os.environ,LIB=str(LIB),STACK_LOCK_ROOT=str(self.base/'locks'))
        code='source "$LIB/target_lock.sh"; stack_acquire_target_lock; echo acquired; sleep 0.5'
        def launch(dest):
            e=dict(env,DIR_LEFT4DEAD2=str(dest)); return subprocess.Popen(['bash','-c',code],env=e,stdout=subprocess.PIPE,text=True)
        a=launch(self.root); self.addCleanup(lambda:a.poll() is None and a.kill()); self.assertEqual(a.stdout.readline().strip(),'acquired')
        b=launch(self.root); c=launch(self.base/'independent')
        start=time.monotonic(); self.assertEqual(c.stdout.readline().strip(),'acquired'); self.assertLess(time.monotonic()-start,.4)
        self.assertEqual(b.stdout.readline().strip(),'acquired'); self.assertGreater(time.monotonic()-start,.35)
        for p in (a,b,c): p.wait(); p.stdout.close()
        nested='source "$LIB/target_lock.sh"; stack_acquire_target_lock; bash -c \'source "$LIB/target_lock.sh"; stack_acquire_target_lock\''
        subprocess.run(['bash','-c',nested],env=dict(env,DIR_LEFT4DEAD2=str(self.root)),check=True,timeout=2)

    def test_modified_optional_resource_survives_subsequent_publications(self):
        resource=self.write(self.root,'sound/aoc/probe.wav','local modification')
        import hashlib
        self.write(self.state,'optional-overlays/whitelist_sound.json',json.dumps({'schema_version':2,'subtree':'sound','files':{'sound/aoc/probe.wav':hashlib.sha256(b'original').hexdigest()}}))
        self.write(self.state,'managed-files.json',json.dumps({'files':['sound/aoc/probe.wav']}))
        tx.seed(self.transaction,self.root,self.state)
        from overlay_stack import deploy
        deploy(self.base/'absent.zip',self.base/'extract','sound',self.transaction/'candidate/serverfiles/left4dead2','whitelist_sound',self.transaction/'candidate/state/optional-overlays')
        tx.plan(self.transaction,self.root,self.stack,self.config,self.state); tx.publish(self.transaction); tx.commit(self.transaction)
        self.assertEqual(resource.read_text(),'local modification')
        import shutil
        shutil.rmtree(self.transaction)
        tx.seed(self.transaction,self.root,self.state)
        deploy(self.base/'absent.zip',self.base/'extract','sound',self.transaction/'candidate/serverfiles/left4dead2','whitelist_sound',self.transaction/'candidate/state/optional-overlays')
        tx.plan(self.transaction,self.root,self.stack,self.config,self.state); tx.publish(self.transaction); tx.commit(self.transaction)
        self.assertEqual(resource.read_text(),'local modification')
