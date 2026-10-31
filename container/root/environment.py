#!/usr/bin/python3
"""Read runtime environment as data; SSH commands never source shell credentials."""
import json
import os
from pathlib import Path
import shlex
import sys

if __name__ == '__main__':
    values = json.loads(Path('/run/l4d2/environment.json').read_text())
    if sys.argv[1:] == ['--exports']:
        for name, value in values.items():
            if name != 'UID':
                print(f'export {name}={shlex.quote(value)}')
    else:
        os.environ.update(values)
        args = sys.argv[1:] or ['-l']
        os.execv('/usr/bin/setpriv', ['setpriv', '--no-new-privs', '/bin/bash', *args])
