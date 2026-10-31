#!/bin/bash
set -euo pipefail
source /app/installer/lib/tools_stack.sh
source /app/container/runtime-permissions.sh
stack_set_runtime_executables /app
# Links and all operational hooks run only after dropping privileges.
bash /app/container/bootstrap/symlink.sh
for script in /app/container/bootstrap/*.sh; do
    [[ "$script" == */symlink.sh ]] && continue
    bash "$script"
done

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
if STACK_CONTAINER_BOOT=true bash "$DIR_INSTALLER_BIN/deploy_stack.sh"; then
  success "Deployment orchestrator completed"
else
  error_exit "Deployment orchestrator failed"
fi

success "User entrypoint completed"
