"""Real Bash entry point, local Git component, no Valve/Docker/private credentials."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

INSTALLER=Path(__file__).resolve().parents[1]

class InstallerFlow(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.base=Path(self.temp.name); self.game=self.base/'serverfiles/left4dead2'; self.game.mkdir(parents=True)
        self.installer=self.base/'installer'; shutil.copytree(INSTALLER,self.installer)
        self.stack=self.base/'stack'; (self.stack/'hooks').mkdir(parents=True); (self.stack/'profiles').mkdir(); (self.stack/'manifests').mkdir()
        (self.stack/'preserve-paths.json').write_text('{"configs":["hostname.cfg"],"data":["sqlite"]}')
        (self.installer/'config/instances_exclude.json').write_text('{"data":["dumps"]}')
        self.app=self.base/'app'; self.app.mkdir(); self.mock=self.base/'mock'; self.mock.mkdir()
        (self.mock/'tmux').write_text('#!/bin/bash\nexit 1\n'); (self.mock/'tmux').chmod(0o755)
        (self.installer/'bin/geoip_update.sh').write_text('#!/bin/bash\nexit 0\n')
        self.source=self.base/'source'; self.source.mkdir()
        subprocess.run(['git','init','-q',str(self.source)],check=True)
        (self.source/'plugin').write_text('version1')
        subprocess.run(['git','-C',str(self.source),'add','.'],check=True)
        subprocess.run(['git','-C',str(self.source),'-c','user.name=Test','-c','user.email=test@example.invalid','commit','-qm','fixture'],check=True)
        self.hook=self.stack/'hooks/demo.default.sh'
        self.hook.write_text('''#!/bin/bash
set -euo pipefail
mkdir -p "$DIR_SOURCEMOD/plugins" "$DIR_SOURCEMOD/data/sqlite"
cp "$1/plugin" "$DIR_SOURCEMOD/plugins/demo.smx"
printf default > "$DIR_SOURCEMOD/data/sqlite/local.sq3"
''')
        (self.installer/'bin/sync_instances.sh').write_text('#!/bin/bash\nexit 0\n')
        (self.stack/'manifests/components.json').write_text(json.dumps({'demo':{'folder':'demo','source_type':'git','repo_url':str(self.source),'branch':'default'}}))
        (self.stack/'profiles/test.json').write_text('{"components":["demo"]}')
        self.env=dict(os.environ,PATH=str(self.mock)+':'+os.environ['PATH'],USER=os.environ['USER'],DIR_INSTALLER=str(self.installer),DIR_INSTALLER_BIN=str(self.installer/'bin'),DIR_INSTALLER_LIB=str(self.installer/'lib'),DIR_INSTALLER_CONFIG=str(self.installer/'config'),DIR_INSTALLER_STATE=str(self.base/'state'),DIR_STACK=str(self.stack),DIR_STACK_HOOKS=str(self.stack/'hooks'),DIR_LEFT4DEAD2=str(self.game),DIR_SOURCEMOD=str(self.game/'addons/sourcemod'),DIR_ADDONS=str(self.game/'addons'),DIR_CFG=str(self.game/'cfg'),DIR_APP=str(self.app),DIR_TMP=str(self.base/'tmp'),STACK_PROFILE='test',GAMESERVER='l4d2server',L4D2_AUTOSTART='false',STACK_LOCK_ROOT=str(self.base/'locks'),GEOIPUPDATE_ENABLED='false')

    def run_install(self,mode='update',extra=None):
        result=subprocess.run(['bash',str(self.installer/'bin/install_stack.sh'),mode],env=dict(self.env,**(extra or {})),capture_output=True,text=True,timeout=20)
        return result

    def assertSuccess(self,result):
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)

    def test_install_repeat_local_reapply_and_hook_fail(self):
        self.assertSuccess(self.run_install('install'))
        plugin=self.game/'addons/sourcemod/plugins/demo.smx'; self.assertEqual(plugin.read_text(),'version1')
        db=self.game/'addons/sourcemod/data/sqlite/local.sq3'; db.parent.mkdir(parents=True,exist_ok=True); db.write_text('live')
        self.assertSuccess(self.run_install(extra={'STACK_REUSE_SOURCES':'true'}))
        self.assertEqual(db.read_text(),'live')
        self.hook.write_text(self.hook.read_text()+'exit 23\n')
        result=self.run_install(); self.assertNotEqual(result.returncode,0)
        self.assertEqual(plugin.read_text(),'version1'); self.assertEqual(db.read_text(),'live')
        state=json.loads((self.base/'state/current/deploy-state.json').read_text()); self.assertEqual(state['status'],'failed')
        sources=json.loads((self.base/'state/source-lock.json').read_text()); self.assertEqual(len(sources[0]['identity']['commit']),40)

    def test_download_failure_and_required_hook_leave_tree(self):
        self.assertSuccess(self.run_install('install'))
        plugin=self.game/'addons/sourcemod/plugins/demo.smx'
        shutil.rmtree(self.base/'state/sources')
        shutil.rmtree(self.source)
        result=self.run_install(); self.assertNotEqual(result.returncode,0); self.assertEqual(plugin.read_text(),'version1')
        self.hook.unlink()
        result=self.run_install(); self.assertNotEqual(result.returncode,0); self.assertIn('Required hook',result.stdout+result.stderr)
        self.assertEqual(plugin.read_text(),'version1')

    def test_publication_failure_restores_and_not_ready(self):
        self.assertSuccess(self.run_install('install'))
        self.hook.write_text(self.hook.read_text()+'printf version2 > "$DIR_SOURCEMOD/plugins/demo.smx"\n')
        result=self.run_install(extra={'STACK_TEST_FAIL_PUBLISH_AFTER':'0'}); self.assertNotEqual(result.returncode,0)
        self.assertEqual((self.game/'addons/sourcemod/plugins/demo.smx').read_text(),'version1')
        self.assertEqual(json.loads((self.base/'state/current/deploy-state.json').read_text())['status'],'failed')
