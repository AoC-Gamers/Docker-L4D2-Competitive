#!/bin/bash
set -euo pipefail

# Verify that the LGSM_SERVERFILES variable is defined
: "${LGSM_SERVERFILES:?The LGSM_SERVERFILES variable is not defined.}"

#####################################################
# Function library
source "$DIR_INSTALLER_LIB/tools_stack.sh"

# Verify if the script is run as the user ${USER}
check_user "${USER}"

update_server() {
    local platform="$1"
    steamcmd +force_install_dir "${LGSM_SERVERFILES}" +login anonymous +@sSteamCmdForcePlatformType "$platform" +app_update 222860 validate +quit
}

prime_steamcmd() {
    step "Priming SteamCMD runtime"
    steamcmd +login anonymous +quit
}

# Update the server for both platforms
section "L4D2 base install repair"
info "Serverfiles directory: ${LGSM_SERVERFILES}"

prime_steamcmd
step "Validating Windows platform payload"
update_server "windows"
step "Validating Linux platform payload"
update_server "linux"

# If the symbolic link exists in /app/serverfiles, remove it
if [ -L "/app/serverfiles" ]; then
    step "Refreshing /app/serverfiles symlink"
    rm "/app/serverfiles"
fi

# Create the symbolic link pointing to LGSM_SERVERFILES
ln -s "${LGSM_SERVERFILES}" "/app/serverfiles"
success "Base install repair completed"

# Reference: https://github.com/ValveSoftware/steam-for-linux/issues/11522#issuecomment-2512232264
