"""Cache reuse across startup permission damage and Git transport metadata."""
import unittest
import test_installer_flow as flow_module


class InstallerCache(unittest.TestCase):
    def test_chmod_only_git_damage_and_metadata_change_reuse_prepared_install(self):
        flow=flow_module.InstallerFlow(); flow.setUp(); self.addCleanup(flow.doCleanups)
        calls=flow.base/'calls'
        flow.hook.write_text(flow.hook.read_text()+f'printf call >> "{calls}"\n')
        flow.assertSuccess(flow.run_install('install'))
        original=flow.base/'state/sources/test/demo'
        (original/'plugin').chmod(0o755)
        # A transport metadata change must affect integrity, not prepared output.
        (original/'.git/FETCH_HEAD').write_text('transport metadata, same source\n')
        result=flow.run_install('install')
        flow.assertSuccess(result)
        self.assertIn('Repository demo unchanged. Reusing local cache.',result.stdout)
        self.assertIn('Prepared cache reused: demo',result.stdout)
        self.assertEqual((original/'plugin').stat().st_mode & 0o111,0)
        self.assertEqual(calls.read_text(),'call')
        (original/'plugin').write_text('locally corrupted')
        result=flow.run_install('install'); flow.assertSuccess(result)
        self.assertIn('Refreshing local cache',result.stdout)
        self.assertEqual((flow.game/'addons/sourcemod/plugins/demo.smx').read_text(),'version1')
        self.assertEqual(calls.read_text(),'call')
