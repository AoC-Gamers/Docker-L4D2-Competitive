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
        if path.is_file():
            path.unlink()
        elif path.exists():
            raise ValueError(f'Expected file for final exclusion: {rel}')
    # Remove only exact exec/load commands, preserving local configuration lines.
    cfg = root / 'cfg'
    commands = set(data.get('remove_exec', []))
    plugins = set(data.get('remove_load', []))
    for path in sorted(cfg.rglob('*.cfg')) if cfg.exists() else []:
        safe_path(root, path.relative_to(root).as_posix())
        text = path.read_text()
        lines = []
        for line in text.splitlines(keepends=True):
            command = line.split('//', 1)[0].strip().rstrip(';').strip()
            match = re.fullmatch(r'exec\s+"?([^"\s;]+)"?', command)
            load = re.fullmatch(r'sm\s+plugins\s+load\s+"?([^"\s;]+)"?', command)
            if (match and match[1] in commands) or (load and load[1] in plugins):
                continue
            # Compound commands must be reviewed instead of silently surviving.
            if any(re.search(r'(?:^|;)\s*exec\s+"?' + re.escape(v) + r'(?:"|\s|;|$)', command) for v in commands):
                raise ValueError(f'Compound excluded exec requires migration: {path.relative_to(root)}')
            lines.append(line)
        updated = ''.join(lines)
        if updated != text:
            path.write_text(updated)


if __name__ == '__main__':
    if Path(sys.argv[2]).is_file():
        apply(Path(sys.argv[1]), Path(sys.argv[2]))
