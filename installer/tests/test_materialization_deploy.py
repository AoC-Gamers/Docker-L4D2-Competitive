"""Automatic deployment respects the toggle without claiming unapplied changes."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

INSTALLER = Path(__file__).resolve().parents[1]


class DeploymentDecision(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        stack = self.root / 'stack'
        for name in ('hooks', 'profiles', 'manifests'):
            (stack / name).mkdir(parents=True, exist_ok=True)
        (stack / 'hooks/demo.default.sh').write_text('# hook v1\n')
        (stack / 'profiles/test.json').write_text('{"components":["demo"]}')
        (stack / 'manifests/components.json').write_text(
            '{"demo":{"folder":"demo","source_type":"hook_only","branch":"default"}}')
        self.env = dict(os.environ, DIR_INSTALLER=str(self.root / 'installer'),
                        DIR_INSTALLER_BIN=str(INSTALLER / 'bin'), DIR_INSTALLER_LIB=str(INSTALLER / 'lib'),
                        DIR_INSTALLER_CONFIG=str(INSTALLER / 'config'), DIR_INSTALLER_STATE=str(self.root / 'state'),
                        DIR_APP=str(self.root / 'app'), DIR_STACK=str(stack), DIR_STACK_HOOKS=str(stack / 'hooks'),
                        DIR_LEFT4DEAD2=str(self.root / 'game'), GAMESERVER='l4d2server',
                        LGSM_CONFIG=str(self.root / 'cfg'), LGSM_SERVERFILES=str(self.root / 'serverfiles'),
                        STACK_PROFILE='test', L4D2_STACK_AUTOUPDATE='false')

    def run_shell(self, body, baseline=True):
        setup = '''set -euo pipefail
source "$DIR_INSTALLER_BIN/deploy_stack.sh"
resolve_target_stack_metadata
'''
        if baseline:
            setup += '''state_create_deploy_state previous "" ready "$STACK_PROFILE" "$STATE_RESOLVED_COMPONENTS_FILE" "" "$GAMESERVER"
record_target_stack_metadata
state_finalize_deploy_state ready false null
printf '{"fixed":"original"}\\n' > "$STATE_ROOT/source-lock.json"
DEPLOYMENT_ID=current
initialize_deploy_state
'''
        return subprocess.run(['bash', '-c', setup + body], env=self.env,
                              capture_output=True, text=True, timeout=15)

    def assertSuccess(self, result):
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_disabled_identical_skips_without_pending_change(self):
        self.assertSuccess(self.run_shell('''
if stack_requires_reapply; then exit 21; fi
bash() { error_exit "unexpected installer call"; }
apply_stack_if_needed
run_stack_autoupdate_before_start
finalize_deploy_state
DEPLOY_STATE_INITIALIZED=false
jq -e '.status=="ready" and .stack.automatic_apply_skipped and (.stack|has("pending")|not)' "$DEPLOY_STATE_FILE"
'''))
        self.assertFalse((self.root / 'installer/cache').exists())

    def test_disabled_changes_stay_pending_and_installed_metadata_survives_restarts(self):
        result = self.run_shell('''
old_logic="$TARGET_MATERIALIZATION_SHA256"
old_definition="$TARGET_RESOLVED_COMPONENTS_SHA256"
printf '# new hook\\n' >> "$DIR_STACK_HOOKS/demo.default.sh"
printf '{"remove":{}}\\n' > "$DIR_STACK/final-policy.json"
cp "$DIR_STACK/profiles/test.json" "$DIR_STACK/profiles/other.json"
STACK_PROFILE=other
resolve_target_stack_metadata
stack_requires_reapply
bash() { error_exit "unexpected installer call"; }
apply_stack_if_needed
finalize_deploy_state
DEPLOY_STATE_INITIALIZED=false
jq -e --arg logic "$old_logic" --arg definition "$old_definition" '
 .status=="ready" and .stack.profile=="test" and .stack.materialization_sha256==$logic and
 .stack.resolved_components_sha256==$definition and .stack.pending.profile=="other" and
 .stack.pending.materialization_sha256!=$logic' "$DEPLOY_STATE_FILE"
# A subsequent boot must still see the changes; skipping cannot adopt them.
DEPLOYMENT_ID=second
initialize_deploy_state
resolve_target_stack_metadata
stack_requires_reapply
apply_stack_if_needed
finalize_deploy_state
DEPLOY_STATE_INITIALIZED=false
jq -e '.stack.profile=="test" and .stack.pending.profile=="other"' "$DEPLOY_STATE_FILE"
''')
        self.assertSuccess(result)
        self.assertIn('Skipping stack acquisition, preparation and publication', result.stdout)
        self.assertIn('Stack changes remain pending', result.stdout)
        self.assertEqual(json.loads((self.root / 'state/source-lock.json').read_text()), {'fixed': 'original'})
        self.assertFalse((self.root / 'installer/cache').exists())

    def test_enabled_change_calls_installer_once_with_remote_checks(self):
        self.assertSuccess(self.run_shell('''
L4D2_STACK_AUTOUPDATE=true
printf '# new hook\\n' >> "$DIR_STACK_HOOKS/demo.default.sh"
resolve_target_stack_metadata
bash() {
 [[ "$1" == "$DIR_INSTALLER_BIN/install_stack.sh" && "$2" == update && "$STACK_REUSE_SOURCES" == false ]]
 printf call >> "$STATE_ROOT/installer-calls"
}
apply_stack_if_needed
run_stack_autoupdate_before_start
test "$(cat "$STATE_ROOT/installer-calls")" = call
jq -e --arg logic "$TARGET_MATERIALIZATION_SHA256" '.stack.materialization_sha256==$logic and (.stack|has("pending")|not)' "$DEPLOY_STATE_FILE"
'''))

    def test_first_install_still_creates_stack_when_automatic_update_is_disabled(self):
        self.assertSuccess(self.run_shell('''
initialize_deploy_state
L4D2_FRESH_INSTALL=true
bash() { [[ "$1" == "$DIR_INSTALLER_BIN/install_stack.sh" && "$2" == install ]]; }
apply_stack_if_needed
test "$STACK_UPDATED_DURING_DEPLOY" = true
''', baseline=False))

    def test_failed_previous_deployment_does_not_become_ready_by_skipping(self):
        result = self.run_shell('''
jq '.status="failed"' "$STATE_HISTORY_DIR/previous/deploy-state.json" > "$STATE_ROOT/failed.json"
mv "$STATE_ROOT/failed.json" "$STATE_HISTORY_DIR/previous/deploy-state.json"
apply_stack_if_needed
''')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('no ready deployment', result.stderr)
        self.assertEqual(json.loads((self.root / 'state/current/deploy-state.json').read_text())['status'], 'failed')

    def test_confirmed_publication_can_continue_without_reinstalling_after_recovery(self):
        self.assertSuccess(self.run_shell('''
jq '.status="failed"' "$STATE_HISTORY_DIR/previous/deploy-state.json" > "$STATE_ROOT/failed.json"
mv "$STATE_ROOT/failed.json" "$STATE_HISTORY_DIR/previous/deploy-state.json"
receipt="$(stack_transaction_root)/journal.json"
mkdir -p "$(dirname "$receipt")"
jq -n --arg logic "$TARGET_MATERIALIZATION_SHA256" '{schema_version:2,phase:"committed",deployment_id:"previous",logic_sha256:$logic}' > "$receipt"
bash() { error_exit "unexpected installer call"; }
apply_stack_if_needed
test "$STACK_APPLY_SKIPPED" = true
# Skipping alone cannot mark the unfinished runtime phases ready.
jq -e '.status=="preparing"' "$DEPLOY_STATE_FILE"
DEPLOY_STATE_INITIALIZED=false
'''))

    def test_unconfirmed_or_mismatched_receipt_cannot_skip_failed_deployment(self):
        for phase, deployment, logic in [('published', 'previous', 'match'),
                                         ('committed', 'older', 'match'),
                                         ('committed', 'previous', 'wrong')]:
            with self.subTest(phase=phase, deployment=deployment, logic=logic):
                result = self.run_shell('''
jq '.status="failed"' "$STATE_HISTORY_DIR/previous/deploy-state.json" > "$STATE_ROOT/failed.json"
mv "$STATE_ROOT/failed.json" "$STATE_HISTORY_DIR/previous/deploy-state.json"
receipt="$(stack_transaction_root)/journal.json"
mkdir -p "$(dirname "$receipt")"
''' + f'phase={phase}\ndeployment={deployment}\nlogic={logic}\n' + '''
if [[ "$logic" == match ]]; then logic="$TARGET_MATERIALIZATION_SHA256"; fi
jq -n --arg phase "$phase" --arg deployment "$deployment" --arg logic "$logic" '{schema_version:2,phase:$phase,deployment_id:$deployment,logic_sha256:$logic}' > "$receipt"
apply_stack_if_needed
''')
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('Complete publication recovery', result.stderr)

    def test_existing_valve_install_without_stack_receipt_requires_manual_install(self):
        result = self.run_shell('initialize_deploy_state\napply_stack_if_needed\n', baseline=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('install_stack.sh install/update explicitly', result.stderr)

    def test_missing_or_corrupt_installed_definition_fails_without_relabeling(self):
        result = self.run_shell('''
printf '[]\\n' > "$STATE_HISTORY_DIR/previous/resolved-components.json"
apply_stack_if_needed
''')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Cannot verify installed stack metadata', result.stderr)
        self.assertEqual(json.loads((self.root / 'state/current/deploy-state.json').read_text())['status'], 'failed')
