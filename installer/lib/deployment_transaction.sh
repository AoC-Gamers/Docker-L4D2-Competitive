#!/bin/bash
source "$DIR_INSTALLER_LIB/target_lock.sh"
source "$DIR_INSTALLER_LIB/instance_stack.sh"

stack_transaction_command() {
    python3 "$DIR_INSTALLER_LIB/transaction_stack.py" "$@"
}

stack_transaction_root() {
    local target_key
    target_key="$(printf '%s' "$(realpath -m "$DIR_LEFT4DEAD2")" | sha256sum | cut -d' ' -f1)"
    printf '%s/publication/%s\n' "$STATE_ROOT" "$target_key"
}

stack_quiesce_instances() {
    local executable name
    if [[ -n "${STACK_RECOVERED_RUNNING_FILE:-}" && -f "$STACK_RECOVERED_RUNNING_FILE" ]]; then
        local saved
        saved="$(cat "$STACK_RECOVERED_RUNNING_FILE")"
        printf '%s\n' "$saved" > "$STACK_TRANSACTION/running-instances"
    else
        : > "$STACK_TRANSACTION/running-instances"
    fi
    if [[ -f "$STACK_TRANSACTION/journal.json" ]]; then
        stack_transaction_command quiescing "$STACK_TRANSACTION"
    fi
    for executable in "${DIR_APP:-/app}/${GAMESERVER:-l4d2server}" "${DIR_APP:-/app}/${GAMESERVER:-l4d2server}"-*; do
        [[ -x "$executable" && -f "$executable" ]] || continue
        name="$(basename "$executable")"
        [[ "$name" == "${GAMESERVER:-l4d2server}" || "$name" =~ ^${GAMESERVER:-l4d2server}-[0-9]+$ ]] || continue
        if instance_is_running "$name"; then
            printf '%s\n' "$name" >> "$STACK_TRANSACTION/running-instances"
            sync -f "$STACK_TRANSACTION/running-instances"
            "$executable" stop
            if instance_is_running "$name"; then
                error_exit "Instance $name did not stop; publication refused."
            fi
        fi
    done
    sort -u -o "$STACK_TRANSACTION/running-instances" "$STACK_TRANSACTION/running-instances"
    sync -f "$STACK_TRANSACTION/running-instances"
}

stack_resume_instances() {
    local name
    [[ -f "$STACK_TRANSACTION/running-instances" ]] || return 0
    case "${L4D2_AUTOSTART:-true}" in
        [fF][aA][lL][sS][eE]|0|[nN][oO]|[oO][fF][fF])
        stack_finish_resume
        return 0 ;;
    esac
    while IFS= read -r name; do
        [[ -n "$name" ]] || continue
        if ! instance_is_running "$name"; then
            "${DIR_APP:-/app}/$name" start
        fi
    done < "$STACK_TRANSACTION/running-instances"
    stack_finish_resume
}

stack_finish_resume() {
    if [[ -f "$STACK_TRANSACTION/journal.json" ]]; then
        stack_transaction_command resumed "$STACK_TRANSACTION"
    fi
    : > "$STACK_TRANSACTION/running-instances"
}

stack_recover_interrupted() {
    STACK_TRANSACTION="$(stack_transaction_root)"
    stack_transaction_command migrate "$STACK_TRANSACTION" "$DIR_LEFT4DEAD2" "$STATE_ROOT"
    if [[ -f "$STACK_TRANSACTION/journal.json" ]]; then
        case "$(jq -r .phase "$STACK_TRANSACTION/journal.json")" in
            publishing|published)
                if [[ -f "${DEPLOY_STATE_FILE:-/nonexistent}" ]]; then
                    jq '.status="failed" | .recovery="publication incomplete; run recover_stack.sh explicitly"' "$DEPLOY_STATE_FILE" > "$DEPLOY_STATE_FILE.tmp"
                    mv "$DEPLOY_STATE_FILE.tmp" "$DEPLOY_STATE_FILE"
                fi
                error_exit "Publication incomplete. Instances must remain stopped; inspect $STACK_TRANSACTION and run recover_stack.sh explicitly."
                ;;
        esac
        # A crash after durable commit may precede payload cleanup. Finish it
        # here without rollback; preserve the receipt and resume intent.
        if [[ "$(jq -r .phase "$STACK_TRANSACTION/journal.json")" == committed ]]; then
            stack_transaction_command cleanup "$STACK_TRANSACTION"
            if [[ "$(jq -r '.resume_pending // false' "$STACK_TRANSACTION/journal.json")" == true ]]; then
                STACK_RECOVERED_RUNNING_FILE="$STACK_TRANSACTION/running-instances"
            fi
        fi
        case "$(jq -r .phase "$STACK_TRANSACTION/journal.json")" in
            prepared|rolled_back|abandoned)
                if [[ "$(jq -r '.resume_pending // false' "$STACK_TRANSACTION/journal.json")" == true ]]; then
                    STACK_RECOVERED_RUNNING_FILE="$STACK_TRANSACTION/running-instances"
                fi
                ;;
        esac
    fi
}

