#!/bin/bash
# Explicit operator retry: use the retained candidate, without fetching or hooks.
set -euo pipefail
source "$DIR_INSTALLER_LIB/tools_stack.sh"
source "$DIR_INSTALLER_LIB/state_stack.sh"
source "$DIR_INSTALLER_LIB/deployment_transaction.sh"
source "$DIR_INSTALLER_LIB/extensions_stack.sh"
state_init_paths
stack_acquire_target_lock
retry_exit() {
    local result=$?
    if [[ "$result" != 0 && -f "$DEPLOY_STATE_FILE" ]]; then
        state_finalize_deploy_state failed false '"manual publication retry failed"' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    fi
}
trap retry_exit EXIT
STACK_TRANSACTION="$(stack_transaction_root)"
stack_transaction_command migrate "$STACK_TRANSACTION" "$DIR_LEFT4DEAD2" "$STATE_ROOT"
[[ -f "$STACK_TRANSACTION/journal.json" ]] || { info 'No publication to retry.'; exit 0; }
phase="$(jq -r .phase "$STACK_TRANSACTION/journal.json")"
schema="$(jq -r .schema_version "$STACK_TRANSACTION/journal.json")"
case "${1:-retry}" in retry|rebuild) ;; *) error_exit 'Use recover_stack.sh [retry|rebuild].' ;; esac
if [[ "$schema" == 1 && ( "$phase" == publishing || "$phase" == published ) ]]; then
    # A pre-migration interruption already has a rollback journal. Honor it once.
    STACK_RECOVERED_RUNNING_FILE="$STACK_TRANSACTION/running-instances"
    stack_quiesce_instances
    stack_transaction_command recover-legacy "$STACK_TRANSACTION"
    warn 'Legacy previous files restored. Run install_stack.sh to validate and synchronize before starting instances.'
    exit 1
fi
if [[ "${1:-retry}" == rebuild ]]; then
    [[ "$phase" != committed ]] || error_exit 'Committed publication does not need rebuilding.'
    STACK_RECOVERED_RUNNING_FILE="$STACK_TRANSACTION/running-instances"
    stack_quiesce_instances
    stack_transaction_command abandon "$STACK_TRANSACTION"
    state_finalize_deploy_state failed false '"publication abandoned; rebuild required"' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    info 'Candidate abandoned explicitly. Run install_stack.sh to prepare and publish again; instances remain stopped.'
    exit 0
fi
case "$phase" in
    committed)
        stack_transaction_command cleanup "$STACK_TRANSACTION"
        if [[ "$(jq -r '.resume_pending // false' "$STACK_TRANSACTION/journal.json")" == true ]]; then stack_resume_instances; fi
        info 'Publication already committed.'; exit 0 ;;
    prepared|publishing|published) ;;
    *) error_exit 'No retryable candidate. Run install_stack.sh to build a new one.' ;;
esac
[[ "$schema" == 2 ]] || error_exit 'Legacy candidate requires a new install_stack.sh run.'
expected="$(jq -r '.logic_sha256 // ""' "$STACK_TRANSACTION/journal.json")"
actual="$(python3 "$DIR_INSTALLER_LIB/materialization.py" "$DIR_STACK" "$DIR_INSTALLER_LIB" "$DIR_INSTALLER_BIN" "$DIR_INSTALLER_CONFIG" "${DIR_APP:-/app}/container")"
[[ -z "$expected" || "$actual" == "$expected" ]] || error_exit 'Preparation logic changed. Use recover_stack.sh rebuild, then install_stack.sh.'
stack_validate_extensions
python3 "$DIR_INSTALLER_LIB/validate_candidate.py" "$STACK_TRANSACTION/candidate/serverfiles/left4dead2"
STACK_RECOVERED_RUNNING_FILE="$STACK_TRANSACTION/running-instances"
stack_quiesce_instances
stack_transaction_command publish "$STACK_TRANSACTION"
bash "$DIR_INSTALLER_BIN/sync_instances.sh" "${L4D2_ADDITIONAL_INSTANCES:-$(state_read_additional_instances)}"
stack_run_extension after-sync
stack_transaction_command commit "$STACK_TRANSACTION"
stack_resume_instances
state_finalize_deploy_state ready false null "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
info 'Prepared publication retried and committed successfully.'
