#!/bin/bash
set -euo pipefail

#####################################################
# Basic configuration
: "${DIR_INSTALLER_BIN:?Error: The DIR_INSTALLER_BIN variable is not defined.}"
: "${DIR_INSTALLER_LIB:?Error: The DIR_INSTALLER_LIB variable is not defined.}"
: "${DIR_STACK:?Error: The DIR_STACK variable is not defined.}"
: "${DIR_STACK_HOOKS:?Error: The DIR_STACK_HOOKS variable is not defined.}"
: "${DIR_LEFT4DEAD2:?Error: The DIR_LEFT4DEAD2 variable is not defined.}"
: "${DIR_CFG:?Error: The DIR_CFG variable is not defined.}"
: "${COMPONENTS_JSON:=$DIR_STACK/manifests/components.json}"
: "${PROFILE_JSON:=$DIR_STACK/profiles/${STACK_PROFILE:-latest}.json}"
: "${DIR_INSTALLER_STATE:=${DIR_INSTALLER}/state}"

#####################################################
# Function library
source "$DIR_INSTALLER_LIB/tools_stack.sh"
source "$DIR_INSTALLER_LIB/state_stack.sh"
source "$DIR_INSTALLER_LIB/install_stack_runtime.sh"

state_init_paths

#####################################################
# Variables
GIT_FORCE_DOWNLOAD="${GIT_FORCE_DOWNLOAD:-false}"
LOG_FILE="$STATE_INSTALL_LOG_FILE"
LEGACY_LOG_FILE="$DIR_INSTALLER_BIN/install_stack.log"
INSTALLER_MANAGED_DEPLOY_STATE=false
DEPLOYMENT_ID=""
RESOLVED_COMPONENTS_JSON=""
DIR_TMP_ROOT="${DIR_TMP}"
INSTALL_TMP_DIR=""
CACHE_FILE=""
CACHE_LOCK_FILE=""

initialize_install_logging() {
    mkdir -p "$STATE_CURRENT_DIR"
    : > "$LOG_FILE"
    : > "$LEGACY_LOG_FILE"
    exec > >(tee -a "$LOG_FILE" "$LEGACY_LOG_FILE") 2>&1
}

ensure_deploy_state_context() {
    local current_status=""
    local previous_deployment_id=""

    state_ensure_directories
    current_status="$(state_get_current_deployment_status)"

    if [[ "$current_status" == "preparing" || "$current_status" == "installing" ]]; then
        return 0
    fi

    previous_deployment_id="$(state_archive_current_deployment)"

    DEPLOYMENT_ID="$(date -u +%Y%m%dT%H%M%SZ)-${STACK_PROFILE:-default}"
    state_create_deploy_state "$DEPLOYMENT_ID" "$previous_deployment_id" "installing" "${STACK_PROFILE:-default}" "$STATE_RESOLVED_COMPONENTS_FILE" "" "${GAMESERVER:-}"
    INSTALLER_MANAGED_DEPLOY_STATE=true
}

finalize_installer_deploy_state() {
    local exit_code="${1:-$?}"
    local completed_at
    local status="failed"
    local last_error_json='null'

    if [[ "$INSTALLER_MANAGED_DEPLOY_STATE" != "true" || ! -f "$DEPLOY_STATE_FILE" ]]; then
        return 0
    fi

    if [[ "$exit_code" -ne 0 ]]; then
        last_error_json=$(jq -Rn --arg value "install_stack exited with code ${exit_code}" '$value')
    else
        status="ready"
    fi

    completed_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    state_finalize_deploy_state "$status" "false" "$last_error_json" "$completed_at"
}

initialize_install_workspace() {
    local stack_profile_slug=""
    local cache_namespace=""
    local run_id=""

    stack_profile_slug="$(printf '%s\n' "${STACK_PROFILE:-default}" | tr -c '[:alnum:]_.-' '_')"
    cache_namespace="${stack_profile_slug:-default}"
    run_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"

    INSTALL_TMP_DIR="${DIR_TMP_ROOT}/install_stack/${cache_namespace}/${run_id}"
    DIR_TMP="$INSTALL_TMP_DIR"

    mkdir -p "$DIR_TMP"
    cd "$DIR_TMP" || error_exit "Could not access the temporary directory $DIR_TMP."

    mkdir -p "${STATE_ROOT}/cache"
    CACHE_FILE="${STATE_ROOT}/cache/${cache_namespace}.log"
    CACHE_LOCK_FILE="${CACHE_FILE}.lock"

    if [[ ! -f "$CACHE_FILE" ]]; then
        touch "$CACHE_FILE"
    fi

    info "Temporary workspace: $DIR_TMP"
    info "Component cache: $CACHE_FILE"
}

