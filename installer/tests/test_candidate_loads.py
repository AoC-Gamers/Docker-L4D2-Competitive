"""Runtime diagnostics report missing loads without repairing publisher CFGs."""
from contextlib import redirect_stdout
import io
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

LIB = Path(__file__).resolve().parents[1] / 'lib'
sys.path.insert(0, str(LIB))
from validate_candidate import validate


class CandidateLoads(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'cfg').mkdir()
        self.cfg = self.root / 'cfg/sharedplugins.cfg'
        self.plugins = self.root / 'addons/sourcemod/plugins'
        self.plugins.mkdir(parents=True)

    def check(self):
        with redirect_stdout(io.StringIO()) as output:
            messages = validate(self.root)
        return messages, output.getvalue()

    def test_missing_local_external_and_optional_are_advisory_and_cfg_is_unchanged(self):
        original = ('sm plugins load custom/local.smx\n'
                    'sm plugins load external/core.smx\n'
                    'sm plugins load optional.smx\n')
        self.cfg.write_text(original)
        result = subprocess.run([sys.executable, str(LIB / 'validate_candidate.py'), str(self.root)],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.count('WARN :'), 3)
        for line, path in enumerate(('custom/local.smx', 'external/core.smx', 'optional.smx'), 1):
            self.assertIn(f'cfg/sharedplugins.cfg:{line}: addons/sourcemod/plugins/{path}', result.stdout)
        self.assertEqual(self.cfg.read_text(), original)
        self.assertEqual(self.check()[0], self.check()[0])

    def test_composed_plugins_quotes_extension_comments_and_command_separators(self):
        for name in ('community.smx', 'external/core.smx', 'folder/with ; spaces.smx'):
            path = self.plugins / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.touch()
        self.cfg.write_text('// sm plugins load comment.smx\n'
                            'sm plugins load "community"; sm plugins load external/core.smx // ignored\n'
                            'sm plugins load "folder/with ; spaces.smx"\n')
        self.assertEqual(self.check(), ([], ''))

    def test_second_loader_and_multiple_missing_commands_are_reported(self):
        self.cfg.write_text('echo "sm plugins load ignored.smx"; sm plugins load missing; sm plugins load "other.smx"\n')
        (self.root / 'cfg/sharedplugins1.cfg').write_text('sm plugins load wrapper.smx\n')
        messages, _ = self.check()
        self.assertEqual(len(messages), 3)
        self.assertIn('cfg/sharedplugins1.cfg:1:', messages[-1])
        self.assertFalse(any('ignored.smx' in message for message in messages))

    def test_unrecognized_load_syntax_is_advisory(self):
        self.cfg.write_text('sm plugins load "unterminated\nsm plugins load\n')
        messages, _ = self.check()
        self.assertEqual(len(messages), 2)
        self.assertTrue(all('review manually' in message for message in messages))

    def test_unsafe_paths_still_fail(self):
        for plugin in ('/tmp/outside.smx', '../outside.smx', 'custom/../../outside', r'custom\outside.smx'):
            with self.subTest(plugin=plugin):
                self.cfg.write_text('sm plugins load "' + plugin + '"\n')
                with self.assertRaises(ValueError):
                    self.check()
        outside = self.root / 'outside'
        outside.mkdir()
        (self.plugins / 'linked').symlink_to(outside, target_is_directory=True)
        self.cfg.write_text('sm plugins load linked/outside.smx\n')
        with self.assertRaisesRegex(ValueError, 'Symlink'):
            self.check()

    def test_absent_loaders_do_not_generate_warnings(self):
        self.assertEqual(self.check(), ([], ''))
