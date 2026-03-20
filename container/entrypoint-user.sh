#!/bin/bash

source "$DIR_INSTALLER_LIB/tools_stack.sh"

exit_handler_user() {
  # Execute the shutdown commands
  section "Stopping primary instance"
  info "Instance: ${GAMESERVER}"
  ./"${GAMESERVER}" stop
  exitcode=$?
  exit ${exitcode}
}

# Exit trap
info "Loading exit handler"
trap exit_handler_user SIGQUIT SIGINT SIGTERM

# Setup game server
if [ ! -f "${GAMESERVER}" ]; then
  section "Bootstrap primary instance"
  step "Creating primary instance executable ${GAMESERVER}"
  ./linuxgsm.sh "${GAMESERVER}"
fi

# Symlink LGSM_CONFIG to /app/lgsm/config-lgsm
if [ ! -d "/app/lgsm/config-lgsm" ]; then
  section "Prepare symlinks"
  step "Linking ${LGSM_CONFIG} to /app/lgsm/config-lgsm"
  ln -s "${LGSM_CONFIG}" "/app/lgsm/config-lgsm"
fi

# Symlink LGSM_SERVERFILES to /app/serverfiles
if [ ! -d "/app/serverfiles" ]; then
  step "Linking ${LGSM_SERVERFILES} to /app/serverfiles"
  ln -s "${LGSM_SERVERFILES}" "/app/serverfiles"
fi

# Symlink LGSM_LOGDIR to /app/log
if [ ! -d "/app/log" ]; then
  step "Linking ${LGSM_LOGDIR} to /app/log"
  ln -s "${LGSM_LOGDIR}" "/app/log"
fi

# Symlink LGSM_DATADIR to /app/lgsm/data
if [ ! -d "/app/lgsm/data" ]; then
  step "Linking ${LGSM_DATADIR} to /app/lgsm/data"
  ln -s "${LGSM_DATADIR}" "/app/lgsm/data"
fi

# Create installer and stack directories in /data
if [ ! -d "$DIR_INSTALLER" ]; then
  section "Prepare runtime directories"
  step "Creating $DIR_INSTALLER"
  mkdir -p "$DIR_INSTALLER"
fi

if [ ! -d "$DIR_STACK" ]; then
  step "Creating $DIR_STACK"
  mkdir -p "$DIR_STACK"
fi

section "Run deployment orchestrator"
step "Delegating runtime flow to deploy_stack.sh"
bash "$DIR_INSTALLER_BIN/deploy_stack.sh"

success "User entrypoint completed"