cleanup_install_workspace() {
    if [[ -n "$INSTALL_TMP_DIR" && -d "$INSTALL_TMP_DIR" ]]; then
        rm -rf "$INSTALL_TMP_DIR"
    fi
}

handle_install_stack_exit() {
    local exit_code=$?
    finalize_installer_deploy_state "$exit_code"
    cleanup_install_workspace
}

trap handle_install_stack_exit EXIT

update_deploy_state_installer_metadata() {
    local resolved_components_sha256=""
    local resolved_components_summary_json='[]'

    mkdir -p "$STATE_CURRENT_DIR"

    if [[ -n "$RESOLVED_COMPONENTS_JSON" ]]; then
        resolved_components_sha256=$(printf '%s\n' "$RESOLVED_COMPONENTS_JSON" | sha256sum | awk '{print $1}')
        printf '%s\n' "$RESOLVED_COMPONENTS_JSON" > "$STATE_RESOLVED_COMPONENTS_FILE"
        resolved_components_summary_json=$(printf '%s\n' "$RESOLVED_COMPONENTS_JSON" | jq -c '[.[] | {id, folder, source_type, repo_url: (.repo_url // null), github_repo: (.github_repo // null), branch: (.branch // "default"), release_tag: (.release_tag // null)}]')
    fi

    state_update_deploy_install_metadata "$INSTALL_TYPE" "$STATE_RESOLVED_COMPONENTS_FILE" "$resolved_components_sha256" "$resolved_components_summary_json"
}

#####################################################
# Load variables from .env
if [[ -f "$DIR_STACK/.env" ]]; then
    # Load variables preserving full values (tokens/URLs) and tolerating CRLF.
    set -o allexport
    source <(grep -E '^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=' "$DIR_STACK/.env" | sed 's/\r$//')
    set +o allexport
else
    echo "The .env file was not found in $DIR_STACK."
fi

#####################################################
# Verify if the script is run as the user ${USER}
check_user "${USER}"

#####################################################
# Check for stack manifest/profile existence
if [[ ! -f "$COMPONENTS_JSON" ]]; then
    echo "Error: The components.json file was not found in $DIR_STACK/manifests."
    exit 1
fi

if [[ ! -f "$PROFILE_JSON" ]]; then
    echo "Error: The stack profile file was not found: $PROFILE_JSON"
    exit 1
fi

RESOLVED_COMPONENTS_JSON="$(build_resolved_components_json "$COMPONENTS_JSON" "$PROFILE_JSON")"

# JSON file with the list of paths to be backuped
BACKUP_JSON="$DIR_STACK/preserve-paths.json"

#####################################################
# Define installation type (install/update)
if [[ -n "${1:-}" ]]; then
    case "$1" in
        install|0) INSTALL_TYPE="install" ;;
        update|1)  INSTALL_TYPE="update"  ;;
        *) error_exit "Invalid argument. Use 'install' (or 0) for clean installation or 'update' (or 1) for update." ;;
    esac
else
    read -rp "Clean installation (0) or update (1)? " OPTION
    case "$OPTION" in
        0) INSTALL_TYPE="install" ;;
        1) INSTALL_TYPE="update" ;;
        *) error_exit "Invalid option. Use '0' for clean installation or '1' for update." ;;
    esac
fi

ensure_deploy_state_context
initialize_install_logging
update_deploy_state_installer_metadata

section "Stack ${INSTALL_TYPE}"
info "Deployment ID: ${DEPLOYMENT_ID:-$(jq -r '.deployment_id // "n/a"' "$DEPLOY_STATE_FILE" 2> /dev/null || echo n/a)}"
info "Stack profile: ${STACK_PROFILE:-default}"
info "Components file: $COMPONENTS_JSON"
info "Profile file: $PROFILE_JSON"

#####################################################
# Temporary directory and cache workspace
initialize_install_workspace

#####################################################
# Process cleaning in case of update
if [ "$INSTALL_TYPE" == "update" ]; then
    prepare_update_cleanup
fi

#####################################################
# Source installation
apply_stack_sources

#####################################################
# Shared post-install maintenance
section "Post-install maintenance"
step "Running shared GeoIP updater"
bash "$DIR_INSTALLER_BIN/geoip_update.sh"

section "Stack ${INSTALL_TYPE} completed"
success "L4D2 competitive stack finished successfully"
info "Mode: $INSTALL_TYPE"
info "Current log: $LOG_FILE"
