import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

INSTALLER=Path(__file__).resolve().parents[1]

class InstanceSync(unittest.TestCase):
    def test_repeated_sync_preserves_private_bytes_and_logs(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); game=root/'game'; sm=game/'addons/sourcemod'; app=root/'app'; app.mkdir(); config=root/'config'; config.mkdir()
            (config/'instances_exclude.json').write_text(json.dumps({'data':['dumps','bansystem_chatlog'],'plugins':['private.smx']}))
            for rel,value in [('plugins/community.smx','community'),('plugins/private.smx','default'),('data/static.cfg','static'),('data/dumps/primary','DO NOT COPY'),('data/bansystem_chatlog/private','DO NOT COPY')]:
                path=sm/rel; path.parent.mkdir(parents=True,exist_ok=True); path.write_text(value)
            dest=Path(str(sm)+'1')
            for rel,value in [('data/dumps/local','own'),('data/bansystem_chatlog/local','own-chat'),('logs/errors_1.log','evidence'),('plugins/private.smx','private-instance')]:
                path=dest/rel; path.parent.mkdir(parents=True,exist_ok=True); path.write_text(value)
            executable=app/'l4d2server'; executable.write_text('#!/bin/bash\nexit 0\n'); executable.chmod(0o755)
            mock=root/'mock'; mock.mkdir(); tmux=mock/'tmux'; tmux.write_text('#!/bin/bash\nexit 1\n'); tmux.chmod(0o755)
            env=dict(os.environ,DIR_INSTALLER_BIN=str(INSTALLER/'bin'),DIR_INSTALLER_LIB=str(INSTALLER/'lib'),DIR_INSTALLER_CONFIG=str(config),DIR_APP=str(app),DIR_SOURCEMOD=str(sm),DIR_LEFT4DEAD2=str(game),DIR_CFG=str(game/'cfg'),DIR_INSTALLER_STATE=str(root/'state'),GAMESERVER='l4d2server',STACK_LOCK_ROOT=str(root/'locks'),PATH=str(mock)+':'+os.environ['PATH'])
            for _ in range(3):
                result=subprocess.run(['bash',str(INSTALLER/'bin/sync_instances.sh'),'0'],env=env,capture_output=True,text=True)
                self.assertEqual(result.returncode,0,result.stdout+result.stderr)
                self.assertEqual((dest/'data/dumps/local').read_text(),'own')
                self.assertEqual((dest/'logs/errors_1.log').read_text(),'evidence')
                self.assertEqual((dest/'plugins/private.smx').read_text(),'private-instance')
                self.assertFalse((dest/'data/dumps/primary').exists())
                self.assertTrue((dest/'plugins/community.smx').exists())
