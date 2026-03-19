#!/bin/bash
set -euo pipefail

# Ensure installer and stack directories are defined
: "${DIR_INSTALLER:?The DIR_INSTALLER variable is not defined.}"
: "${DIR_STACK:?The DIR_STACK variable is not defined.}"

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
        if [ -e "$target" ] && [ ! -L "$target" ]; then
            rm -f "$target"
        fi

        if [ ! -L "$target" ] || [ "$(readlink "$target" 2>/dev/null || true)" != "$src" ]; then
            rm -f "$target"
            ln -s "$src" "$target"
            echo "Symlink created: $target"
        fi
    done
}

echo ""
echo "Creating symlinks for installer binaries"
create_symlinks "/app/installer/bin" "$DIR_INSTALLER/bin"

echo ""
echo "Creating symlinks for installer libraries"
create_symlinks "/app/installer/lib" "$DIR_INSTALLER/lib"

echo ""
echo "Creating symlinks for installer config"
create_symlinks "/app/installer/config" "$DIR_INSTALLER/config"

echo ""
echo "Creating symlinks for stack root"
create_symlinks "/app/stack" "$DIR_STACK" ! -path "/app/stack/hooks/*"

echo ""
echo "Creating symlinks for stack hooks"
create_symlinks "/app/stack/hooks" "$DIR_STACK/hooks"

echo ""
echo "Creating symlinks for stack manifests"
create_symlinks "/app/stack/manifests" "$DIR_STACK/manifests"

echo ""
echo "Creating symlinks for stack profiles"
create_symlinks "/app/stack/profiles" "$DIR_STACK/profiles"

echo "Symlink creation process completed."
