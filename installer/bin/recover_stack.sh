#!/bin/bash
# Explicit retry: retain sources/component effects; after-sync extensions rerun.
set -euo pipefail
source "$DIR_INSTALLER_LIB/tools_stack.sh"
source "$DIR_INSTALLER_LIB/state_stack.sh"
source "$DIR_INSTALLER_LIB/deployment_transaction.sh"
source "$DIR_INSTALLER_LIB/extensions_stack.sh"
state_init_paths
stack_acquire_target_lock
RECOVERY_ACTIVE=false
RECOVERY_DEPLOYMENT_ID=""

publication_update_deploy_state() {
    local status="$1" last_error="$2" current_deployment_id completed_at
    [[ "$RECOVERY_ACTIVE" == true && -n "$RECOVERY_DEPLOYMENT_ID" && -f "$DEPLOY_STATE_FILE" ]] || return 0
    current_deployment_id="$(state_get_current_deployment_id)"
    [[ "$RECOVERY_DEPLOYMENT_ID" == "$current_deployment_id" ]] || return 0
    completed_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    jq --arg status "$status" --arg error "$last_error" --arg completed_at "$completed_at" \
        '.status=$status | .timestamps.completed_at=$completed_at | .last_error=(if $error == "" then null else $error end)' \
        "$DEPLOY_STATE_FILE" > "$DEPLOY_STATE_FILE.tmp"
    mv "$DEPLOY_STATE_FILE.tmp" "$DEPLOY_STATE_FILE"
    state_archive_snapshot "$current_deployment_id"
}

retry_exit() {
    local result=$?
    if [[ "$result" != 0 && "$RECOVERY_ACTIVE" == true ]]; then
        publication_update_deploy_state failed 'manual publication retry failed'
    fi
}

complete_committed_publication() {
    local finalizes_deploy_state publication_deployment_id current_deployment_id
    stack_transaction_command cleanup "$STACK_TRANSACTION"
    finalizes_deploy_state="$(jq -r '.finalizes_deploy_state // false' "$STACK_TRANSACTION/journal.json")"
    publication_deployment_id="$(jq -r '.deployment_id // empty' "$STACK_TRANSACTION/journal.json")"
    current_deployment_id="$(state_get_current_deployment_id)"
    if [[ "$finalizes_deploy_state" == true && -n "$publication_deployment_id" && "$publication_deployment_id" == "$current_deployment_id" ]]; then
        if [[ "$(jq -r '.resume_pending // false' "$STACK_TRANSACTION/journal.json")" == true ]]; then
            stack_resume_instances
        fi
        publication_update_deploy_state ready ''
        info 'Publication already committed and standalone deployment finalized.'
    else
        info 'Publication committed. Complete deploy_stack.sh before resuming instances or declaring the deployment ready.'
    fi
}

trap retry_exit EXIT
case "${1:-retry}" in retry|rebuild) ;; *) error_exit 'Use recover_stack.sh [retry|rebuild].' ;; esac
STACK_TRANSACTION="$(stack_transaction_root)"
stack_transaction_command migrate "$STACK_TRANSACTION" "$DIR_LEFT4DEAD2" "$STATE_ROOT"
[[ -f "$STACK_TRANSACTION/journal.json" ]] || { info 'No publication to retry.'; exit 0; }
phase="$(jq -r .phase "$STACK_TRANSACTION/journal.json")"
schema="$(jq -r .schema_version "$STACK_TRANSACTION/journal.json")"
RECOVERY_DEPLOYMENT_ID="$(jq -r '.deployment_id // empty' "$STACK_TRANSACTION/journal.json")"
# A retained, uncommitted publication belongs to the deployment that prepared
# it. Never let retry/rebuild mutate the live tree after a newer deployment
# has taken ownership. Old committed receipts are informational and are handled
# below without resuming or finalizing a mismatched deployment.
if [[ "$phase" != committed && -n "$RECOVERY_DEPLOYMENT_ID" ]]; then
    current_deployment_id="$(state_get_current_deployment_id)"
    [[ "$RECOVERY_DEPLOYMENT_ID" == "$current_deployment_id" ]] || error_exit \
        'Publication belongs to a different deployment. Refusing retry or rebuild.'
fi
if [[ "$schema" == 1 && ( "$phase" == publishing || "$phase" == published ) ]]; then
    # A pre-migration interruption already has a rollback journal. Honor it once.
    RECOVERY_ACTIVE=true
    STACK_RECOVERED_RUNNING_FILE="$STACK_TRANSACTION/running-instances"
    stack_quiesce_instances
    stack_transaction_command recover-legacy "$STACK_TRANSACTION"
    warn 'Legacy previous files restored. Run install_stack.sh to validate and synchronize before starting instances.'
    exit 1
fi
if [[ "${1:-retry}" == rebuild ]]; then
    [[ "$phase" != committed ]] || error_exit 'Committed publication does not need rebuilding.'
    RECOVERY_ACTIVE=true
    STACK_RECOVERED_RUNNING_FILE="$STACK_TRANSACTION/running-instances"
    stack_quiesce_instances
    stack_transaction_command abandon "$STACK_TRANSACTION"
    publication_update_deploy_state failed 'publication abandoned; rebuild required'
    info 'Candidate abandoned explicitly. Run install_stack.sh to prepare and publish again; instances remain stopped.'
    exit 0
fi
case "$phase" in
    committed)
        RECOVERY_ACTIVE=true
        complete_committed_publication; exit 0 ;;
    prepared|publishing|published) ;;
    *) error_exit 'No retryable candidate. Run install_stack.sh to build a new one.' ;;
esac
[[ "$schema" == 2 ]] || error_exit 'Legacy candidate requires a new install_stack.sh run.'
RECOVERY_ACTIVE=true
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
complete_committed_publication
