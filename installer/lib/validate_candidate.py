#!/usr/bin/env python3
"""Report shared-loader references absent from the fully composed candidate.

Missing binaries are advisory: the installer cannot infer the author's intent.
Unsafe paths remain errors. No CFG is modified and exec chains are not followed.
"""
from datetime import datetime
from pathlib import Path, PurePosixPath
import re
import sys
from overlay_stack import safe_path


def commands(line):
    """Split Source CFG commands, respecting quoted semicolons and // comments."""
    quoted = False
    start = 0
    index = 0
    while index < len(line):
        char = line[index]
        if char == '"':
            quoted = not quoted
        if not quoted:
            if line[index:index + 2] == '//':
                break
            if char == ';':
                yield line[start:index].strip()
                start = index + 1
        index += 1
    yield line[start:index].strip()


def validate(root):
    messages = []

    def report(message):
        messages.append(message)
        print(f'[{datetime.now():%Y-%m-%d %H:%M:%S}] WARN : {message}')

    for name in ('sharedplugins.cfg', 'sharedplugins1.cfg'):
        cfg = safe_path(root, 'cfg/' + name)
        if not cfg.is_file():
            continue
        for number, line in enumerate(cfg.read_text().splitlines(), 1):
            for command in commands(line):
                if not re.match(r'^sm\s+plugins\s+load(?:\s|$)', command):
                    continue
                match = re.fullmatch(r'sm\s+plugins\s+load\s+(?:"([^"\n]+)"|([^\s"]+))', command)
                location = f'cfg/{name}:{number}'
                if not match:
                    report(f'Unrecognized plugin load syntax at {location}; review manually.')
                    continue
                plugin = match[1] if match[1] is not None else match[2]
                if PurePosixPath(plugin).is_absolute():
                    raise ValueError(f'Unsafe plugin path at {location}: {plugin!r}')
                if not plugin.endswith('.smx'):
                    plugin += '.smx'
                relative = 'addons/sourcemod/plugins/' + plugin
                path = safe_path(root, relative)
                if not path.is_file():
                    report(f'Plugin load has no binary in composed candidate: {location}: {relative}; configuration unchanged.')
    return messages


if __name__ == '__main__':
    validate(Path(sys.argv[1]))
