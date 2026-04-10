#!/bin/bash

source "/app/installer/lib/tools_stack.sh"

export DIR_APP="/app"
export DIR_TMP="/app/tmp"
export DIR_INSTALLER="/data/installer"
export DIR_INSTALLER_BIN="/data/installer/bin"
export DIR_INSTALLER_LIB="/data/installer/lib"
export DIR_INSTALLER_CONFIG="/data/installer/config"
export DIR_INSTALLER_STATE="/data/installer/state"
export DIR_STACK="/data/stack"
export DIR_STACK_HOOKS="/data/stack/hooks"
export DIR_LEFT4DEAD2="${LGSM_SERVERFILES}/left4dead2"
export DIR_ADDONS="${DIR_LEFT4DEAD2}/addons"
export DIR_SOURCEMOD="${DIR_ADDONS}/sourcemod"
export DIR_CFG="${DIR_LEFT4DEAD2}/cfg"
export GAMESERVER="${GAMESERVER:-l4d2server}"

exit_handler() {
  # Execute the shutdown commands
  section "Stopping primary instance"
  info "Instance: ${GAMESERVER}"
  exec gosu "${USER}" ./"${GAMESERVER}" stop
  exitcode=$?
  exit ${exitcode}
}

# Exit trap
info "Loading exit handler"
trap exit_handler SIGQUIT SIGINT SIGTERM

# Get the operating system distribution
DISTRO="$(grep "PRETTY_NAME" /etc/os-release | awk -F = '{gsub(/"/,"",$2);print $2}')"
section "LinuxGSM runtime bootstrap"
render_runtime_metadata() {
  info "Current time: $(date)"
  info "Build time: $(cat /build-time.txt)"
  info "Primary instance executable: ${GAMESERVER}"
  info "Distro: ${DISTRO}"
  info "User: ${USER}"
  info "UID: ${UID}"
  info "GID: ${GID}"
  info "LGSM GitHub user: ${LGSM_GITHUBUSER}"
  info "LGSM GitHub repo: ${LGSM_GITHUBREPO}"
  info "LGSM branch: ${LGSM_GITHUBBRANCH}"
  info "LGSM log dir: ${LGSM_LOGDIR}"
  info "LGSM serverfiles: ${LGSM_SERVERFILES}"
  info "LGSM data dir: ${LGSM_DATADIR}"
  info "LGSM config dir: ${LGSM_CONFIG}"
}

render_runtime_metadata

if [ -n "${LGSM_PASSWORD}" ]; then
  echo -e "${USER}:${LGSM_PASSWORD}" | chpasswd
else
  warn "Password is empty. Skipping password change."
fi

persist_runtime_environment() {
  cat > /etc/environment <<EOF
PATH=${PATH}
GAMESERVER=${GAMESERVER}
DISTRO="${DISTRO}"
USER=${USER}
UID=${UID}
GID=${GID}
LGSM_GITHUBUSER=${LGSM_GITHUBUSER}
LGSM_GITHUBREPO=${LGSM_GITHUBREPO}
LGSM_GITHUBBRANCH=${LGSM_GITHUBBRANCH}
LGSM_LOGDIR=${LGSM_LOGDIR}
LGSM_SERVERFILES=${LGSM_SERVERFILES}
LGSM_DATADIR=${LGSM_DATADIR}
LGSM_CONFIG=${LGSM_CONFIG}
DIR_APP=${DIR_APP}
DIR_TMP=${DIR_TMP}
DIR_INSTALLER=${DIR_INSTALLER}
DIR_INSTALLER_BIN=${DIR_INSTALLER_BIN}
DIR_INSTALLER_LIB=${DIR_INSTALLER_LIB}
DIR_INSTALLER_CONFIG=${DIR_INSTALLER_CONFIG}
DIR_INSTALLER_STATE=${DIR_INSTALLER_STATE}
DIR_STACK=${DIR_STACK}
DIR_STACK_HOOKS=${DIR_STACK_HOOKS}
DIR_LEFT4DEAD2=${DIR_LEFT4DEAD2}
DIR_ADDONS=${DIR_ADDONS}
DIR_SOURCEMOD=${DIR_SOURCEMOD}
DIR_CFG=${DIR_CFG}
SSH_PORT=${SSH_PORT:-22}
STACK_PROFILE=${STACK_PROFILE:-default}
REPO_RESOURCES_DIR=${REPO_RESOURCES_DIR:-/data/resources}
L4D2_INSTALL=${L4D2_INSTALL:-normal}
L4D2_AUTOSTART=${L4D2_AUTOSTART:-true}
L4D2_UPDATER=${L4D2_UPDATER:-true}
GEOIPUPDATE_ENABLED=${GEOIPUPDATE_ENABLED:-false}
GEOIPUPDATE_ACCOUNT_ID=${GEOIPUPDATE_ACCOUNT_ID:-}
GEOIPUPDATE_EDITION_ID=${GEOIPUPDATE_EDITION_ID:-GeoLite2-City}
GEOIPUPDATE_LICENSE_KEY=${GEOIPUPDATE_LICENSE_KEY:-}
EOF
}

section "Runtime initialization"

# Add environment variables to /etc/environment to make them permanent
step "Persisting runtime environment to /etc/environment"
persist_runtime_environment

# Export environment variables
set -o allexport
source /etc/environment
set +o allexport

cd /app || exit

section "Permissions and ownership"
step "Setting UID to ${UID}"
usermod -u "${UID}" -m -d /data linuxgsm > /dev/null 2>&1
step "Setting GID to ${GID}"
groupmod -g "${GID}" linuxgsm
step "Updating ownership for /data"
chown -R "${USER}":"${USER}" /data
step "Updating ownership for /app"
chown -R "${USER}":"${USER}" /app
export HOME=/data

section "Container bootstrap scripts"
if ls /app/container/bootstrap/*.sh 1> /dev/null 2>&1; then
  for script in /app/container/bootstrap/*.sh; do
    step "Running $script"
    if bash "$script"; then
      success "Completed $script"
    else
      error_exit "Bootstrap script failed: $script"
    fi
  done
else
  info "No .sh files found in /app/container/bootstrap"
fi

step "Reloading environment after bootstrap scripts"
set -o allexport
source /etc/environment
set +o allexport

# Change owner and permissions
step "Setting executable permissions on /app and /data"
chown -R linuxgsm:linuxgsm /app /data
chmod -R +x /app /data

section "Hand-off to user runtime"
info "Switching to user ${USER}"
exec gosu "${USER}" /app/container/entrypoint-user.sh &
wait

section "Container idle"
info "Keeping the container running"
tail -f /dev/null
