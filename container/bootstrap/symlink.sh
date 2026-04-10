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
        local relative_path
        relative_path="${src#$src_dir/}"
        local target="$dest_dir/$relative_path"

        mkdir -p "$(dirname "$target")"
        if [ -d "$target" ] && [ ! -L "$target" ]; then
            rm -rf "$target"
        elif [ -e "$target" ] && [ ! -L "$target" ]; then
            rm -f "$target"
        fi

        if [ ! -L "$target" ] || [ "$(readlink "$target" 2>/dev/null || true)" != "$src" ]; then
            rm -f "$target"
            ln -s "$src" "$target"
            echo "Symlink created: $target"
        fi
    done
}

########################################
# Function: cleanup_stale_symlinks
# Removes symlinks in a managed destination tree when their source file
# no longer exists in the current immutable /app tree.
#
# Parameters:
#   $1: Source directory
#   $2: Destination directory
########################################
cleanup_stale_symlinks() {
    local src_dir="$1"
    local dest_dir="$2"

    [ -d "$dest_dir" ] || return 0

    find "$dest_dir" -type l | while IFS= read -r target; do
        local relative_path
        relative_path="${target#$dest_dir/}"
        local expected_source="$src_dir/$relative_path"

        if [ ! -e "$expected_source" ]; then
            rm -f "$target"
            echo "Stale symlink removed: $target"
        fi
    done
}

echo ""
echo "Creating symlinks for installer binaries"
cleanup_stale_symlinks "/app/installer/bin" "$DIR_INSTALLER/bin"
create_symlinks "/app/installer/bin" "$DIR_INSTALLER/bin"

echo ""
echo "Creating symlinks for installer libraries"
cleanup_stale_symlinks "/app/installer/lib" "$DIR_INSTALLER/lib"
create_symlinks "/app/installer/lib" "$DIR_INSTALLER/lib"

echo ""
echo "Creating symlinks for installer config"
cleanup_stale_symlinks "/app/installer/config" "$DIR_INSTALLER/config"
create_symlinks "/app/installer/config" "$DIR_INSTALLER/config"

echo ""
echo "Creating symlinks for stack root files"
cleanup_stale_symlinks "/app/stack" "$DIR_STACK"
create_symlinks "/app/stack" "$DIR_STACK" -maxdepth 1 -type f

echo ""
echo "Creating symlinks for stack hooks"
cleanup_stale_symlinks "/app/stack/hooks" "$DIR_STACK/hooks"
create_symlinks "/app/stack/hooks" "$DIR_STACK/hooks"

echo ""
echo "Creating symlinks for stack manifests"
cleanup_stale_symlinks "/app/stack/manifests" "$DIR_STACK/manifests"
create_symlinks "/app/stack/manifests" "$DIR_STACK/manifests"

echo ""
echo "Creating symlinks for stack profiles"
cleanup_stale_symlinks "/app/stack/profiles" "$DIR_STACK/profiles"
create_symlinks "/app/stack/profiles" "$DIR_STACK/profiles"

echo "Symlink creation process completed."
