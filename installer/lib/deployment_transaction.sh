#!/bin/bash
source "$DIR_INSTALLER_LIB/target_lock.sh"
source "$DIR_INSTALLER_LIB/instance_stack.sh"

stack_transaction_command() {
    python3 "$DIR_INSTALLER_LIB/transaction_stack.py" "$@"
}

stack_transaction_root() {
    # Same filesystem as the live tree: publication uses renames, never cross-device moves.
    printf '%s/.stack-transaction\n' "$(dirname "$(realpath -m "$DIR_LEFT4DEAD2")")"
}

stack_quiesce_instances() {
    local executable name
    if [[ -n "${STACK_RECOVERED_RUNNING_FILE:-}" && -f "$STACK_RECOVERED_RUNNING_FILE" ]]; then
        cp "$STACK_RECOVERED_RUNNING_FILE" "$STACK_TRANSACTION/running-instances"
    else
        : > "$STACK_TRANSACTION/running-instances"
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
    case "${L4D2_AUTOSTART:-true}" in false|0|no|off) return 0 ;; esac
    while IFS= read -r name; do
        [[ -n "$name" ]] || continue
        if ! instance_is_running "$name"; then
            "${DIR_APP:-/app}/$name" start
        fi
    done < "$STACK_TRANSACTION/running-instances"
}

stack_recover_interrupted() {
    STACK_TRANSACTION="$(stack_transaction_root)"
    if [[ -f "$STACK_TRANSACTION/journal.json" ]]; then
        case "$(jq -r .phase "$STACK_TRANSACTION/journal.json")" in
            publishing|published)
                # A killed publisher may have left a mixed tree. Stop before restoring.
                # Preserve the original resume list across recovery.
                cp "$STACK_TRANSACTION/running-instances" "$STACK_TRANSACTION/resume.saved" 2>/dev/null || true
                stack_quiesce_instances
                mv "$STACK_TRANSACTION/resume.saved" "$STACK_TRANSACTION/running-instances" 2>/dev/null || true
                stack_transaction_command recover "$STACK_TRANSACTION"
                # Do not resume here: instance layouts/reconciliation still need to run.
                ;;
        esac
        case "$(jq -r .phase "$STACK_TRANSACTION/journal.json")" in
            prepared|rolled_back)
                STACK_RECOVERED_RUNNING_FILE="$STACK_TRANSACTION/running-instances"
                ;;
        esac
    fi
}

stack_prepare_transaction() {
    STACK_TRANSACTION="$(stack_transaction_root)"
    if [[ -d "$STACK_TRANSACTION" ]]; then
        rm -rf "${STACK_TRANSACTION}.last"
        mv "$STACK_TRANSACTION" "${STACK_TRANSACTION}.last"
        if [[ -n "${STACK_RECOVERED_RUNNING_FILE:-}" ]]; then
            STACK_RECOVERED_RUNNING_FILE="${STACK_TRANSACTION}.last/running-instances"
        fi
    fi
    mkdir -p "$STACK_TRANSACTION/candidate/state"
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
    apply_stack_sources
    python3 "$DIR_INSTALLER_LIB/final_policy.py" "$DIR_LEFT4DEAD2" "$DIR_STACK/final-policy.json"
    python3 "$DIR_INSTALLER_LIB/merge_local_configs.py" "$DIR_LEFT4DEAD2" "$STACK_ACTIVE_GAME_ROOT" "$STATE_ROOT" "$STACK_TRANSACTION/config-default-hashes.json"
    python3 "$DIR_INSTALLER_LIB/final_policy.py" "$DIR_LEFT4DEAD2" "$DIR_STACK/final-policy.json"
    python3 "$DIR_INSTALLER_LIB/validate_candidate.py" "$DIR_LEFT4DEAD2"
    bash "$DIR_INSTALLER_BIN/geoip_update.sh"
)

stack_publish_transaction() {
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
            stack_transaction_command recover "$STACK_TRANSACTION" || return 1
            bash "$DIR_INSTALLER_BIN/sync_instances.sh" "${L4D2_ADDITIONAL_INSTANCES:-$(state_read_additional_instances)}" || return 1
            stack_run_extension after-sync || return 1
            stack_resume_instances
            ;;
        prepared) stack_resume_instances ;;
    esac
}
