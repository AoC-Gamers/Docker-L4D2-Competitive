#!/bin/bash
# example.default.sh
# Subscript to apply specific modifications to the 'default' branch of Example.
set -euo pipefail

if [ -z "$1" ]; then
    echo "Usage: $0 <REPO_DIR> <INSTALL_TYPE> <GIT_DOWNLOAD>"
    echo "  REPO_DIR: Repository location."
    echo "  INSTALL_TYPE: ('install'|'update') Installation type. def: install"
    echo "  GIT_DOWNLOAD: (true|false) Downloaded from remote repository. def: false"
    echo ""
    echo "Example:"
    echo "  bash example.default.sh /app/tmp/example update true"
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

##############################
# Auxiliary functions:
##############################
CopyFiles() {
}

##############################
# Main Script:
##############################
if [ "$GIT_DOWNLOAD" = "false" ]; then
    CopyFiles
    echo "Cache copy completed."
    exit 0
fi

CopyFiles
log "Repository modifications completed."