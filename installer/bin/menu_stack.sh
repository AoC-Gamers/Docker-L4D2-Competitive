#!/bin/bash
set -euo pipefail

if ! command -v jq &> /dev/null; then
    echo -e "\e[31mError:\e[0m jq no esta instalado."
    exit 1
fi

source "$DIR_INSTALLER_LIB/tools_stack.sh"
source "$DIR_INSTALLER_LIB/state_stack.sh"
source "$DIR_INSTALLER_LIB/instance_stack.sh"

: "${DIR_INSTALLER_BIN:?DIR_INSTALLER_BIN no esta definido.}"
: "${DIR_INSTALLER_LIB:?DIR_INSTALLER_LIB no esta definido.}"
: "${DIR_APP:?DIR_APP no esta definido.}"
: "${GAMESERVER:?GAMESERVER no esta definido.}"

state_init_paths
source "$DIR_INSTALLER_LIB/target_lock.sh"
stack_acquire_target_lock

render_kv() {
    printf '%-28s %s\n' "$1" "$2"
}

print_runtime_panel() {
    section "Runtime status"
    render_kv "Primary instance" "$GAMESERVER"
    render_kv "Detected instances" "$TOTAL_SERVERS"
    render_kv "Additional instances" "$(( TOTAL_SERVERS - 1 ))"

    if [[ -f "$DEPLOY_STATE_FILE" ]]; then
        render_kv "Deployment ID" "$(jq -r '.deployment_id // "n/a"' "$DEPLOY_STATE_FILE")"
        render_kv "Previous deployment" "$(jq -r '.previous_deployment_id // "n/a"' "$DEPLOY_STATE_FILE")"
        render_kv "Deployment status" "$(jq -r '.status // "unknown"' "$DEPLOY_STATE_FILE")"
        render_kv "Stack profile" "$(jq -r '.stack.profile // "default"' "$DEPLOY_STATE_FILE")"
        render_kv "Completed at" "$(jq -r '.timestamps.completed_at // "pending"' "$DEPLOY_STATE_FILE")"
    else
        render_kv "Deployment status" "not available"
    fi
}

show_deploy_state_summary() {
    if [[ ! -f "$DEPLOY_STATE_FILE" ]]; then
        warn "Deployment state is not available"
        return
    fi

    section "Deployment summary"
    render_kv "Deployment ID" "$(jq -r '.deployment_id // "n/a"' "$DEPLOY_STATE_FILE")"
    render_kv "Previous deployment" "$(jq -r '.previous_deployment_id // "n/a"' "$DEPLOY_STATE_FILE")"
    render_kv "Status" "$(jq -r '.status // "unknown"' "$DEPLOY_STATE_FILE")"
    render_kv "Profile" "$(jq -r '.stack.profile // "default"' "$DEPLOY_STATE_FILE")"
    render_kv "Completed at" "$(jq -r '.timestamps.completed_at // "pending"' "$DEPLOY_STATE_FILE")"
}

TOTAL_SERVERS=$(instance_calculate_total)

if [[ -f "$INSTANCES_STATE_FILE" ]]; then
    if jq -e 'has("additional_instances")' "$INSTANCES_STATE_FILE" &>/dev/null; then
        ADDITIONAL_INSTANCES=$(state_read_additional_instances)
        CURRENT_ADDITIONAL_INSTANCES=$(( TOTAL_SERVERS - 1 ))

        if [[ $ADDITIONAL_INSTANCES -ne $CURRENT_ADDITIONAL_INSTANCES ]]; then
            warn "Detected instance-state mismatch. Running instance synchronization."
            "$DIR_INSTALLER_BIN/sync_instances.sh" "$ADDITIONAL_INSTANCES"
            info "Recalculating detected instances after synchronization."
            TOTAL_SERVERS=$(instance_calculate_total)
        fi
    else
        warn "The instances-state JSON does not contain the additional_instances field."
    fi
fi

menu() {
    section "Stack menu"
    render_kv "1" "Start"
    render_kv "2" "Stop"
    render_kv "3" "Restart"
    render_kv "4" "Automatic update"
    render_kv "5" "Manual update"
    render_kv "*" "Exit"
}

start_servers() {
    local start_range=$1 end_range=$2
    instance_for_each_in_range "$start_range" "$end_range" start_instance_callback
    bash "$DIR_INSTALLER_BIN/runtime_intent.sh" capture
}

stop_servers() {
    local start_range=$1 end_range=$2
    instance_for_each_in_range "$start_range" "$end_range" stop_instance_callback
    bash "$DIR_INSTALLER_BIN/runtime_intent.sh" capture
    success "Stop operation completed"
}

restart_servers() {
    local start_range=$1 end_range=$2
    instance_for_each_in_range "$start_range" "$end_range" restart_instance_callback
    bash "$DIR_INSTALLER_BIN/runtime_intent.sh" capture
    success "Restart operation completed"
}

start_instance_callback() {
    local index="$1"
    local executable="$2"

    if [[ -x "$executable" ]]; then
        step "Starting $executable"
        "$executable" start 8>&- || warn "Could not start $executable. Continuing."
    else
        error_exit "The executable $executable does not exist or is not executable."
    fi
}

stop_instance_callback() {
    local index="$1"
    local executable="$2"

    if [[ -x "$executable" ]]; then
        step "Stopping $executable"
        "$executable" stop 8>&- || warn "Could not stop $executable. Continuing."
    else
        error_exit "The executable $executable does not exist or is not executable."
    fi
}

restart_instance_callback() {
    # shellcheck disable=SC2034 # Shared hook/library contract; may be consumed by sourced helpers.
    local index="$1"
    local executable="$2"

    if [[ -x "$executable" ]]; then
        step "Restarting $executable"
        "$executable" restart 8>&- || warn "Could not restart $executable. Continuing."
    else
        error_exit "The executable $executable does not exist or is not executable."
    fi
}

update_servers() {
    local update_type=${1:-manual}
    section "Stack update"
    info "Update mode: ${update_type}"
    if [[ "$update_type" == manual ]]; then
        stop_servers 1 "$TOTAL_SERVERS"
    fi
    step "Running install_stack.sh update"
    bash "$DIR_INSTALLER_BIN/install_stack.sh" update
    bash "$DIR_INSTALLER_BIN/runtime_intent.sh" capture
    info "Update completed; automatic mode preserves the prior selection, manual mode leaves instances stopped."

}

if [[ $# -eq 0 ]]; then
    print_runtime_panel
    show_deploy_state_summary
    echo ""
    menu
    read -rp "Seleccion: " choice
    case $choice in
        1) start_servers 1 "$TOTAL_SERVERS" ;;
        2) stop_servers 1 "$TOTAL_SERVERS" ;;
        3) restart_servers 1 "$TOTAL_SERVERS" ;;
        4) update_servers automatic ;;
        5) update_servers manual ;;
        *) info "Exiting menu" ;;
    esac
else
    command=$1
    start_range=${2:-1}
    end_range=${3:-$TOTAL_SERVERS}

    instance_validate_range "$start_range" "$end_range" "$TOTAL_SERVERS"

    case $command in
        st|start)     start_servers "$start_range" "$end_range" ;;
        s|stop)       stop_servers "$start_range" "$end_range" ;;
        r|restart)    restart_servers "$start_range" "$end_range" ;;
        aup|aupdate)  update_servers automatic ;;
        up|update)    update_servers manual ;;
        *) echo -e "\e[31mError:\e[0m Comando invalido."; exit 1 ;;
    esac
fi

print_runtime_panel
