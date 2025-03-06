#!/bin/bash
set -euo pipefail

# Verify that the LGSM_SERVERFILES variable is defined
: "${LGSM_SERVERFILES:?The LGSM_SERVERFILES variable is not defined.}"

#####################################################
# Function library
source "$DIR_SCRIPTING/tools_gameserver.sh"

# Verify if the script is run as the user ${USER}
check_user "${USER}"

update_server() {
    local platform="$1"
    steamcmd +force_install_dir "${LGSM_SERVERFILES}" +login anonymous +@sSteamCmdForcePlatformType "$platform" +app_update 222860 validate +quit
}

# Update the server for both platforms
update_server "windows"
update_server "linux"

# If the symbolic link exists in /app/serverfiles, remove it
if [ -L "/app/serverfiles" ]; then
    rm "/app/serverfiles"
fi

# Create the symbolic link pointing to LGSM_SERVERFILES
ln -s "${LGSM_SERVERFILES}" "/app/serverfiles"

# Reference: https://github.com/ValveSoftware/steam-for-linux/issues/11522#issuecomment-2512232264