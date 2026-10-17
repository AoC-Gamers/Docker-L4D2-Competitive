import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
import zipfile

LIB = Path(__file__).resolve().parents[1] / 'lib'
sys.path.insert(0, str(LIB))
from overlay_stack import deploy
from final_policy import apply


class OverlayTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.root = self.base / 'game'
        self.root.mkdir()
        self.state = self.base / 'state'
        self.archive = self.base / 'resource.zip'

    def run_overlay(self, subtree='sound', label='whitelist_sound'):
        deploy(self.archive, self.base / 'extract', subtree, self.root, label, self.state)

    def zip(self, files):
        with zipfile.ZipFile(self.archive, 'w') as zf:
            for path, value in files.items():
                zf.writestr(path, value)

    def test_install_update_remove_repeat_all_roots(self):
        for subtree, label in [('sound', 'whitelist_sound'), ('models', 'fortnite_emotes_models'), ('addons', 'fortnite_emotes_addons')]:
            foreign = self.root / 'aoc/probe'; foreign.parent.mkdir(exist_ok=True); foreign.write_text('foreign')
            self.zip({subtree + '/aoc/probe': 'managed'})
            self.run_overlay(subtree, label); self.run_overlay(subtree, label)
            self.zip({subtree + '/aoc/new': 'new'})
            self.run_overlay(subtree, label)
            self.assertFalse((self.root / subtree / 'aoc/probe').exists())
            self.assertEqual(foreign.read_text(), 'foreign')
            self.archive.unlink(); self.run_overlay(subtree, label); self.run_overlay(subtree, label)
            self.assertFalse((self.root / subtree / 'aoc/new').exists())

    def test_legacy_verified_and_unverified(self):
        self.state.mkdir(); old = self.state / 'whitelist_sound_.paths'
        old.write_text('aoc/probe\naoc/unknown\n')
        for name in ('probe', 'unknown'):
            p = self.root / 'sound/aoc' / name; p.parent.mkdir(parents=True, exist_ok=True); p.write_text('old')
        self.zip({'sound/aoc/probe': 'old'}); self.run_overlay()
        self.archive.unlink(); self.run_overlay()
        self.assertFalse((self.root / 'sound/aoc/probe').exists())
        self.assertTrue((self.root / 'sound/aoc/unknown').exists())
        self.assertTrue(old.with_suffix('.paths.unresolved').exists())

    def test_invalid_registry_and_archives(self):
        self.state.mkdir()
        for path in ('../victim', '/victim', 'models/victim', 'sound/../victim'):
            (self.state / 'whitelist_sound.json').write_text(json.dumps({'schema_version': 2, 'subtree':'sound','files':{path:'hash'}}))
            with self.assertRaises(ValueError): self.run_overlay()
        (self.state / 'whitelist_sound.json').unlink()
        self.zip({'../escape':'bad'})
        with self.assertRaises(ValueError): self.run_overlay()
        self.assertFalse((self.base / 'escape').exists())

    def test_symlink_escape_and_modified_owned_file(self):
        outside = self.base / 'outside'; outside.mkdir(); (self.root / 'sound').symlink_to(outside)
        self.zip({'sound/probe':'bad'})
        with self.assertRaises(ValueError): self.run_overlay()
        self.assertFalse((outside / 'probe').exists())
        (self.root / 'sound').unlink(); self.run_overlay()
        (self.root / 'sound/probe').write_text('local')
        self.archive.unlink(); self.run_overlay()
        self.assertEqual((self.root / 'sound/probe').read_text(), 'local')

    def test_final_policy_after_hostile_layer(self):
        policy = self.base / 'policy.json'
        remove = ['cfg/sharedplugins.cfg', 'cfg/sharedplugins1.cfg', 'addons/sourcemod/plugins/match_vote.smx', 'addons/sourcemod/plugins/confoglcompmod.smx']
        policy.write_text(json.dumps({'remove':dict.fromkeys(remove, 'reason'), 'remove_exec':['sharedplugins.cfg']}))
        for iteration in range(2):
            for rel in remove:
                p=self.root/rel; p.parent.mkdir(parents=True,exist_ok=True); p.write_text('late layer')
            community=self.root/'addons/sourcemod/plugins/community.smx'; community.write_text('keep')
            local=self.root/'cfg/local.cfg'; local.write_text('hostname local\nexec "sharedplugins.cfg"\n')
            apply(self.root,policy); apply(self.root,policy)
            self.assertTrue(community.exists())
            self.assertEqual(local.read_text(),'hostname local\n')
            for rel in remove: self.assertFalse((self.root/rel).exists())
