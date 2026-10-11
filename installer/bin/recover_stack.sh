#!/bin/bash
# Recovery-only command: no remote resolution and no Valve update.
set -euo pipefail
source "$DIR_INSTALLER_LIB/tools_stack.sh"
source "$DIR_INSTALLER_LIB/state_stack.sh"
source "$DIR_INSTALLER_LIB/deployment_transaction.sh"
source "$DIR_INSTALLER_LIB/extensions_stack.sh"
state_init_paths
stack_acquire_target_lock
STACK_TRANSACTION="$(stack_transaction_root)"
[[ -f "$STACK_TRANSACTION/journal.json" ]] || { info 'No publication journal to recover.'; exit 0; }
phase="$(jq -r .phase "$STACK_TRANSACTION/journal.json")"
case "$phase" in
    committed)
        stack_recover_interrupted
        if [[ "$(jq -r '.resume_pending // false' "$STACK_TRANSACTION/journal.json")" == true ]]; then stack_resume_instances; fi
        info 'Publication is committed; recovery payload cleaned.'; exit 0 ;;
    rolled_back) info "Publication is already $phase."; exit 0 ;;
    prepared)
        stack_resume_instances
        ;;
    publishing|published)
        stack_recover_interrupted
        bash "$DIR_INSTALLER_BIN/sync_instances.sh" "${L4D2_ADDITIONAL_INSTANCES:-$(state_read_additional_instances)}"
        stack_run_extension after-sync
        stack_resume_instances
        ;;
    *) error_exit 'Unknown publication phase; preserve the journal for inspection.' ;;
esac
if [[ -f "$DEPLOY_STATE_FILE" ]]; then
    jq '.status="failed" | .recovery="previous files restored; run install_stack/deploy_stack to validate the intended stack"' "$DEPLOY_STATE_FILE" > "$DEPLOY_STATE_FILE.tmp"
    mv "$DEPLOY_STATE_FILE.tmp" "$DEPLOY_STATE_FILE"
fi
info 'Recovery completed. Deployment remains failed until a full validated deployment succeeds.'
