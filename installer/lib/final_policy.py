#!/usr/bin/env python3
"""Apply narrowly named final exclusions after all layers, including old volumes."""
import json
from pathlib import Path
import re
import sys
from overlay_stack import safe_path


def apply(root, policy):
    data = json.loads(policy.read_text())
    for rel in data.get('remove', {}):
        path = safe_path(root, rel)
        status = 'absent'
        if path.is_file():
            path.unlink()
            status = 'removed'
        elif path.exists():
            raise ValueError(f'Expected file for final exclusion: {rel}')
        print(f'Excluded path from deployment: {rel} ({status})')
    # Remove only exact exec/load commands, preserving local configuration lines.
    cfg = root / 'cfg'
    commands = set(data.get('remove_exec', []))
    plugins = set(data.get('remove_load', []))
    removed_exec = dict.fromkeys(commands, 0)
    removed_load = dict.fromkeys(plugins, 0)
    for path in sorted(cfg.rglob('*.cfg')) if cfg.exists() else []:
        safe_path(root, path.relative_to(root).as_posix())
        text = path.read_text()
        lines = []
        for line in text.splitlines(keepends=True):
            command = line.split('//', 1)[0].strip().rstrip(';').strip()
            match = re.fullmatch(r'exec\s+"?([^"\s;]+)"?', command)
            load = re.fullmatch(r'sm\s+plugins\s+load\s+"?([^"\s;]+)"?', command)
            if (match and match[1] in commands) or (load and load[1] in plugins):
                if match and match[1] in commands:
                    removed_exec[match[1]] += 1
                if load and load[1] in plugins:
                    removed_load[load[1]] += 1
                continue
            # Compound commands must be reviewed instead of silently surviving.
            if any(re.search(r'(?:^|;)\s*exec\s+"?' + re.escape(v) + r'(?:"|\s|;|$)', command) for v in commands):
                raise ValueError(f'Compound excluded exec requires migration: {path.relative_to(root)}')
            lines.append(line)
        updated = ''.join(lines)
        if updated != text:
            path.write_text(updated)
    for verb, counts in (('exec', removed_exec), ('sm plugins load', removed_load)):
        for value, count in sorted(counts.items()):
            status = 'removed' if count else 'absent'
            print(f'Excluded command from deployment: {verb} {value} ({status}; occurrences={count})')


if __name__ == '__main__':
    if Path(sys.argv[2]).is_file():
        apply(Path(sys.argv[1]), Path(sys.argv[2]))
