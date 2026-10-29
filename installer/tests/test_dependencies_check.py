"""Dependency diagnostics must never repair packages, including missing .so files."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[2] / 'container/bootstrap/dependencies_check.sh'


class DependenciesCheck(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        bootstrap = self.root / 'container/bootstrap'
        bootstrap.mkdir(parents=True)
        self.script = bootstrap / SCRIPT.name
        shutil.copyfile(SCRIPT, self.script)
        self.manifest = bootstrap.parent / 'runtime-packages.txt'
        self.manifest.write_text('libcurl4t64:i386\nlib32stdc++6\n')
        self.library = self.root / 'libcurl.so.4'
        self.library.write_text('fixture library')
        self.fixture = self.root / 'packages.json'
        self.packages = {
            'libcurl4t64:i386': {'status': 'installed', 'files': [str(self.library)]},
            'lib32stdc++6': {'status': 'installed', 'files': []},
        }
        mock = self.root / 'mock'
        mock.mkdir()
        query = mock / 'dpkg-query'
        query.write_text('''#!/usr/bin/env python3
import json, os, sys
data = json.load(open(os.environ['DPKG_FIXTURE']))
package = data.get(sys.argv[-1])
if package is None: sys.exit(1)
if sys.argv[1] == '-W': print(package['status'], end='')
elif sys.argv[1] == '-L':
    if package.get('list_error'): sys.exit(1)
    print('\\n'.join(package['files']))
else: sys.exit(2)
''')
        query.chmod(0o755)
        self.mutation = self.root / 'mutation'
        for name in ['apt-get', 'apt', 'dpkg', 'sudo']:
            command = mock / name
            command.write_text('#!/bin/sh\nprintf mutation > "$MUTATION_SENTINEL"\nexit 99\n')
            command.chmod(0o755)
        self.env = dict(os.environ, PATH=str(mock) + ':' + os.environ['PATH'],
                        DPKG_FIXTURE=str(self.fixture), MUTATION_SENTINEL=str(self.mutation))

    def run_check(self, *args):
        self.fixture.write_text(json.dumps(self.packages))
        result = subprocess.run(['bash', str(self.script), *args], env=self.env,
                                capture_output=True, text=True, check=False)
        self.assertFalse(self.mutation.exists(), 'Checker attempted to mutate packages')
        return result

    def test_installed_architecture_and_existing_libraries_are_verified(self):
        result = self.run_check('--strict')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('Libraries verified: 2 required packages', result.stdout)
        self.assertEqual(result.stderr, '')

    def test_missing_i386_package_only_warns_and_strict_rejects_it(self):
        del self.packages['libcurl4t64:i386']
        self.packages['libcurl4t64'] = {'status': 'installed', 'files': []}
        result = self.run_check()
        self.assertEqual(result.returncode, 0)
        self.assertIn('Missing required package: libcurl4t64:i386', result.stderr)
        self.assertNotIn('Libraries verified:', result.stdout)
        self.assertEqual(self.run_check('--strict').returncode, 1)

    def test_installed_package_with_missing_library_is_not_verified(self):
        self.library.unlink()
        result = self.run_check()
        self.assertEqual(result.returncode, 0)
        self.assertIn('Missing library file (libcurl4t64:i386)', result.stderr)
        self.assertNotIn('Libraries verified:', result.stdout)
        self.assertEqual(self.run_check('--strict').returncode, 1)

    def test_removed_package_and_unreadable_inventory_are_not_verified(self):
        self.packages['lib32stdc++6']['status'] = 'config-files'
        self.packages['libcurl4t64:i386']['list_error'] = True
        result = self.run_check('--strict')
        self.assertEqual(result.returncode, 1)
        self.assertIn('Cannot inspect library files', result.stderr)
        self.assertIn('Missing required package: lib32stdc++6', result.stderr)

    def test_missing_or_empty_manifest_never_reports_success(self):
        for text in [None, '', '# no packages\n']:
            with self.subTest(text=text):
                if text is None:
                    self.manifest.unlink()
                else:
                    self.manifest.write_text(text)
                result = self.run_check('--strict')
                self.assertEqual(result.returncode, 1)
                self.assertNotIn('Libraries verified:', result.stdout)

    def test_invalid_arguments_are_rejected(self):
        self.assertEqual(self.run_check('--repair').returncode, 2)
        self.assertEqual(self.run_check('--strict', 'extra').returncode, 2)
