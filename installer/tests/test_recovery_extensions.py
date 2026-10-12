"""Recovery reruns after-sync extensions, but not source acquisition or hooks."""
import json
import shutil
import unittest

import test_installer_flow as flow_module


class RecoveryExtensions(unittest.TestCase):
    def test_retry_repeats_after_sync_only_and_stays_failed_until_it_succeeds(self):
        flow = flow_module.InstallerFlow()
        flow.setUp()
        self.addCleanup(flow.doCleanups)

        extension_dir = flow.app / 'container/extensions'
        extension_dir.mkdir(parents=True)
        extension_calls = flow.base / 'after-sync-calls'
        component_calls = flow.base / 'component-hook-calls'
        extension = extension_dir / 'after-sync.sh'
        extension.write_text(f'''#!/bin/bash
set -euo pipefail
calls=0
[[ ! -f "{extension_calls}" ]] || calls=$(cat "{extension_calls}")
calls=$((calls + 1))
printf '%s' "$calls" > "{extension_calls}"
[[ "$calls" != 2 ]] || exit 23
''')
        flow.hook.write_text(flow.hook.read_text() + f'printf call >> "{component_calls}"\n')

        flow.assertSuccess(flow.run_install('install'))
        self.assertEqual(extension_calls.read_text(), '1')
        self.assertEqual(component_calls.read_text(), 'call')

        flow.hook.write_text(flow.hook.read_text() +
                             'printf version2 > "$DIR_SOURCEMOD/plugins/demo.smx"\n')
        update = flow.run_install('update')
        self.assertNotEqual(update.returncode, 0, update.stdout + update.stderr)
        transaction = flow.publication()
        state_path = flow.base / 'state/current/deploy-state.json'
        failed_state = json.loads(state_path.read_text())
        failed_journal = json.loads((transaction / 'journal.json').read_text())
        self.assertEqual(failed_state['status'], 'failed')
        self.assertEqual(failed_journal['phase'], 'published')
        self.assertEqual(extension_calls.read_text(), '2')
        self.assertEqual(component_calls.read_text(), 'callcall')
        self.assertEqual((flow.game / 'addons/sourcemod/plugins/demo.smx').read_text(), 'version2')

        # The retained candidate must recover without consulting the deleted Git source.
        shutil.rmtree(flow.source)
        retry = flow.retry()
        flow.assertSuccess(retry)

        committed = json.loads((transaction / 'journal.json').read_text())
        ready_state = json.loads(state_path.read_text())
        self.assertEqual(extension_calls.read_text(), '3')
        self.assertEqual(component_calls.read_text(), 'callcall')
        self.assertEqual(committed['phase'], 'committed')
        self.assertEqual(ready_state['status'], 'ready')
        self.assertEqual((flow.game / 'addons/sourcemod/plugins/demo.smx').read_text(), 'version2')


if __name__ == '__main__':
    unittest.main()
