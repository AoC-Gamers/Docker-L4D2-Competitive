#!/bin/bash
set -euo pipefail

# Ensure DIR_SCRIPTING is defined
: "${DIR_SCRIPTING:?The DIR_SCRIPTING variable is not defined.}"

########################################
# Function: create_symlinks
# Creates symbolic links for all files in a source directory,
# copying them to the destination directory, applying exclusion filters for 'find'.
#
# Parameters:
#   $1: Source directory
#   $2: Destination directory
#   $3...: Additional options for 'find' (exclusion filters)
########################################
create_symlinks() {
    local src_dir="$1"
    local dest_dir="$2"
    shift 2
    local find_filters=("$@")
    
    mkdir -p "$dest_dir"
    
    find "$src_dir" -type f "${find_filters[@]}" | while IFS= read -r src; do
        local filename
        filename=$(basename "$src")
        local target="$dest_dir/$filename"
        if [ ! -L "$target" ]; then
            ln -s "$src" "$target"
            echo "Symlink created: $target"
        fi
    done
}

########################################
# Special symlink for menu_gameserver.sh
########################################
echo "Creating symlink for menu_gameserver.sh (located in /data)"
if [ ! -L "/data/menu_gameserver.sh" ]; then
    ln -s "/app/server-scripts/menu_gameserver.sh" "/data/menu_gameserver.sh"
    echo "Symlink created: /data/menu_gameserver.sh"
fi

########################################
# Symlinks for files in /app/server-scripts, except
# menu_gameserver.sh and the git-gameserver subfolder
########################################
echo ""
echo "Creating symlinks for files in /app/server-scripts"
mkdir -p "$DIR_SCRIPTING"
create_symlinks "/app/server-scripts" "$DIR_SCRIPTING" ! -name "menu_gameserver.sh" ! -path "/app/server-scripts/git-gameserver/*"

########################################
# Symlinks for files in /app/server-scripts/git-gameserver
########################################
echo ""
echo "Creating symlinks for files in /app/server-scripts/git-gameserver"
create_symlinks "/app/server-scripts/git-gameserver" "$DIR_SCRIPTING/git-gameserver"

echo "Symlink creation process completed."
