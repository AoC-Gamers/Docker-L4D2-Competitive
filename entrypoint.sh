#!/bin/bash

exit_handler() {
  # Execute the shutdown commands
  echo -e "Stopping ${GAMESERVER}"
  exec gosu "${USER}" ./"${GAMESERVER}" stop
  exitcode=$?
  exit ${exitcode}
}

# Exit trap
echo -e "Loading exit handler"
trap exit_handler SIGQUIT SIGINT SIGTERM

# Get the operating system distribution
DISTRO="$(grep "PRETTY_NAME" /etc/os-release | awk -F = '{gsub(/"/,"",$2);print $2}')"
echo -e ""
echo -e "Welcome to the LinuxGSM"
echo -e "================================================================================"
echo -e "CURRENT TIME: $(date)"
echo -e "BUILD TIME: $(cat /build-time.txt)"
echo -e "GAMESERVER: ${GAMESERVER}"
echo -e "DISTRO: ${DISTRO}"
echo -e ""
echo -e "USER: ${USER}"
echo -e "UID: ${UID}"
echo -e "GID: ${GID}"
if [ -n "${LGSM_PASSWORD}" ]; then
  echo -e "${USER}:${LGSM_PASSWORD}" | chpasswd
else
  echo -e "Password is empty, skipping password change"
fi
echo -e ""
echo -e "LGSM_GITHUBUSER: ${LGSM_GITHUBUSER}"
echo -e "LGSM_GITHUBREPO: ${LGSM_GITHUBREPO}"
echo -e "LGSM_GITHUBBRANCH: ${LGSM_GITHUBBRANCH}"
echo -e "LGSM_LOGDIR: ${LGSM_LOGDIR}"
echo -e "LGSM_SERVERFILES: ${LGSM_SERVERFILES}"
echo -e "LGSM_DATADIR: ${LGSM_DATADIR}"
echo -e "LGSM_CONFIG: ${LGSM_CONFIG}"

echo -e ""
echo -e "Initializing"
echo -e "================================================================================"

# Add environment variables to /etc/environment to make them permanent
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
  echo -e "SSH_PORT=${SSH_PORT:-22}"
  echo -e "DIR_SCRIPTING=/data/server-scripts"
} >> /etc/environment

# Export environment variables
set -o allexport
source /etc/environment
set +o allexport

cd /app || exit

echo -e ""
echo -e "Check Permissions"
echo -e "================================="
echo -e "setting UID to ${UID}"
usermod -u "${UID}" -m -d /data linuxgsm > /dev/null 2>&1
echo -e "setting GID to ${GID}"
groupmod -g "${GID}" linuxgsm
echo -e "updating permissions for /data"
chown -R "${USER}":"${USER}" /data
echo -e "updating permissions for /app"
chown -R "${USER}":"${USER}" /app
export HOME=/data

echo -e ""
echo -e "Custom Docker Scripts"
echo -e "================================="
if ls /app/docker-scripts/*.sh 1> /dev/null 2>&1; then
  for script in /app/docker-scripts/*.sh; do
    echo -e "$script"
    bash "$script"
    echo -e "---"
  done
else
  echo -e "No .sh files found in /app/docker-scripts"
fi

# Change owner and permissions
chown -R linuxgsm:linuxgsm /app /data
chmod -R +x /app /data

echo -e ""
echo -e "Switch to user ${USER}"
echo -e "================================="
exec gosu "${USER}" /app/entrypoint-user.sh &
wait

echo -e ""
echo -e "Keeping the container running..."
echo -e "================================="
tail -f /dev/null