#!/bin/bash

source "/app/installer/lib/tools_stack.sh"

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

section "Runtime initialization"

# Add environment variables to /etc/environment to make them permanent
step "Persisting runtime environment to /etc/environment"
{
  echo -e "GAMESERVER=${GAMESERVER}"
  echo -e "DISTRO=\"${DISTRO}\""
  echo -e "USER=${USER}"
  echo -e "UID=${UID}"
  echo -e "GID=${GID}"

  echo -e "LGSM_GITHUBUSER=${LGSM_GITHUBUSER}"
  echo -e "LGSM_GITHUBREPO=${LGSM_GITHUBREPO}"
  echo -e "LGSM_GITHUBBRANCH=${LGSM_GITHUBBRANCH}"
  echo -e "LGSM_LOGDIR=${LGSM_LOGDIR}"
  echo -e "LGSM_SERVERFILES=${LGSM_SERVERFILES}"
  echo -e "LGSM_DATADIR=${LGSM_DATADIR}"
  echo -e "LGSM_CONFIG=${LGSM_CONFIG}"
  
  echo -e "DIR_LEFT4DEAD2=${LGSM_SERVERFILES}/left4dead2"
  echo -e "DIR_ADDONS=${LGSM_SERVERFILES}/left4dead2/addons"
  echo -e "DIR_SOURCEMOD=${LGSM_SERVERFILES}/left4dead2/addons/sourcemod"
  echo -e "DIR_CFG=${LGSM_SERVERFILES}/left4dead2/cfg"
  echo -e "DIR_INSTALLER=/data/installer"
  echo -e "DIR_INSTALLER_BIN=/data/installer/bin"
  echo -e "DIR_INSTALLER_LIB=/data/installer/lib"
  echo -e "DIR_INSTALLER_CONFIG=/data/installer/config"
  echo -e "DIR_INSTALLER_STATE=/data/installer/state"
  echo -e "DIR_STACK=/data/stack"
  echo -e "DIR_STACK_HOOKS=/data/stack/hooks"
  echo -e "SSH_PORT=${SSH_PORT:-22}"
} >> /etc/environment

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