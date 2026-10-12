import os
from pathlib import Path
import subprocess
import tempfile
import unittest

INSTALLER=Path(__file__).resolve().parents[1]
class Coordination(unittest.TestCase):
    def test_linuxgsm_uid_socket_and_only_previous_running_resumed(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); app=root/'app'; app.mkdir(); mock=root/'mock'; mock.mkdir(); data=root/'data'; data.mkdir()
            events=root/'events'; running=root/'running'; running.write_text('yes')
            (data/'l4d2server.uid').write_text('1234abcd')
            tmux=mock/'tmux'; tmux.write_text('''#!/bin/bash
if [[ "$*" == '-L l4d2server-1234abcd has-session -t =l4d2server' && -f "$RUNNING" ]]; then exit 0; fi
exit 1
'''); tmux.chmod(0o755)
            for name in ('l4d2server','l4d2server-2'):
                p=app/name; p.write_text('''#!/bin/bash
printf '%s %s\\n' "$(basename "$0")" "$1" >> "$EVENTS"
if [[ "$1" == stop ]]; then rm -f "$RUNNING"; else touch "$RUNNING"; fi
'''); p.chmod(0o755)
            env=dict(os.environ,DIR_INSTALLER_LIB=str(INSTALLER/'lib'),DIR_APP=str(app),DIR_LEFT4DEAD2=str(root/'game'),GAMESERVER='l4d2server',LGSM_DATADIR=str(data),STACK_TRANSACTION=str(root/'tx'),PATH=str(mock)+':'+os.environ['PATH'],EVENTS=str(events),RUNNING=str(running))
            (root/'tx').mkdir()
            script='set -euo pipefail; source "$DIR_INSTALLER_LIB/tools_stack.sh"; source "$DIR_INSTALLER_LIB/deployment_transaction.sh"; stack_quiesce_instances; stack_resume_instances'
            result=subprocess.run(['bash','-c',script],env=env,capture_output=True,text=True); self.assertEqual(result.returncode,0,result.stderr)
            self.assertEqual(events.read_text().splitlines(),['l4d2server stop','l4d2server start'])
            false_values=('false','FALSE','no','NO','off','OFF','0')
            for value in false_values:
                with self.subTest(path='stack_resume',value=value):
                    events.unlink(missing_ok=True); running.write_text('yes'); env['L4D2_AUTOSTART']=value
                    result=subprocess.run(['bash','-c',script],env=env,capture_output=True,text=True)
                    self.assertEqual(result.returncode,0,result.stderr)
                    self.assertEqual(events.read_text().splitlines(),['l4d2server stop'])
            true_values=('true','TRUE','yes','YES','on','ON','1')
            for value in true_values:
                with self.subTest(path='stack_resume',value=value):
                    events.unlink(missing_ok=True); running.write_text('yes'); env['L4D2_AUTOSTART']=value
                    result=subprocess.run(['bash','-c',script],env=env,capture_output=True,text=True)
                    self.assertEqual(result.returncode,0,result.stderr)
                    self.assertEqual(events.read_text().splitlines(),['l4d2server stop','l4d2server start'])

            intent_state=root/'intent-state'; intent_state.mkdir()
            (intent_state/'runtime-intent.json').write_text('["l4d2server"]\n')
            env.update(DIR_INSTALLER_STATE=str(intent_state),RUNNING=str(running))
            intent_script=str(INSTALLER/'bin/runtime_intent.sh')
            for value in false_values:
                with self.subTest(path='runtime_intent',value=value):
                    events.unlink(missing_ok=True); running.unlink(missing_ok=True); env['L4D2_AUTOSTART']=value
                    result=subprocess.run(['bash',intent_script,'resume'],env=env,capture_output=True,text=True)
                    self.assertEqual(result.returncode,0,result.stderr)
                    self.assertFalse(events.exists())

            for value in true_values:
                with self.subTest(path='runtime_intent',value=value):
                    events.unlink(missing_ok=True); running.unlink(missing_ok=True); env['L4D2_AUTOSTART']=value
                    result=subprocess.run(['bash',intent_script,'resume'],env=env,capture_output=True,text=True)
                    self.assertEqual(result.returncode,0,result.stderr)
                    self.assertEqual(events.read_text().splitlines(),['l4d2server start'])
