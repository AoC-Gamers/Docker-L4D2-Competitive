#!/bin/bash
# state_stack.sh - Helpers for deployment and instance state.

state_init_paths() {
    if [ -z "${DIR_INSTALLER_STATE:-}" ]; then
        if [ -n "${DIR_INSTALLER:-}" ]; then
            DIR_INSTALLER_STATE="${DIR_INSTALLER}/state"
        elif [ -n "${DIR_INSTALLER_BIN:-}" ]; then
            DIR_INSTALLER_STATE="${DIR_INSTALLER_BIN%/bin}/state"
        else
            DIR_INSTALLER_STATE="/data/installer/state"
        fi
    fi

    STATE_ROOT="$DIR_INSTALLER_STATE"
    STATE_CURRENT_DIR="$STATE_ROOT/current"
    STATE_HISTORY_DIR="$STATE_ROOT/history"
    DEPLOY_STATE_FILE="$STATE_CURRENT_DIR/deploy-state.json"
    INSTANCES_STATE_FILE="$STATE_CURRENT_DIR/instances-state.json"
    STATE_SOURCES_FILE="$STATE_CURRENT_DIR/sources.json"
    STATE_INSTALL_LOG_FILE="$STATE_CURRENT_DIR/install_stack.log"
}

state_ensure_directories() {
    mkdir -p "$STATE_CURRENT_DIR" "$STATE_HISTORY_DIR"
}

state_compute_sources_sha256() {
    local sources_file="${1:-${DIR_STACK}/sources.json}"

    if [ -f "$sources_file" ]; then
        sha256sum "$sources_file" | awk '{print $1}'
        return 0
    fi

    printf '%s\n' ""
}

state_get_current_deployment_id() {
    if [ ! -f "$DEPLOY_STATE_FILE" ]; then
        printf '%s\n' ""
        return 0
    fi

    jq -r '.deployment_id // empty' "$DEPLOY_STATE_FILE" 2> /dev/null || printf '%s\n' ""
}

state_get_current_deployment_status() {
    if [ ! -f "$DEPLOY_STATE_FILE" ]; then
        printf '%s\n' ""
        return 0
    fi

    jq -r '.status // empty' "$DEPLOY_STATE_FILE" 2> /dev/null || printf '%s\n' ""
}

state_archive_snapshot() {
    local deployment_id="$1"
    local snapshot_dir
    local state_file

    [ -n "$deployment_id" ] || return 0

    snapshot_dir="${STATE_HISTORY_DIR}/${deployment_id}"
    mkdir -p "$snapshot_dir"

    for state_file in deploy-state.json sources.json install_stack.log instances-state.json; do
        if [ -f "${STATE_CURRENT_DIR}/${state_file}" ]; then
            cp "${STATE_CURRENT_DIR}/${state_file}" "${snapshot_dir}/${state_file}"
        fi
    done
}

state_archive_current_deployment() {
    local deployment_id

    deployment_id="$(state_get_current_deployment_id)"
    if [ -n "$deployment_id" ]; then
        state_archive_snapshot "$deployment_id"
    fi

    printf '%s\n' "$deployment_id"
}

state_create_deploy_state() {
    local deployment_id="$1"
    local previous_deployment_id="$2"
    local status="$3"
    local stack_profile="$4"
    local sources_file="$5"
    local sources_sha256="$6"
    local gameserver="$7"
    local started_at="${8:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"

    state_ensure_directories

    jq -n \
        --arg deployment_id "$deployment_id" \
        --arg previous_deployment_id "$previous_deployment_id" \
        --arg status "$status" \
        --arg stack_profile "$stack_profile" \
        --arg sources_file "$sources_file" \
        --arg sources_sha256 "$sources_sha256" \
        --arg gameserver "$gameserver" \
        --arg started_at "$started_at" \
        '
            {
                schema_version: 1,
                deployment_id: $deployment_id,
                previous_deployment_id: (if $previous_deployment_id == "" then null else $previous_deployment_id end),
                status: $status,
                stack: {
                    profile: $stack_profile,
                    sources_file: $sources_file,
                    sources_sha256: $sources_sha256
                },
                runtime: {
                    gameserver: $gameserver,
                    fresh_install: false
                },
                instances: {
                    additional_instances: 0,
                    detected_instances: 0
                },
                timestamps: {
                    started_at: $started_at,
                    completed_at: null
                },
                last_error: null
            }
        ' > "${DEPLOY_STATE_FILE}.tmp"
    mv "${DEPLOY_STATE_FILE}.tmp" "$DEPLOY_STATE_FILE"
}

