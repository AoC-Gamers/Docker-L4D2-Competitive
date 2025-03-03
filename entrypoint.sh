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

# Obtener la distribución del sistema operativo
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
echo -e ""
echo -e "LGSM_GITHUBUSER: ${LGSM_GITHUBUSER}"
echo -e "LGSM_GITHUBREPO: ${LGSM_GITHUBREPO}"
echo -e "LGSM_GITHUBBRANCH: ${LGSM_GITHUBBRANCH}"
echo -e "LGSM_LOGDIR: ${LGSM_LOGDIR}"
echo -e "LGSM_SERVERFILES: ${LGSM_SERVERFILES}"
echo -e "LGSM_DATADIR: ${LGSM_DATADIR}"
echo -e "LGSM_CONFIG: ${LGSM_CONFIG}"
echo -e "linuxgsm:${LINUXGSM_PASSWORD}" | chpasswd

echo -e ""
echo -e "Initalising"
echo -e "================================================================================"

# Agregar variables de entorno a /etc/environment para que sean permanentes
echo -e "LGSM_GITHUBUSER=${LGSM_GITHUBUSER}" >> /etc/environment
echo -e "LGSM_GITHUBREPO=${LGSM_GITHUBREPO}" >> /etc/environment
echo -e "LGSM_GITHUBBRANCH=${LGSM_GITHUBBRANCH}" >> /etc/environment
echo -e "LGSM_LOGDIR=${LGSM_LOGDIR}" >> /etc/environment
echo -e "LGSM_SERVERFILES=${LGSM_SERVERFILES}" >> /etc/environment
echo -e "LGSM_DATADIR=${LGSM_DATADIR}" >> /etc/environment
echo -e "LGSM_CONFIG=${LGSM_CONFIG}" >> /etc/environment

echo -e "DIR_LEFT4DEAD2=${LGSM_SERVERFILES}/left4dead2" >> /etc/environment
echo -e "DIR_ADDONS=${LGSM_SERVERFILES}/left4dead2/addons" >> /etc/environment
echo -e "DIR_SOURCEMOD=${LGSM_SERVERFILES}/left4dead2/addons/sourcemod" >> /etc/environment
echo -e "DIR_CFG=${LGSM_SERVERFILES}/left4dead2/cfg" >> /etc/environment
echo -e "LINUXGSM_SSHPORT=${LINUXGSM_SSHPORT:-22}" >> /etc/environment
echo -e "DIR_SCRIPTING=/data/server-scripts" >> /etc/environment

# Exportar variables de entorno para la sesión actual
export LGSM_GITHUBUSER=${LGSM_GITHUBUSER}
export LGSM_GITHUBREPO=${LGSM_GITHUBREPO}
export LGSM_GITHUBBRANCH=${LGSM_GITHUBBRANCH}
export LGSM_LOGDIR=${LGSM_LOGDIR}
export LGSM_SERVERFILES=${LGSM_SERVERFILES}
export LGSM_DATADIR=${LGSM_DATADIR}
export LGSM_CONFIG=${LGSM_CONFIG}

export DIR_LEFT4DEAD2=${LGSM_SERVERFILES}/left4dead2
export DIR_ADDONS=${LGSM_SERVERFILES}/left4dead2/addons
export DIR_SOURCEMOD=${LGSM_SERVERFILES}/left4dead2/addons/sourcemod
export DIR_CFG=${LGSM_SERVERFILES}/left4dead2/cfg
export DIR_SCRIPTING=/data/server-scripts
export LINUXGSM_SSHPORT=${LINUXGSM_SSHPORT}

export L4D2_NO_INTALL=${L4D2_NO_INTALL:-"false"}
export L4D2_NO_AUTOSTART=${L4D2_NO_AUTOSTART:-"false"}

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
echo -e "SSH"
echo -e "================================="
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i "s/#Port 22/Port ${LINUXGSM_SSHPORT}/" /etc/ssh/sshd_config
service ssh start

echo -e ""
echo -e "Custom Docker Scripts"
echo -e "================================="
if ls /app/docker-scripts/*.sh 1> /dev/null 2>&1; then
  for script in /app/docker-scripts/*.sh; do
    echo -e "Executing $script"
    bash "$script"
  done
else
  echo -e "No .sh files found in /app/docker-scripts"
fi

echo -e ""
echo -e "Switch to user ${USER}"
echo -e "================================="
exec gosu "${USER}" /app/entrypoint-user.sh &
wait

echo -e ""
echo -e "Manteniendo el contenedor en ejecución..."
echo -e "================================="
tail -f /dev/null