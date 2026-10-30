#!/usr/bin/python3
"""Unprivileged deployment lifecycle and orderly multi-instance shutdown."""
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

stopping = False
child = None

def stop(signum, frame):
    global stopping
    stopping = True
    if child is not None and child.poll() is None:
        os.killpg(child.pid, signum)

for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGQUIT):
    signal.signal(sig, stop)

if sys.argv[1:]:
    os.execvp(sys.argv[1], sys.argv[1:])
child = subprocess.Popen(['/bin/bash', '/app/container/entrypoint-user.sh'], start_new_session=True)
while child.poll() is None:
    time.sleep(0.2)
if not stopping:
    if child.returncode:
        print('Deployment failed; keeping SSH available for diagnosis', flush=True)
    subprocess.run(['/bin/bash', '-c', 'source "$DIR_INSTALLER_LIB/tools_stack.sh"; source "$DIR_INSTALLER_LIB/extensions_stack.sh"; stack_run_extension idle'])
while not stopping:
    time.sleep(0.2)
print('Saving runtime intent and stopping all active instances', flush=True)
result = subprocess.run(['/bin/bash', os.environ['DIR_INSTALLER_BIN']+'/runtime_intent.sh', 'shutdown'])
sys.exit(result.returncode)