state_update_deploy_install_metadata() {
    local install_type="$1"
    local sources_file="$2"
    local sources_sha256="$3"
    local components_json="$4"

    if [ ! -f "$DEPLOY_STATE_FILE" ]; then
        return 0
    fi

    jq \
        --arg install_type "$install_type" \
        --arg stack_profile "${STACK_PROFILE:-default}" \
        --arg sources_file "$sources_file" \
        --arg sources_sha256 "$sources_sha256" \
        --argjson components "$components_json" \
        '
            .stack.profile = $stack_profile |
            .stack.sources_file = $sources_file |
            .stack.sources_sha256 = $sources_sha256 |
            .installer.install_type = $install_type |
            .components = $components
        ' "$DEPLOY_STATE_FILE" > "${DEPLOY_STATE_FILE}.tmp" && mv "${DEPLOY_STATE_FILE}.tmp" "$DEPLOY_STATE_FILE"
}

state_read_additional_instances() {
    if [ ! -f "$INSTANCES_STATE_FILE" ]; then
        printf '%s\n' "0"
        return 0
    fi

    jq -r '.additional_instances // 0' "$INSTANCES_STATE_FILE" 2> /dev/null || printf '%s\n' "0"
}

state_write_instances_state() {
    local additional_instances="$1"
    local last_execution="${2:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"

    state_ensure_directories

    jq -n \
        --arg last_execution "$last_execution" \
        --argjson additional_instances "$additional_instances" \
        '
            {
                schema_version: 1,
                last_execution: $last_execution,
                additional_instances: $additional_instances
            }
        ' > "${INSTANCES_STATE_FILE}.tmp"
    mv "${INSTANCES_STATE_FILE}.tmp" "$INSTANCES_STATE_FILE"
}

state_count_detected_instances() {
    local count=0
    local file

    if [ -n "${GAMESERVER:-}" ] && [ -x "/app/${GAMESERVER}" ]; then
        count=1
    fi

    if [ -n "${GAMESERVER:-}" ]; then
        shopt -s nullglob
        for file in /app/${GAMESERVER}-*; do
            if [ -x "$file" ]; then
                count=$((count + 1))
            fi
        done
        shopt -u nullglob
    fi

    printf '%s\n' "$count"
}

state_finalize_deploy_state() {
    local status="$1"
    local fresh_install_flag="$2"
    local last_error_json="$3"
    local completed_at="${4:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
    local sources_sha256
    local detected_instances
    local additional_instances

    if [ ! -f "$DEPLOY_STATE_FILE" ]; then
        return 0
    fi

    sources_sha256="$(state_compute_sources_sha256 "${DIR_STACK}/sources.json")"
    detected_instances="$(state_count_detected_instances)"
    additional_instances="$(state_read_additional_instances)"

    jq \
        --arg status "$status" \
        --arg completed_at "$completed_at" \
        --arg stack_profile "${STACK_PROFILE:-}" \
        --arg sources_file "${DIR_STACK:-}/sources.json" \
        --arg sources_sha256 "$sources_sha256" \
        --arg gameserver "${GAMESERVER:-}" \
        --argjson fresh_install "$( [ "$fresh_install_flag" = "true" ] && echo true || echo false )" \
        --argjson additional_instances "$additional_instances" \
        --argjson detected_instances "$detected_instances" \
        --argjson last_error "$last_error_json" \
        '
            .status = $status |
            .timestamps.completed_at = $completed_at |
            .stack.profile = (if $stack_profile == "" then .stack.profile else $stack_profile end) |
            .stack.sources_file = (if $sources_file == "/sources.json" then .stack.sources_file else $sources_file end) |
            .stack.sources_sha256 = $sources_sha256 |
            .runtime.gameserver = (if $gameserver == "" then .runtime.gameserver else $gameserver end) |
            .runtime.fresh_install = $fresh_install |
            .instances.additional_instances = $additional_instances |
            .instances.detected_instances = $detected_instances |
            .last_error = $last_error
        ' "$DEPLOY_STATE_FILE" > "${DEPLOY_STATE_FILE}.tmp" && mv "${DEPLOY_STATE_FILE}.tmp" "$DEPLOY_STATE_FILE"

    state_archive_snapshot "$(state_get_current_deployment_id)"
}