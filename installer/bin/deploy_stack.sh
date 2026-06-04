#!/bin/bash
set -euo pipefail

: "${DIR_INSTALLER_BIN:?Error: The DIR_INSTALLER_BIN variable is not defined.}"
: "${DIR_INSTALLER_LIB:?Error: The DIR_INSTALLER_LIB variable is not defined.}"
: "${DIR_INSTALLER:?Error: The DIR_INSTALLER variable is not defined.}"
: "${DIR_STACK:?Error: The DIR_STACK variable is not defined.}"
: "${GAMESERVER:?Error: The GAMESERVER variable is not defined.}"
: "${LGSM_CONFIG:?Error: The LGSM_CONFIG variable is not defined.}"
: "${LGSM_SERVERFILES:?Error: The LGSM_SERVERFILES variable is not defined.}"
: "${COMPONENTS_JSON:=$DIR_STACK/manifests/components.json}"
: "${PROFILE_JSON:=$DIR_STACK/profiles/${STACK_PROFILE:-latest}.json}"

source "$DIR_INSTALLER_LIB/tools_stack.sh"
source "$DIR_INSTALLER_LIB/state_stack.sh"
source "$DIR_INSTALLER_LIB/install_stack_runtime.sh"

state_init_paths

DEPLOYMENT_ID="$(date -u +%Y%m%dT%H%M%SZ)-${STACK_PROFILE:-default}"
DEPLOY_STATE_INITIALIZED=false
L4D2_FRESH_INSTALL="false"
PREVIOUS_DEPLOYMENT_ID=""
TARGET_RESOLVED_COMPONENTS_JSON=""
TARGET_RESOLVED_COMPONENTS_SHA256=""
STACK_UPDATED_DURING_DEPLOY="false"

finalize_deploy_state() {
  local exit_code=$?
  local status="failed"
  local last_error_json

  if [ "$DEPLOY_STATE_INITIALIZED" != "true" ] || [ ! -f "$DEPLOY_STATE_FILE" ]; then
    return
  fi

  if [ "$exit_code" -eq 0 ]; then
    status="ready"
    last_error_json='null'
  else
    last_error_json=$(jq -Rn --arg value "deploy_stack exited with code ${exit_code}" '$value')
  fi

  state_finalize_deploy_state "$status" "$L4D2_FRESH_INSTALL" "$last_error_json"
}

trap finalize_deploy_state EXIT

get_target_additional_instances() {
  local configured_value="${L4D2_ADDITIONAL_INSTANCES:-}"

  if [ -z "$configured_value" ]; then
    if [ -f "$INSTANCES_STATE_FILE" ]; then
      configured_value="$(state_read_additional_instances)"
    else
      configured_value="0"
    fi
  fi

  if ! [[ "$configured_value" =~ ^[0-9]+$ ]]; then
    error_exit "Invalid L4D2_ADDITIONAL_INSTANCES value '$configured_value'. Expected a natural number greater than or equal to 0."
  fi

  printf '%s\n' "$configured_value"
}

clean_steam_password() {
  if [ -n "${STEAM_PASSWD:-}" ]; then
    step "Cleaning STEAM_PASSWD from environment"
    unset STEAM_PASSWD
    export STEAM_PASSWD=""
  fi
}

get_l4d2_install_mode() {
  local mode="${L4D2_INSTALL:-}"

  if [ -z "$mode" ]; then
    mode="normal"
  fi

  case "$mode" in
    normal|skip|force)
      printf '%s\n' "$mode"
      ;;
    *)
      error_exit "Invalid L4D2_INSTALL value '$mode'. Expected: normal, skip or force."
      ;;
  esac
}

is_l4d2_autostart_enabled() {
  local value="${L4D2_AUTOSTART:-}"

  if [ -z "$value" ]; then
    return 0
  fi

  case "${value,,}" in
    true|1|yes|on)
      return 0
      ;;
    false|0|no|off)
      return 1
      ;;
    *)
      error_exit "Invalid L4D2_AUTOSTART value '$value'. Expected a boolean value."
      ;;
  esac
}

is_stack_autoupdate_enabled() {
  local value="${L4D2_STACK_AUTOUPDATE:-}"

  if [ -z "$value" ]; then
    return 1
  fi

  case "${value,,}" in
    true|1|yes|on)
      return 0
      ;;
    false|0|no|off)
      return 1
      ;;
    *)
      error_exit "Invalid L4D2_STACK_AUTOUPDATE value '$value'. Expected a boolean value."
      ;;
  esac
}

