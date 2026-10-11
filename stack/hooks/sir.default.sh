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
source "$DIR_INSTALLER_LIB/tools_stack.sh"
source "$DIR_INSTALLER_LIB/stack_component_lib.sh"

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
    stack_install_addons_tree "$DIR_SIR"
    stack_install_cfg_tree "$DIR_SIR"
    stack_install_scripts_tree "$DIR_SIR"
}

##############################
# Main Script:
##############################
# Delete server.cfg file
stack_remove_files_if_present "$DIR_SIR/cfg/server.cfg"

# Delete .dll files in the addons folder
find "$DIR_SIR_ADDONS" -type f -name "*.dll" -print0 |
        while IFS= read -r -d '' path; do
            stack_remove_files_if_present "$path"
        done

if [ "$GIT_DOWNLOAD" = "false" ]; then
    CopyFiles
    echo "Cache copy completed."
    exit 0
fi

CopyFiles
log "Repository modifications completed."
