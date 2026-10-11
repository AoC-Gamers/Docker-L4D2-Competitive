import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest

LIB=Path(__file__).resolve().parents[1]/'lib'
sys.path.insert(0,str(LIB))
import transaction_stack as tx
from materialization import fingerprint

class Transactions(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.base=Path(self.temp.name); self.root=self.base/'serverfiles/left4dead2'; self.root.mkdir(parents=True)
        self.transaction=self.root.parent/'.stack-transaction'
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

    def test_live_data_no_snapshot_and_publish_rollback(self):
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
        tx.recover(self.transaction); tx.recover(self.transaction)
        self.assertEqual(old.read_text(),'old')
        self.assertFalse((self.root/'addons/sourcemod/plugins/new.smx').exists())
        self.assertEqual(hostname.read_text(),'local'); self.assertEqual(db.read_text(),'live'); self.assertEqual(log.read_text(),'evidence')
        self.assertFalse(any((self.transaction/'backup').rglob('*.sq3')))

    def test_success_equivalence_clean_and_update(self):
        self.write(self.root,'addons/sourcemod/plugins/stale.smx','stale')
        self.prepare(); tx.publish(self.transaction); tx.commit(self.transaction)
        plugins=self.root/'addons/sourcemod/plugins'
        self.assertEqual(sorted(p.name for p in plugins.iterdir()),['new.smx'])
        clean=self.base/'clean/left4dead2'; clean.mkdir(parents=True)
        clean_tx=self.base/'clean/.stack-transaction'
        tx.seed(clean_tx,clean,self.state)
        self.write(clean_tx/'candidate/serverfiles/left4dead2','addons/sourcemod/plugins/new.smx','new')
        tx.plan(clean_tx,clean,self.stack,self.config,self.base/'clean-state'); tx.publish(clean_tx); tx.commit(clean_tx)
        self.assertEqual({p.name:p.read_bytes() for p in plugins.iterdir()}, {p.name:p.read_bytes() for p in (clean/'addons/sourcemod/plugins').iterdir()})

    def test_sigkill_recovery(self):
        old=self.write(self.root,'addons/sourcemod/plugins/old.smx','old')
        self.prepare()
        code='import sys,os; from pathlib import Path; sys.path.insert(0,sys.argv[1]); import transaction_stack as t; t.publish(Path(sys.argv[2]))'
        # Kill the publisher itself after its durable rename, bypassing all Bash traps.
        code=code.replace('t.publish(Path(sys.argv[2]))', 'original=t.flush_dir\ndef kill_after(p):\n original(p)\n if str(p).endswith("plugins") and any((Path(sys.argv[2])/"backup").rglob("*.smx")): os.kill(os.getpid(),9)\nt.flush_dir=kill_after\nt.publish(Path(sys.argv[2]))')
        result=subprocess.run(['python3','-c',code,str(LIB),str(self.transaction)])
        self.assertEqual(result.returncode,-9)
        tx.recover(self.transaction); self.assertEqual(old.read_text(),'old')
        self.assertEqual(json.loads((self.transaction/'journal.json').read_text())['phase'],'rolled_back')

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