initialize_deploy_state() {
  if [ ! -d "$DIR_INSTALLER" ]; then
    section "Prepare runtime directories"
    step "Creating $DIR_INSTALLER"
    mkdir -p "$DIR_INSTALLER"
  fi

  if [ ! -d "$STATE_CURRENT_DIR" ] || [ ! -d "$STATE_HISTORY_DIR" ]; then
    step "Creating deployment state directories"
    state_ensure_directories
  fi

  if [ ! -d "$DIR_STACK" ]; then
    step "Creating $DIR_STACK"
    mkdir -p "$DIR_STACK"
  fi

  PREVIOUS_DEPLOYMENT_ID="$(state_archive_current_deployment)"
  state_create_deploy_state "$DEPLOYMENT_ID" "$PREVIOUS_DEPLOYMENT_ID" "preparing" "${STACK_PROFILE:-default}" "$STATE_RESOLVED_COMPONENTS_FILE" "" "$GAMESERVER"
  DEPLOY_STATE_INITIALIZED=true
}

resolve_target_stack_metadata() {
  if [[ -f "$DIR_STACK/.env" ]]; then
    set -o allexport
    source <(grep -E '^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=' "$DIR_STACK/.env" | sed 's/\r$//')
    set +o allexport
  fi

  if [ ! -f "$COMPONENTS_JSON" ]; then
    error_exit "The components.json file was not found: $COMPONENTS_JSON"
  fi

  if [ ! -f "$PROFILE_JSON" ]; then
    error_exit "The stack profile file was not found: $PROFILE_JSON"
  fi

  TARGET_RESOLVED_COMPONENTS_JSON="$(build_resolved_components_json "$COMPONENTS_JSON" "$PROFILE_JSON")"
  TARGET_RESOLVED_COMPONENTS_SHA256="$(printf '%s\n' "$TARGET_RESOLVED_COMPONENTS_JSON" | sha256sum | awk '{print $1}')"
}

record_target_stack_metadata() {
  local components_summary_json='[]'

  mkdir -p "$STATE_CURRENT_DIR"
  printf '%s\n' "$TARGET_RESOLVED_COMPONENTS_JSON" > "$STATE_RESOLVED_COMPONENTS_FILE"

  components_summary_json="$(printf '%s\n' "$TARGET_RESOLVED_COMPONENTS_JSON" | jq -c '[.[] | {id, folder, source_type, repo_url: (.repo_url // null), github_repo: (.github_repo // null), branch: (.branch // "default"), release_tag: (.release_tag // null)}]')"

  jq \
    --arg stack_profile "${STACK_PROFILE:-default}" \
    --arg resolved_components_file "$STATE_RESOLVED_COMPONENTS_FILE" \
    --arg resolved_components_sha256 "$TARGET_RESOLVED_COMPONENTS_SHA256" \
    --argjson components "$components_summary_json" \
    '
      .stack.profile = $stack_profile |
      .stack.resolved_components_file = $resolved_components_file |
      .stack.resolved_components_sha256 = $resolved_components_sha256 |
      .components = $components
    ' "$DEPLOY_STATE_FILE" > "${DEPLOY_STATE_FILE}.tmp" && mv "${DEPLOY_STATE_FILE}.tmp" "$DEPLOY_STATE_FILE"
}

stack_requires_reapply() {
  local previous_state_file=""
  local previous_status=""
  local previous_profile=""
  local previous_sha256=""

  if [ -z "$PREVIOUS_DEPLOYMENT_ID" ]; then
    return 0
  fi

  previous_state_file="$STATE_HISTORY_DIR/$PREVIOUS_DEPLOYMENT_ID/deploy-state.json"
  if [ ! -f "$previous_state_file" ]; then
    return 0
  fi

  previous_status="$(jq -r '.status // empty' "$previous_state_file" 2> /dev/null || true)"
  previous_profile="$(jq -r '.stack.profile // empty' "$previous_state_file" 2> /dev/null || true)"
  previous_sha256="$(jq -r '.stack.resolved_components_sha256 // empty' "$previous_state_file" 2> /dev/null || true)"

  if [ "$previous_status" != "ready" ]; then
    return 0
  fi

  if [ -z "$previous_profile" ] || [ -z "$previous_sha256" ]; then
    return 0
  fi

  if [ "$previous_profile" != "${STACK_PROFILE:-default}" ]; then
    return 0
  fi

  if [ "$previous_sha256" != "$TARGET_RESOLVED_COMPONENTS_SHA256" ]; then
    return 0
  fi

  return 1
}

