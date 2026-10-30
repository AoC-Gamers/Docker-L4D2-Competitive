import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

INSTALLER=Path(__file__).resolve().parents[1]


class RuntimeShutdown(unittest.TestCase):
    def test_twelve_instances_preserve_selection_shutdown_and_resume(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); app=root/'app'; app.mkdir(); mock=root/'mock'; mock.mkdir(); state=root/'state'; state.mkdir()
            selected=['l4d2server']+[f'l4d2server-{i}' for i in [2,4,6,10,12]]
            running=root/'running'; running.write_text('\n'.join(selected)+'\n'); events=root/'events'
            tmux=mock/'tmux';tmux.write_text('''#!/bin/bash
name=${!#}; name=${name#=}
grep -Fxq "$name" "$RUNNING"
''');tmux.chmod(0o755)
            for i in range(1,13):
                name='l4d2server' if i==1 else f'l4d2server-{i}'
                p=app/name;p.write_text('''#!/bin/bash
name=$(basename "$0")
echo "$name $1" >> "$EVENTS"
if [[ "$1" == stop ]]; then
 grep -Fxv "$name" "$RUNNING" > "$RUNNING.tmp" || true
 mv "$RUNNING.tmp" "$RUNNING"
else
 echo "$name" >> "$RUNNING"
fi
''');p.chmod(0o755)
            env=dict(os.environ,PATH=str(mock)+':'+os.environ['PATH'],DIR_APP=str(app),GAMESERVER='l4d2server',DIR_LEFT4DEAD2=str(root/'game'),DIR_INSTALLER_LIB=str(INSTALLER/'lib'),DIR_INSTALLER_STATE=str(state),STACK_LOCK_ROOT=str(root/'locks'),RUNNING=str(running),EVENTS=str(events),L4D2_AUTOSTART='true')
            command=['bash',str(INSTALLER/'bin/runtime_intent.sh')]
            subprocess.run(command+['shutdown'],env=env,check=True,capture_output=True,text=True)
            self.assertEqual(running.read_text(),'')
            self.assertEqual(set(json.loads((state/'runtime-intent.json').read_text())),set(selected))
            self.assertEqual(set(events.read_text().splitlines()),{f'{name} stop' for name in selected})
            subprocess.run(command+['resume'],env=env,check=True,capture_output=True,text=True)
            self.assertEqual(set(running.read_text().splitlines()),set(selected))
            self.assertEqual(set(json.loads((state/'runtime-intent.json').read_text())),set(selected))
