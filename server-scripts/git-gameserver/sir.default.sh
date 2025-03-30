#!/bin/bash
# sir.default.sh
# Subscript to apply specific modifications to the 'default' branch of L4D2-Competitive-Rework.
set -euo pipefail

if [ -z "$1" ]; then
    echo "Usage: $0 <REPO_DIR> <INSTALL_TYPE> <GIT_DOWNLOAD>"
    echo "  REPO_DIR: Repository location."
    echo "  INSTALL_TYPE: ('install'|'update') Installation type. def: install"
    echo "  GIT_DOWNLOAD: (true|false) Downloaded from remote repository. def: false"
    echo ""
    echo "Example:"
    echo "  bash sir.default.sh /app/tmp/sir update true"
    exit 1
fi

# Resources
source "$DIR_SCRIPTING/tools_gameserver.sh"

REPO_DIR="$1"
INSTALL_TYPE="${2:-install}"
GIT_DOWNLOAD="${3:-false}"

##############################
# Environment variables:
##############################
DIR_SIR="$REPO_DIR"
DIR_SIR_ADDONS="$DIR_SIR/addons"
DIR_SIR_SOURCEMOD="$DIR_SIR_ADDONS/sourcemod"
DIR_SIR_METAMOD="$DIR_SIR_ADDONS/metamod"

##############################
# Helper functions:
##############################
CopyFiles() {
    cp -r "$DIR_SIR/addons" "$DIR_LEFT4DEAD2"
    cp -r "$DIR_SIR/cfg" "$DIR_LEFT4DEAD2"
    cp -r "$DIR_SIR/scripts" "$DIR_LEFT4DEAD2"
}

##############################
# Main Script:
##############################
if [ "$GIT_DOWNLOAD" = "false" ]; then
    CopyFiles
    echo "Cache copy completed."
    exit 0
fi

# Delete server.cfg file
verify_and_delete_file "$DIR_SIR/cfg/server.cfg"

# Delete .dll files in the addons folder
find "$DIR_SIR_ADDONS" -type f -name "*.dll" -delete

CopyFiles
log "Repository modifications completed."