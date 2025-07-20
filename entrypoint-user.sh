#!/bin/bash

exit_handler_user() {
  # Execute the shutdown commands
  echo -e "Stopping ${GAMESERVER}"
  ./"${GAMESERVER}" stop
  exitcode=$?
  exit ${exitcode}
}

# Exit trap
echo -e "Loading exit handler"
trap exit_handler_user SIGQUIT SIGINT SIGTERM

# Setup game server
if [ ! -f "${GAMESERVER}" ]; then
  echo -e ""
  echo -e "Creating ${GAMESERVER}"
  echo -e "================================="
  ./linuxgsm.sh "${GAMESERVER}"
fi

# Symlink LGSM_CONFIG to /app/lgsm/config-lgsm
if [ ! -d "/app/lgsm/config-lgsm" ]; then
  echo -e ""
  echo -e "Creating symlink for ${LGSM_CONFIG}"
  echo -e "================================="
  ln -s "${LGSM_CONFIG}" "/app/lgsm/config-lgsm"
fi

# Symlink LGSM_SERVERFILES to /app/serverfiles
if [ ! -d "/app/serverfiles" ]; then
  echo -e ""
  echo -e "Creating symlink for ${LGSM_SERVERFILES}"
  echo -e "================================="
  ln -s "${LGSM_SERVERFILES}" "/app/serverfiles"
fi

# Symlink LGSM_LOGDIR to /app/log
if [ ! -d "/app/log" ]; then
  echo -e ""
  echo -e "Creating symlink for ${LGSM_LOGDIR}"
  echo -e "================================="
  ln -s "${LGSM_LOGDIR}" "/app/log"
fi

# Symlink LGSM_DATADIR to /app/lgsm/data
if [ ! -d "/app/lgsm/data" ]; then
  echo -e ""
  echo -e "Creating symlink for ${LGSM_DATADIR}"
  echo -e "================================="
  ln -s "${LGSM_DATADIR}" "/app/lgsm/data"
fi

# Create folder /data/server-scripts
if [ ! -d "$DIR_SCRIPTING" ]; then
  echo -e ""
  echo -e "Creating $DIR_SCRIPTING"
  echo -e "================================="
  mkdir -p $DIR_SCRIPTING
fi

# npm install in /app/lgsm
if [ -f "/app/lgsm/package.json" ]; then
  echo -e ""
  echo -e "Running npm install in /app/lgsm"
  echo -e "================================="
  cd /app/lgsm || exit
  npm install
  cd /app || exit
fi

