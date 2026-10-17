import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[2]


class RuntimePermissions(unittest.TestCase):
    def test_only_runtime_entrypoints_become_executable_caches_stay_unchanged(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            names=['container/entrypoint-user.sh','installer/bin/install_stack.sh',
                   'stack/hooks/demo.sh','lgsm/modules/command_start.sh','l4d2server',
                   'installer/cache/work/source/plugin','installer/state/sources/test/repo/file',
                   'installer/cache/artifacts/hash/original.zip','serverfiles/cfg/local.cfg']
            for name in names:
                p=root/name; p.parent.mkdir(parents=True,exist_ok=True); p.write_text('bytes'); p.chmod(0o644)
            outside=root.parent/(root.name+'-outside'); outside.write_text('external'); outside.chmod(0o644)
            self.addCleanup(outside.unlink)
            (root/'container/external.sh').symlink_to(outside)
            subprocess.run(['bash','-c','source "$1"; stack_set_runtime_executables "$2"','bash',str(ROOT/'container/runtime-permissions.sh'),str(root)],check=True)
            for name in names[:5]: self.assertTrue((root/name).stat().st_mode & 0o111,name)
            for name in names[5:]: self.assertEqual((root/name).stat().st_mode & 0o777,0o644,name)
            self.assertEqual(outside.stat().st_mode & 0o777,0o644)
