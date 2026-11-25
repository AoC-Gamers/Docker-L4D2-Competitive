"""Check launcher selection without contacting Steam or starting SRCDS."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


UPDATER = Path(__file__).resolve().parents[2] / "container/bootstrap/l4d2_updater.sh"


class L4D2Updater(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        root = Path(directory.name)
        self.game = root / "serverfiles"
        self.game.mkdir()
        self.cfg = root / "config/l4d2server/common.cfg"
        self.cfg.parent.mkdir(parents=True)
        self.original = self.game / "srcds_run"
        self.original.write_text('#!/bin/sh\nAUTO_UPDATE=""\nSTEAM_DIR=""\nSTEAMCMD_SCRIPT=""\n')
        self.wrapper = self.game / "srcds_l4d2"
        self.steamcmd_script = self.game / "update_l4d2.txt"
        self.env = dict(
            os.environ,
            LGSM_SERVERFILES=str(self.game),
            LGSM_CONFIG=str(self.cfg.parent.parent),
            GAMESERVER="l4d2server",
        )

    def run_updater(self, value):
        result = subprocess.run(
            ["bash", str(UPDATER)],
            env=dict(self.env, L4D2_UPDATER=value),
            capture_output=True,
            text=True,
            timeout=10,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_disabled_migrates_existing_launcher_and_preserves_files(self):
        for quote in ('"', "'", ""):
            with self.subTest(quote=quote):
                initial = f'tickrate="120"\nexecutable={quote}./srcds_l4d2{quote}  # Valve\n'
                self.cfg.write_text(initial)
                self.wrapper.write_text("existing wrapper\n")
                self.steamcmd_script.write_text("existing SteamCMD script\n")
                self.run_updater("false")
                self.assertEqual(self.cfg.read_text(), initial.replace("srcds_l4d2", "srcds_run"))
                self.assertEqual(self.wrapper.read_text(), "existing wrapper\n")
                self.assertEqual(self.steamcmd_script.read_text(), "existing SteamCMD script\n")
                changed_at = self.cfg.stat().st_mtime_ns
                self.run_updater("false")
                self.assertEqual(self.cfg.stat().st_mtime_ns, changed_at)

    def test_enabled_creates_launcher_and_can_enable_again_after_disable(self):
        self.cfg.write_text('tickrate="120"\n')
        self.run_updater("true")
        self.assertIn('executable="./srcds_l4d2"\n', self.cfg.read_text())
        self.assertIn('AUTO_UPDATE="yes"', self.wrapper.read_text())
        self.assertIn("app_update 222860\n", self.steamcmd_script.read_text())
        self.assertIn('AUTO_UPDATE=""', self.original.read_text())
        self.run_updater("false")
        self.assertIn('executable="./srcds_run"\n', self.cfg.read_text())
        self.run_updater("true")
        self.assertEqual(self.cfg.read_text().count('executable="./srcds_l4d2"'), 1)

    def test_disabled_fresh_install_uses_default_without_creating_updater(self):
        initial = 'tickrate="120"\n'
        self.cfg.write_text(initial)
        self.run_updater("false")
        self.assertEqual(self.cfg.read_text(), initial)
        self.assertFalse(self.wrapper.exists())
        self.assertFalse(self.steamcmd_script.exists())

    def test_preserves_custom_launcher_for_both_modes(self):
        initial = 'executable="./local_srctl"\n'
        self.cfg.write_text(initial)
        for enabled in ("true", "false"):
            self.run_updater(enabled)
            self.assertEqual(self.cfg.read_text(), initial)


if __name__ == "__main__":
    unittest.main()