prepare_lgsm_tooling() {
  if [ -f "/app/lgsm/package.json" ]; then
    section "Prepare LGSM tooling"
    step "Running npm install in /app/lgsm"
    cd /app/lgsm || exit
    npm install
    cd /app || exit
  fi

  if [ "${LGSM_GITHUBBRANCH:-master}" != "master" ]; then
    warn "Non-master LGSM branch detected. Refreshing modules."
    rm -rf /app/lgsm/modules/*
    ./"${GAMESERVER}" update-lgsm
  elif [ -d "/app/lgsm/modules" ]; then
    step "Ensuring LGSM modules are executable"
    chmod +x /app/lgsm/modules/*
  fi

  if [ "${LGSM_DEV:-false}" = "true" ]; then
    info "Developer mode enabled"
    ./"${GAMESERVER}" developer
  fi
}

prepare_steam_runtime_libraries() {
  section "Prepare Steam runtime libraries"

  if [ -d "$HOME/.steam/sdk32" ]; then
    rm -rf "$HOME/.steam/sdk32"
  fi

  if [ -d "$HOME/.steam/sdk64" ]; then
    rm -rf "$HOME/.steam/sdk64"
  fi

  mkdir -p "$HOME/.steam/sdk32" "$HOME/.steam/sdk64"

  step "Syncing Steam runtime libraries"
  find "$HOME/.local/share/Steam/steamcmd/linux32/" -maxdepth 1 -type f -exec cp -v {} "$HOME/.steam/sdk32" \;
  cp -v "$HOME/.local/share/Steam/steamcmd/linux64/steamclient.so" "$HOME/.steam/sdk64/steamclient.so"
}

is_gameserver_installed() {
  [ -f "${LGSM_SERVERFILES}/srcds_run" ]
}

install_primary_instance() {
  section "Prepare primary instance runtime"
  info "Primary instance: ${GAMESERVER}"
  local install_mode
  install_mode="$(get_l4d2_install_mode)"
  info "Install mode: ${install_mode}"

  if [ -n "${STEAM_USER:-}" ] && [ -n "${STEAM_PASSWD:-}" ]; then
    local secrets_config

    section "Install primary instance"
    info "Steam credentials detected. Using official Steam installation method."

    secrets_config="${LGSM_CONFIG}/${GAMESERVER}/secrets-common.cfg"

    if [ ! -f "${secrets_config}" ]; then
      step "Creating secrets-common.cfg with Steam credentials"
      mkdir -p "$(dirname "${secrets_config}")"
      touch "${secrets_config}"
    fi

    if ! grep -q "steamuser=" "${secrets_config}"; then
      echo "steamuser=${STEAM_USER}" >> "${secrets_config}"
    fi

    if ! grep -q "steampass=" "${secrets_config}"; then
      echo "steampass=${STEAM_PASSWD}" >> "${secrets_config}"
    fi

    warn "If your Steam account uses SteamGuard Mobile Authenticator, authorize the login from your mobile device when prompted."

    if [ "$install_mode" = "skip" ]; then
      warn "Skipping primary instance installation because L4D2_INSTALL=skip"
      info "Manual installation command: ./${GAMESERVER} auto-install"
      clean_steam_password
      return 0
    fi

    if [ "$install_mode" = "force" ] || ! is_gameserver_installed; then
      step "Installing the primary instance using the official Steam method"
      ./"${GAMESERVER}" auto-install
      L4D2_FRESH_INSTALL="true"
      clean_steam_password
      success "Primary instance installation completed"
      return 0
    fi

    info "Skipping installation because the primary instance is already installed"
    ./"${GAMESERVER}" sponsor
    clean_steam_password
    return 0
  fi

  if [ "$install_mode" = "skip" ]; then
    warn "Skipping primary instance installation because L4D2_INSTALL=skip"
    info "Manual installation command: ./${GAMESERVER} auto-install"
    return 0
  fi

  section "Install primary instance"
  info "No Steam credentials provided. Using anonymous installation path."

  if [ "$install_mode" != "force" ] && is_gameserver_installed; then
    info "Skipping installation because the primary instance is already installed"
    return 0
  fi

  step "Running l4d2_fix_install.sh workaround"
  bash "$DIR_INSTALLER_BIN/l4d2_fix_install.sh"
  L4D2_FRESH_INSTALL="true"
}

apply_stack_if_needed() {
  section "Apply stack"

  if [ "$L4D2_FRESH_INSTALL" = "true" ]; then
    step "Installing stack files"
    bash "$DIR_INSTALLER_BIN/install_stack.sh" install
    STACK_UPDATED_DURING_DEPLOY="true"
    return 0
  fi

  if stack_requires_reapply; then
    step "Applying stack update because the resolved stack definition changed"
    bash "$DIR_INSTALLER_BIN/install_stack.sh" update
    STACK_UPDATED_DURING_DEPLOY="true"
    return 0
  fi

  info "Skipping stack update because the resolved stack definition is unchanged"
}

run_stack_autoupdate_before_start() {
  if ! is_stack_autoupdate_enabled; then
    info "Pre-start stack auto-update disabled"
    return 0
  fi

  if [ "$STACK_UPDATED_DURING_DEPLOY" = "true" ]; then
    info "Skipping pre-start update because the stack was already applied during this deployment"
    return 0
  fi

  section "Pre-start stack auto-update"

  if [ "$L4D2_FRESH_INSTALL" = "true" ]; then
    info "Skipping pre-start update because the stack was just installed during fresh setup"
    return 0
  fi

  step "Running install_stack.sh update before server startup"
  bash "$DIR_INSTALLER_BIN/install_stack.sh" 1
}

prepare_user_profile() {
  section "Prepare user profile"
  local key
  local trimmed_key

  if [ ! -f "$HOME/.bashrc" ]; then
    step "Creating $HOME/.bashrc"
    cp /etc/skel/.bashrc "$HOME/.bashrc"
  else
    info "$HOME/.bashrc already exists"
  fi

  if [ ! -d "$HOME/.ssh" ]; then
    step "Creating $HOME/.ssh"
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
  else
    info "$HOME/.ssh already exists"
  fi

  if [ ! -f "$HOME/.ssh/authorized_keys" ]; then
    step "Creating authorized_keys"
    touch "$HOME/.ssh/authorized_keys"
  else
    info "authorized_keys already exists"
  fi

  chmod 600 "$HOME/.ssh/authorized_keys"

  if [ -n "${SSH_KEY:-}" ]; then
    step "Ensuring SSH public keys are present"
    IFS=',' read -ra KEYS <<< "${SSH_KEY}"
    for key in "${KEYS[@]}"; do
      trimmed_key="$(printf '%s' "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
      if [ -z "$trimmed_key" ]; then
        continue
      fi

      if ! grep -Fqx "$trimmed_key" "$HOME/.ssh/authorized_keys"; then
        printf '%s\n' "$trimmed_key" >> "$HOME/.ssh/authorized_keys"
      fi
    done
  else
    info "SSH_KEY is empty. Skipping key addition."
  fi
}

start_runtime() {
  section "Start runtime"
  info "Primary instance: ${GAMESERVER}"
  local additional_instances_target="0"

  additional_instances_target="$(get_target_additional_instances)"
  step "Synchronizing runtime instances (additional: ${additional_instances_target})"
  "$DIR_INSTALLER_BIN/sync_instances.sh" "$additional_instances_target"

  if ! is_l4d2_autostart_enabled; then
    warn "Skipping start because L4D2_AUTOSTART=false"
    return 0
  fi

  step "Starting runtime through menu_stack.sh"
  bash "$DIR_INSTALLER_BIN/menu_stack.sh" start
}

initialize_deploy_state
resolve_target_stack_metadata
record_target_stack_metadata
prepare_lgsm_tooling
prepare_user_profile
install_primary_instance
prepare_steam_runtime_libraries
apply_stack_if_needed

section "Update runtime patches"
step "Running L4D2 updater bootstrap"
bash /app/container/bootstrap/l4d2_updater.sh

run_stack_autoupdate_before_start

start_runtime

success "Deployment orchestration completed"
