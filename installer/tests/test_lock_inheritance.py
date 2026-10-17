"""Long-lived runtime children must not keep a finished deployment locked."""
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time
import unittest

INSTALLER = Path(__file__).resolve().parents[1]


class RuntimeLockInheritance(unittest.TestCase):
    def check_runtime_boundary(self, action):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            app = root/'app'
            mock = root/'mock'
            state = root/'state'
            transaction = root/'transaction'
            for directory in (app, mock, state, transaction):
                directory.mkdir()
            daemon_file = root/'daemon.pid'
            running = root/'running'
            (state/'runtime-intent.json').write_text('["l4d2server"]\n')
            (transaction/'running-instances').write_text('l4d2server\n')
            if action == 'quiesce':
                running.touch()
            spawn = '''sleep 30 </dev/null >/dev/null 2>&1 &
printf '%s\\n' "$!" > "$DAEMON_PID_FILE"
'''
            executable = app/'l4d2server'
            executable.write_text('#!/bin/bash\n' + spawn +
                                  'if [[ "$1" == stop ]]; then rm -f "$RUNNING"; fi\n')
            executable.chmod(0o755)
            tmux = mock/'tmux'
            tmux.write_text('#!/bin/bash\n' +
                            'if [[ "$SPAWN_ON_QUERY" == true && ! -s "$DAEMON_PID_FILE" ]]; then\n' +
                            spawn + 'fi\n[[ -f "$RUNNING" ]]\n')
            tmux.chmod(0o755)
            env = dict(os.environ, PATH=str(mock)+':'+os.environ['PATH'],
                       DIR_INSTALLER_LIB=str(INSTALLER/'lib'),
                       DIR_INSTALLER_BIN=str(INSTALLER/'bin'), DIR_INSTALLER_STATE=str(state),
                       DIR_APP=str(app), DIR_LEFT4DEAD2=str(root/'game'),
                       GAMESERVER='l4d2server', STACK_LOCK_ROOT=str(root/'locks'),
                       STACK_TRANSACTION=str(transaction), L4D2_AUTOSTART='true',
                       DAEMON_PID_FILE=str(daemon_file), RUNNING=str(running),
                       SPAWN_ON_QUERY='true' if action in ('query', 'capture') else 'false',
                       ACTION=action, READY_FILE=str(root/'ready'))
            script = '''set -euo pipefail
source "$DIR_INSTALLER_LIB/tools_stack.sh"
source "$DIR_INSTALLER_LIB/deployment_transaction.sh"
stack_acquire_target_lock
case "$ACTION" in
    resume) stack_resume_instances ;;
    quiesce) stack_quiesce_instances ;;
    intent) bash "$DIR_INSTALLER_BIN/runtime_intent.sh" resume ;;
    capture) bash "$DIR_INSTALLER_BIN/runtime_intent.sh" capture ;;
    query) instance_is_running "$GAMESERVER" || true ;;
    start|stop|restart) bash "$DIR_INSTALLER_BIN/menu_stack.sh" "$ACTION" ;;
esac
touch "$READY_FILE"
read -r finish
'''
            with (root/'output').open('w+') as output:
                parent = subprocess.Popen(['bash', '-c', script], env=env, stdin=subprocess.PIPE,
                                          stdout=output, stderr=output, text=True)
                try:
                    deadline = time.monotonic()+5
                    while not (root/'ready').exists() and parent.poll() is None and time.monotonic() < deadline:
                        time.sleep(.02)
                    output.seek(0)
                    self.assertTrue((root/'ready').exists(), output.read())
                    self.assertTrue(daemon_file.exists())
                    lock = next((root/'locks').glob('*.lock'))
                    probe = ['flock', '-n', str(lock), 'true']
                    # Child launch must not release the owner's lock early.
                    self.assertNotEqual(subprocess.run(probe).returncode, 0)
                    parent.communicate('\n', timeout=3)
                    self.assertEqual(parent.returncode, 0)
                    # The detached child is alive, but a subsequent installer can enter.
                    os.kill(int(daemon_file.read_text()), 0)
                    self.assertEqual(subprocess.run(probe).returncode, 0,
                                     'runtime child retained the finished deployment lock')
                finally:
                    if parent.poll() is None:
                        parent.kill()
                    parent.communicate(timeout=3)
                    if daemon_file.exists():
                        try:
                            os.kill(int(daemon_file.read_text()), signal.SIGTERM)
                        except ProcessLookupError:
                            pass

    def test_publication_resume(self):
        self.check_runtime_boundary('resume')

    def test_publication_stop(self):
        self.check_runtime_boundary('quiesce')

    def test_boot_runtime_intent_resume(self):
        self.check_runtime_boundary('intent')

    def test_runtime_intent_capture_query(self):
        self.check_runtime_boundary('capture')

    def test_tmux_status_query(self):
        self.check_runtime_boundary('query')

    def test_menu_start(self):
        self.check_runtime_boundary('start')

    def test_menu_stop(self):
        self.check_runtime_boundary('stop')

    def test_menu_restart(self):
        self.check_runtime_boundary('restart')
