#!/usr/bin/python3
import json
import os
from pathlib import Path
import sys

values = json.loads(Path('/run/l4d2/environment.json').read_text())
try:
    os.kill(int(Path('/run/l4d2/runtime.pid').read_text()), 0)
except (FileNotFoundError, ProcessLookupError):
    sys.exit('Runtime supervisor unavailable')
os.environ.update(values)
os.execv('/usr/bin/setpriv', ['setpriv', '--reuid='+values['UID'], '--regid='+values['GID'],
    '--init-groups', '--inh-caps=-all', '--ambient-caps=-all', '--bounding-set=-all', '--no-new-privs',
    '/bin/bash', '/app/container/entrypoint-healthcheck.sh'])
