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
: "${REPOS_JSON:=$DIR_STACK/sources.json}"
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
SUBSCRIPT_DIR="$DIR_STACK_HOOKS"
CACHE_FILE="$DIR_TMP/cache_gameserver.log"
LOG_FILE="$STATE_INSTALL_LOG_FILE"
LEGACY_LOG_FILE="$DIR_INSTALLER_BIN/install_stack.log"
INSTALLER_MANAGED_DEPLOY_STATE=false
DEPLOYMENT_ID=""

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
    state_create_deploy_state "$DEPLOYMENT_ID" "$previous_deployment_id" "installing" "${STACK_PROFILE:-default}" "$STATE_SOURCES_FILE" "" "${GAMESERVER:-}"
    INSTALLER_MANAGED_DEPLOY_STATE=true
}

finalize_installer_deploy_state() {
    local completed_at

    if [[ "$INSTALLER_MANAGED_DEPLOY_STATE" != "true" || ! -f "$DEPLOY_STATE_FILE" ]]; then
        return 0
    fi

    completed_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    state_finalize_deploy_state "ready" "false" 'null' "$completed_at"
}

update_deploy_state_installer_metadata() {
    local sources_sha256=""
    local components_json='[]'

    mkdir -p "$STATE_CURRENT_DIR"

    if [[ -f "$REPOS_JSON" ]]; then
        sources_sha256=$(sha256sum "$REPOS_JSON" | awk '{print $1}')
        cp "$REPOS_JSON" "$STATE_SOURCES_FILE"
        components_json=$(jq -c '[.[] | {folder, source_type, repo_url: (.repo_url // null), github_repo: (.github_repo // null), branch: (.branch // "default"), release_tag: (.release_tag // null)}]' "$REPOS_JSON")
    fi

    state_update_deploy_install_metadata "$INSTALL_TYPE" "$STATE_SOURCES_FILE" "$sources_sha256" "$components_json"
}

#####################################################
# Check for repos.json existence
if [[ ! -f "$REPOS_JSON" ]]; then
    echo "Error: The sources.json file was not found in $DIR_STACK."
    exit 1
fi

# JSON file with the list of paths to be backuped
BACKUP_JSON="$DIR_STACK/preserve-paths.json"

#####################################################
# Verify if the script is run as the user ${USER}
check_user "${USER}"

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
info "Sources file: $REPOS_JSON"

#####################################################
# Prepare 32-bit libraries and remove duplicates
if [ -d "$HOME/.steam/sdk32" ]; then
    rm -rf "$HOME/.steam/sdk32"
fi
if [ -d "$HOME/.steam/sdk64" ]; then
    rm -rf "$HOME/.steam/sdk64"
fi

mkdir -p "$HOME/.steam/sdk32" "$HOME/.steam/sdk64"

find "$HOME/.local/share/Steam/steamcmd/linux32/" -maxdepth 1 -type f -exec cp -v {} "$HOME/.steam/sdk32" \;
cp -v "$HOME/.local/share/Steam/steamcmd/linux64/steamclient.so" "$HOME/.steam/sdk64/steamclient.so"

if [[ -e "$LGSM_SERVERFILES/bin/libstdc++.so.6" ]]; then
    rm "$LGSM_SERVERFILES/bin/libstdc++.so.6" "$LGSM_SERVERFILES/bin/dedicated/libstdc++.so.6"
    log "Removed libstdc++.so.6 for compatibility with extensions."
else
    log "libstdc++.so.6 not detected locally."
fi

if [[ -e "$LGSM_SERVERFILES/bin/libgcc_s.so.1" ]]; then
    rm "$LGSM_SERVERFILES/bin/libgcc_s.so.1" "$LGSM_SERVERFILES/bin/dedicated/libgcc_s.so.1"
    log "Removed libgcc_s.so.1 for compatibility with extensions."
else
    log "libgcc_s.so.1 not detected locally."
fi

#####################################################
# Temporary directory
mkdir -p "$DIR_TMP"
cd "$DIR_TMP" || error_exit "Could not access the temporary directory $DIR_TMP."

if [[ ! -f "$CACHE_FILE" ]]; then
    touch "$CACHE_FILE"
fi

#####################################################
# Process cleaning in case of update
if [ "$INSTALL_TYPE" == "update" ]; then
    prepare_update_cleanup
fi

#####################################################
# Source installation
apply_stack_sources

section "Stack ${INSTALL_TYPE} completed"
success "L4D2 competitive stack finished successfully"
info "Mode: $INSTALL_TYPE"
info "Current log: $LOG_FILE"

finalize_installer_deploy_state
