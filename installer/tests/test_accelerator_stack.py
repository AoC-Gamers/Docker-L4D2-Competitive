"""Only the reviewed legacy Accelerator may have its execstack marker normalized."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

LIB = Path(__file__).resolve().parents[1] / 'lib'
LEGACY_HASH = 'e74fdebd0f0eafb721caf4f8fe96e1f5763d73e1cbb2f94a470017bffdc62b76'


class AcceleratorStack(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.library = self.root / 'accelerator.ext.so'
        self.library.write_text('fixture binary')
        self.calls = self.root / 'calls'
        self.cleared = self.root / 'cleared'
        mock = self.root / 'mock'
        mock.mkdir()
        commands = {
            'readelf': '''#!/bin/sh
if [ "$TEST_HEADER" = missing ]; then printf 'LOAD RW\\n';
elif [ -f "$CLEARED" ] || [ "$TEST_HEADER" = rw ]; then printf 'GNU_STACK RW\\n';
else printf 'GNU_STACK RWE\\n'; fi
''',
            'sha256sum': '#!/bin/sh\nprintf "%s  %s\\n" "$TEST_HASH" "$1"\n',
            'patchelf': '''#!/bin/sh
[ "$1" = --clear-execstack ] || exit 2
printf '%s\\n' "$2" >> "$CALLS"
touch "$CLEARED"
''',
        }
        for name, content in commands.items():
            path = mock / name
            path.write_text(content)
            path.chmod(0o755)
        self.env = dict(os.environ, DIR_INSTALLER_LIB=str(LIB),
                        PATH=str(mock) + ':' + os.environ['PATH'], TEST_HASH=LEGACY_HASH,
                        TEST_HEADER='rwe', CALLS=str(self.calls), CLEARED=str(self.cleared))

    def run_hook(self, **env):
        script = '''set -euo pipefail
error_exit() { printf '%s\\n' "$*" >&2; exit 1; }
log() { printf '%s\\n' "$*"; }
source "$DIR_INSTALLER_LIB/stack_component_lib.sh"
stack_normalize_accelerator_execstack "$1"
'''
        return subprocess.run(['bash', '-c', script, 'bash', str(self.library)],
                              env=dict(self.env, **env), capture_output=True, text=True)

    def test_known_artifact_is_normalized_once(self):
        for _ in range(2):
            result = self.run_hook()
            self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls.read_text().splitlines(), [str(self.library)])

    def test_unknown_executable_stack_artifact_is_rejected_without_changes(self):
        result = self.run_hook(TEST_HASH='0' * 64)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Unknown Accelerator artifact', result.stderr)
        self.assertFalse(self.calls.exists())
        self.assertEqual(self.library.read_text(), 'fixture binary')

    def test_non_executable_artifact_is_preserved_without_hash_exception(self):
        result = self.run_hook(TEST_HASH='0' * 64, TEST_HEADER='rw')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.calls.exists())

    def test_missing_header_or_symlink_is_rejected(self):
        self.assertNotEqual(self.run_hook(TEST_HEADER='missing').returncode, 0)
        target = self.root / 'target'
        self.library.rename(target)
        self.library.symlink_to(target)
        self.assertNotEqual(self.run_hook().returncode, 0)
        self.assertFalse(self.calls.exists())

    def test_absent_optional_artifact_is_skipped(self):
        self.library.unlink()
        result = self.run_hook()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.calls.exists())

class AcceleratorComposition(unittest.TestCase):
    def test_final_layer_is_normalized_after_cache_replay_without_mutating_cache(self):
        import json
        import shutil
        import test_installer_flow as flow_module
        flow = flow_module.InstallerFlow()
        flow.setUp()
        self.addCleanup(flow.doCleanups)
        catalog = json.loads((flow.stack / 'manifests/components.json').read_text())
        catalog['late'] = dict(catalog['demo'], folder='late')
        (flow.stack / 'manifests/components.json').write_text(json.dumps(catalog))
        (flow.stack / 'profiles/test.json').write_text('{"components":["demo","late"]}')
        flow.hook.write_text(flow.hook.read_text() + '''
mkdir -p "$DIR_SOURCEMOD/extensions"
printf early > "$DIR_SOURCEMOD/extensions/accelerator.ext.so"
''')
        (flow.stack / 'hooks/late.default.sh').write_text('''#!/bin/bash
set -euo pipefail
mkdir -p "$DIR_SOURCEMOD/extensions"
printf legacy > "$DIR_SOURCEMOD/extensions/accelerator.ext.so"
''')
        mocks = {
            'readelf': '''#!/usr/bin/env python3
import pathlib, sys
print('GNU_STACK RW' if pathlib.Path(sys.argv[-1]).read_text() == 'normalized' else 'GNU_STACK RWE')
''',
            'sha256sum': f'''#!/usr/bin/env python3
import os, sys
if len(sys.argv) == 2 and sys.argv[1].endswith('/extensions/accelerator.ext.so'):
    print({LEGACY_HASH!r} + '  ' + sys.argv[1])
else:
    os.execv({shutil.which('sha256sum')!r}, ['sha256sum'] + sys.argv[1:])
''',
            'patchelf': '''#!/usr/bin/env python3
import pathlib, sys
assert sys.argv[1] == '--clear-execstack'
p = pathlib.Path(sys.argv[2])
assert p.read_text() == 'legacy', 'Normalizer ran before the final overlay'
p.write_text('normalized')
''',
        }
        for name, text in mocks.items():
            path = flow.mock / name
            path.write_text(text)
            path.chmod(0o755)
        for iteration in range(2):
            result = flow.run_install(extra={'STACK_REUSE_SOURCES': 'true'} if iteration else {})
            flow.assertSuccess(result)
            self.assertEqual((flow.game / 'addons/sourcemod/extensions/accelerator.ext.so').read_text(), 'normalized')
            cached = list((flow.installer / 'cache/prepared/late').glob('*/files/serverfiles/left4dead2/addons/sourcemod/extensions/accelerator.ext.so'))
            self.assertTrue(cached)
            self.assertTrue(all(path.read_text() == 'legacy' for path in cached))
            if iteration:
                self.assertIn('Prepared cache reused: late', result.stdout)