# Clear modules directory if not master
if [ "${LGSM_GITHUBBRANCH}" != "master" ]; then
  echo -e "Not master branch, clearing modules directory"
  rm -rf /app/lgsm/modules/*
  ./"${GAMESERVER}" update-lgsm
elif [ -d "/app/lgsm/modules" ]; then
  echo -e "Ensure all modules are executable"
  chmod +x /app/lgsm/modules/*
fi

# Enable developer mode
if [ "${LGSM_DEV}" == "true" ]; then
  echo -e "Developer mode enabled"
  ./"${GAMESERVER}" developer
fi

echo -e ""
echo -e "Installing ${GAMESERVER}"
echo -e "================================="
L4D2_FRESH_INSTALL="false"
install=0

# Function to clean Steam password from environment
clean_steam_password() {
  if [ -n "${STEAM_PASSWD:-}" ]; then
    echo -e "🔒 Cleaning STEAM_PASSWD from environment for security..."
    unset STEAM_PASSWD
    export STEAM_PASSWD=""
  fi
}

# Check if Steam credentials are provided
if [ -n "${STEAM_USER:-}" ] && [ -n "${STEAM_PASSWD:-}" ]; then
  echo -e "Steam credentials detected - using official Steam installation method"
  
  # Configure Steam credentials in secrets-common.cfg
  SECRETS_CONFIG="${LGSM_CONFIG}/${GAMESERVER}/secrets-common.cfg"
  
  if [ ! -f "${SECRETS_CONFIG}" ]; then
    echo -e "Creating secrets-common.cfg with Steam credentials"
    mkdir -p "$(dirname "${SECRETS_CONFIG}")"
    touch "${SECRETS_CONFIG}"
  fi
  
  # Add Steam credentials if not already present
  if ! grep -q "steamuser=" "${SECRETS_CONFIG}"; then
    echo "steamuser=${STEAM_USER}" >> "${SECRETS_CONFIG}"
  fi
  
  if ! grep -q "steampass=" "${SECRETS_CONFIG}"; then
    echo "steampass=${STEAM_PASSWD}" >> "${SECRETS_CONFIG}"
  fi
  
  echo -e "⚠️  IMPORTANT: If your Steam account is protected with SteamGuard Mobile Authenticator,"
  echo -e "    you must authorize this login from your mobile device when prompted."
  echo -e ""
  
  # Official Steam installation
  if [ -z "$(ls -A -- "/data/serverfiles" 2> /dev/null)" ]; then
    echo -e "Installing ${GAMESERVER} using official Steam method"
    ./"${GAMESERVER}" auto-install
    install=1
    L4D2_FRESH_INSTALL="true"
    
    # Clean password after successful installation
    clean_steam_password
    echo -e "✅ Installation completed. Steam password cleared from environment."
  else
    echo -e "Skip installing ${GAMESERVER} as serverfiles directory is not empty"
    # Sponsor to display LinuxGSM logo
    ./"${GAMESERVER}" sponsor
    clean_steam_password
  fi
  
elif [ "${L4D2_NO_INSTALL}" == "true" ]; then
  echo -e "Skip installing ${GAMESERVER} as L4D2_NO_INSTALL is set to true"
  echo -e "To install manually, run: ./${GAMESERVER} auto-install"
  
else
  echo -e "Using community workaround method (l4d2_fix_install.sh)"
  echo -e "No Steam credentials provided - using anonymous installation"
  
  if [ -n "$(ls -A -- "${LGSM_SERVERFILES}" 2> /dev/null)" ]; then
    echo -e "Skip installing ${GAMESERVER} as ${LGSM_SERVERFILES} is not empty"
  else
    bash $DIR_SCRIPTING/l4d2_fix_install.sh
    L4D2_FRESH_INSTALL="true"
  fi
fi

echo -e ""
echo -e "Install GameServer Files"
echo -e "================================="
if [ "${L4D2_FRESH_INSTALL}" == "false" ]; then
  echo -e "Skip installing game server files as it is not a fresh install"
else
  bash $DIR_SCRIPTING/install_gameserver.sh install
fi

bash /app/docker-scripts/l4d2_updater.sh

echo -e ""
echo -e "Config Profile"
echo -e "================================="
if [ ! -f $HOME/.bashrc ]; then
  echo -e "Creating $HOME/.bashrc"
  cp /etc/skel/.bashrc $HOME/.bashrc
else
  echo -e "$HOME/.bashrc already exists"
fi

if [ ! -d $HOME/.ssh ]; then
  echo -e "Creating $HOME/.ssh"
  mkdir -p $HOME/.ssh
  chmod 700 $HOME/.ssh
else 
  echo -e "$HOME/.ssh already exists"
fi

if [ ! -f $HOME/.ssh/authorized_keys ]; then
  echo -e "Creating authorized_keys"
  touch $HOME/.ssh/authorized_keys
  chmod 600 $HOME/.ssh/authorized_keys

  if [ -n "${SSH_KEY}" ]; then
    IFS=',' read -ra KEYS <<< "${SSH_KEY}"
    for key in "${KEYS[@]}"; do
      echo -e "${key}" >> $HOME/.ssh/authorized_keys
    done
  else
    echo -e "SSH_KEY is empty, skipping key addition"
  fi
  
else
  echo -e "authorized_keys already exists"
fi

echo -e ""
echo -e "Starting ${GAMESERVER}"
echo -e "================================="
if [ "${L4D2_FRESH_INSTALL}" == "true" ]; then
  echo -e "Skip starting ${GAMESERVER} as it is a fresh install"
    $DIR_SCRIPTING/clone_l4d2server.sh 0  > /dev/null 2>&1
elif [ "${L4D2_NO_AUTOSTART}" == "true" ]; then
  echo -e "Skip starting ${GAMESERVER} as L4D2_NO_AUTOSTART is set to true"
else
  echo -e "Done"
  bash $HOME/menu_gameserver.sh start
fi