stack_prepare_transaction() {
    STACK_TRANSACTION="$(stack_transaction_root)"
    local saved=''
    if [[ -n "${STACK_RECOVERED_RUNNING_FILE:-}" && -f "$STACK_RECOVERED_RUNNING_FILE" ]]; then
        saved="$(cat "$STACK_RECOVERED_RUNNING_FILE")"
    fi
    # Entry guard refuses incomplete publication. No previous-tree backup or .last.
    rm -rf "$STACK_TRANSACTION"
    mkdir -p "$STACK_TRANSACTION/candidate/state"
    if [[ -n "$saved" ]]; then
        printf '%s\n' "$saved" > "$STACK_TRANSACTION/running-instances"
        STACK_RECOVERED_RUNNING_FILE="$STACK_TRANSACTION/running-instances"
    fi
    stack_transaction_command seed "$STACK_TRANSACTION" "$DIR_LEFT4DEAD2" "$STATE_ROOT"
}

stack_run_candidate() (
    export STACK_ACTIVE_GAME_ROOT="$DIR_LEFT4DEAD2"
    # All destination aliases, including parent-of-left4dead2 runtime libraries,
    # point inside the candidate. Caches and source workspaces remain separate.
    export LGSM_SERVERFILES="$STACK_TRANSACTION/candidate/serverfiles"
    export DIR_LEFT4DEAD2="$LGSM_SERVERFILES/left4dead2"
    export DIR_ADDONS="$DIR_LEFT4DEAD2/addons"
    export DIR_SOURCEMOD="$DIR_ADDONS/sourcemod"
    export DIR_CFG="$DIR_LEFT4DEAD2/cfg"
    export DIR_INSTALLER_STATE="$STACK_TRANSACTION/candidate/state"
    export OPTIONAL_OVERLAY_STATE_DIR="$DIR_INSTALLER_STATE/optional-overlays"
    export STACK_RUNTIME_REMOVALS_FILE="$STACK_TRANSACTION/candidate/runtime-removals.json"
    export STACK_PREPARING=true
    export STACK_HOOK_ASSETS_FILE="$DIR_INSTALLER_STATE/hook-assets.json"
    if [[ "${STACK_REUSE_SOURCES:-false}" == true && -f "$STATE_ROOT/hook-assets.json" ]]; then
        cp "$STATE_ROOT/hook-assets.json" "$STACK_HOOK_ASSETS_FILE"
    fi
    export STACK_PREPARED_HOOK_ASSETS=true
    apply_stack_sources
    python3 "$DIR_INSTALLER_LIB/final_policy.py" "$DIR_LEFT4DEAD2" "$DIR_STACK/final-policy.json"
    python3 "$DIR_INSTALLER_LIB/merge_local_configs.py" "$DIR_LEFT4DEAD2" "$STACK_ACTIVE_GAME_ROOT" "$STATE_ROOT" "$STACK_TRANSACTION/config-default-hashes.json"
    python3 "$DIR_INSTALLER_LIB/final_policy.py" "$DIR_LEFT4DEAD2" "$DIR_STACK/final-policy.json"
    python3 "$DIR_INSTALLER_LIB/validate_candidate.py" "$DIR_LEFT4DEAD2"
    bash "$DIR_INSTALLER_BIN/geoip_update.sh"
)

stack_publish_transaction() {
    export STACK_PUBLICATION_FINALIZES_DEPLOY_STATE="${INSTALLER_MANAGED_DEPLOY_STATE:-false}"
    stack_transaction_command plan "$STACK_TRANSACTION" "$DIR_LEFT4DEAD2" "$DIR_STACK" "$DIR_INSTALLER_CONFIG" "$STATE_ROOT"
    stack_quiesce_instances
    if ! stack_transaction_command publish "$STACK_TRANSACTION"; then
        return 1
    fi
    # Sync runs while consumers are stopped. A failure leaves a recoverable published journal.
    bash "$DIR_INSTALLER_BIN/sync_instances.sh" "${L4D2_ADDITIONAL_INSTANCES:-$(state_read_additional_instances)}"
    stack_run_extension after-sync
    stack_transaction_command commit "$STACK_TRANSACTION"
    if [[ "${STACK_DEFER_RESUME:-false}" != true ]]; then stack_resume_instances; fi
}

stack_handle_transaction_failure() {
    local phase
    phase="$(jq -r .phase "$STACK_TRANSACTION/journal.json")"
    case "$phase" in
        publishing|published)
            warn "Publication incomplete: prepared material retained in $STACK_TRANSACTION. No rollback or automatic restart; run recover_stack.sh explicitly."
            ;;
        prepared) stack_resume_instances ;;
    esac
}
