#!/bin/bash
set -euo pipefail

: "${DIR_INSTALLER_BIN:?Error: The DIR_INSTALLER_BIN variable is not defined.}"
: "${DIR_INSTALLER_LIB:?Error: The DIR_INSTALLER_LIB variable is not defined.}"
: "${DIR_INSTALLER:?Error: The DIR_INSTALLER variable is not defined.}"
: "${DIR_STACK:?Error: The DIR_STACK variable is not defined.}"
: "${GAMESERVER:?Error: The GAMESERVER variable is not defined.}"
: "${LGSM_CONFIG:?Error: The LGSM_CONFIG variable is not defined.}"
: "${LGSM_SERVERFILES:?Error: The LGSM_SERVERFILES variable is not defined.}"

source "$DIR_INSTALLER_LIB/tools_stack.sh"
source "$DIR_INSTALLER_LIB/state_stack.sh"

state_init_paths

DEPLOYMENT_ID="$(date -u +%Y%m%dT%H%M%SZ)-${STACK_PROFILE:-default}"
DEPLOY_STATE_INITIALIZED=false
L4D2_FRESH_INSTALL="false"
PREVIOUS_DEPLOYMENT_ID=""

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

clean_steam_password() {
  if [ -n "${STEAM_PASSWD:-}" ]; then
    step "Cleaning STEAM_PASSWD from environment"
    unset STEAM_PASSWD
    export STEAM_PASSWD=""
  fi
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
  state_create_deploy_state "$DEPLOYMENT_ID" "$PREVIOUS_DEPLOYMENT_ID" "preparing" "${STACK_PROFILE:-default}" "${DIR_STACK}/sources.json" "$(state_compute_sources_sha256 "${DIR_STACK}/sources.json")" "$GAMESERVER"
  DEPLOY_STATE_INITIALIZED=true
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

install_primary_instance() {
  section "Prepare primary instance runtime"
  info "Primary instance: ${GAMESERVER}"

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

    if [ -z "$(ls -A -- "/data/serverfiles" 2> /dev/null)" ]; then
      step "Installing the primary instance using the official Steam method"
      ./"${GAMESERVER}" auto-install
      L4D2_FRESH_INSTALL="true"
      clean_steam_password
      success "Primary instance installation completed"
      return 0
    fi

    info "Skipping installation because /data/serverfiles is not empty"
    ./"${GAMESERVER}" sponsor
    clean_steam_password
    return 0
  fi

  if [ "${L4D2_NO_INSTALL:-false}" = "true" ]; then
    warn "Skipping primary instance installation because L4D2_NO_INSTALL=true"
    info "Manual installation command: ./${GAMESERVER} auto-install"
    return 0
  fi

  section "Install primary instance"
  info "No Steam credentials provided. Using anonymous installation path."
  step "Running l4d2_fix_install.sh workaround"

  if [ -n "$(ls -A -- "${LGSM_SERVERFILES}" 2> /dev/null)" ]; then
    info "Skipping installation because ${LGSM_SERVERFILES} is not empty"
    return 0
  fi

  bash "$DIR_INSTALLER_BIN/l4d2_fix_install.sh"
  L4D2_FRESH_INSTALL="true"
}

apply_stack_if_needed() {
  section "Apply stack"

  if [ "$L4D2_FRESH_INSTALL" = "false" ]; then
    info "Skipping stack installation because this is not a fresh install"
    return 0
  fi

  step "Installing stack files"
  bash "$DIR_INSTALLER_BIN/install_stack.sh" install
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

  if [ "$L4D2_FRESH_INSTALL" = "true" ]; then
    info "Fresh install detected. Skipping automatic start."
    "$DIR_INSTALLER_BIN/sync_instances.sh" 0 > /dev/null 2>&1
    return 0
  fi

  if [ "${L4D2_NO_AUTOSTART:-false}" = "true" ]; then
    warn "Skipping start because L4D2_NO_AUTOSTART=true"
    return 0
  fi

  step "Starting runtime through menu_stack.sh"
  bash "$DIR_INSTALLER_BIN/menu_stack.sh" start
}

initialize_deploy_state
prepare_lgsm_tooling
install_primary_instance
apply_stack_if_needed

section "Update runtime patches"
step "Running L4D2 updater bootstrap"
bash /app/container/bootstrap/l4d2_updater.sh

prepare_user_profile
start_runtime

success "Deployment orchestration completed"