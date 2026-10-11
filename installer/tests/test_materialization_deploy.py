import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

INSTALLER=Path(__file__).resolve().parents[1]
class DeploymentDecision(unittest.TestCase):
    def test_identical_skips_hook_change_reapplies_without_remote_update(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); stack=root/'stack'; (stack/'hooks').mkdir(parents=True); (stack/'profiles').mkdir(); (stack/'manifests').mkdir()
            (stack/'hooks/demo.default.sh').write_text('# hook v1\n')
            (stack/'profiles/test.json').write_text('{"components":["demo"]}')
            (stack/'manifests/components.json').write_text('{"demo":{"folder":"demo","source_type":"hook_only","branch":"default"}}')
            env=dict(os.environ,DIR_INSTALLER=str(root/'installer'),DIR_INSTALLER_BIN=str(INSTALLER/'bin'),DIR_INSTALLER_LIB=str(INSTALLER/'lib'),DIR_INSTALLER_CONFIG=str(INSTALLER/'config'),DIR_INSTALLER_STATE=str(root/'state'),DIR_STACK=str(stack),DIR_STACK_HOOKS=str(stack/'hooks'),DIR_LEFT4DEAD2=str(root/'game'),GAMESERVER='l4d2server',LGSM_CONFIG=str(root/'cfg'),LGSM_SERVERFILES=str(root/'serverfiles'),STACK_PROFILE='test',L4D2_STACK_AUTOUPDATE='false')
            script='''set -euo pipefail
source "$DIR_INSTALLER_BIN/deploy_stack.sh"
resolve_target_stack_metadata
mkdir -p "$STATE_HISTORY_DIR/previous"
PREVIOUS_DEPLOYMENT_ID=previous
jq -n --arg hash "$TARGET_RESOLVED_COMPONENTS_SHA256" --arg logic "$TARGET_MATERIALIZATION_SHA256" '{status:"ready",stack:{profile:"test",resolved_components_sha256:$hash,materialization_sha256:$logic}}' > "$STATE_HISTORY_DIR/previous/deploy-state.json"
if stack_requires_reapply; then echo 'identical reapplied' >&2; exit 1; fi
printf '# changed\\n' >> "$DIR_STACK_HOOKS/demo.default.sh"
resolve_target_stack_metadata
stack_requires_reapply
# apply_stack_if_needed must propagate reuse-only to the nested installer.
bash() { [[ "$STACK_REUSE_SOURCES" == true && "$1" == "$DIR_INSTALLER_BIN/install_stack.sh" ]]; }
apply_stack_if_needed
'''
            result=subprocess.run(['bash','-c',script],env=env,capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
