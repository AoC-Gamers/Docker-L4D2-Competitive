#!/bin/bash
set -euo pipefail

#####################################################
# Basic configuration
: "${DIR_SCRIPTING:?Error: The DIR_SCRIPTING variable is not defined.}"
: "${DIR_LEFT4DEAD2:?Error: The DIR_LEFT4DEAD2 variable is not defined.}"
: "${DIR_CFG:?Error: The DIR_CFG variable is not defined.}"
: "${REPOS_JSON:=$DIR_SCRIPTING/repos.json}"

#####################################################
# Function library
source "$DIR_SCRIPTING/tools_gameserver.sh"

#####################################################
# Variables
GIT_FORCE_DOWNLOAD="${GIT_FORCE_DOWNLOAD:-false}"
SUBSCRIPT_DIR="$DIR_SCRIPTING/git-gameserver"
LOG_FILE="$DIR_SCRIPTING/install_gameserver.log"
CACHE_FILE="$DIR_TMP/cache_gameserver.log"

#####################################################
# Check for repos.json existence
if [[ ! -f "$REPOS_JSON" ]]; then
    echo "Error: The repos.json file was not found in $DIR_SCRIPTING."
    exit 1
fi

# JSON file with the list of paths to be backuped
BACKUP_JSON="$DIR_SCRIPTING/backup_gameserver.json"

#####################################################
# Verify if the script is run as the user ${USER}
check_user "${USER}"

#####################################################
# Load variables from .env
if [[ -f "$DIR_SCRIPTING/.env" ]]; then
    # Load variables ignoring commented lines
    export $(grep -v '^#' "$DIR_SCRIPTING/.env" | xargs)
else
    echo "The .env file was not found in $DIR_SCRIPTING."
fi

#####################################################
# Define installation type (install/update)
if [[ -n "${1:-}" ]]; then
    case "$1" in
        install|0) INSTALL_TYPE="install" ;;
        update|1)  INSTALL_TYPE="update"  ;;
        *) error_exit "Invalid argument. Use 'install' (or 0) for clean installation or 'update' (or 1) for update." ;;
    esac
else
    read -rp "Clean installation (0) or update (1)? " OPTION
    case "$OPTION" in
        0) INSTALL_TYPE="install" ;;
        1) INSTALL_TYPE="update" ;;
        *) error_exit "Invalid option. Use '0' for clean installation or '1' for update." ;;
    esac
fi

#####################################################
# Prepare 32-bit libraries and remove duplicates
if [ -d "$HOME/.steam/sdk32" ]; then
    rm -rf "$HOME/.steam/sdk32"
fi
if [ -d "$HOME/.steam/sdk64" ]; then
    rm -rf "$HOME/.steam/sdk64"
fi

mkdir -p "$HOME/.steam/sdk32" "$HOME/.steam/sdk64"

cp -v "$HOME/.local/share/Steam/steamcmd/linux32/"* "$HOME/.steam/sdk32"
cp -v "$HOME/.local/share/Steam/steamcmd/linux64/steamclient.so" "$HOME/.steam/sdk64/steamclient.so"

if [[ -e "$LGSM_SERVERFILES/bin/libstdc++.so.6" ]]; then
    rm "$LGSM_SERVERFILES/bin/libstdc++.so.6" "$LGSM_SERVERFILES/bin/dedicated/libstdc++.so.6"
    log "Removed libstdc++.so.6 for compatibility with extensions."
else
    log "libstdc++.so.6 not detected locally."
fi

if [[ -e "$LGSM_SERVERFILES/bin/libgcc_s.so.1" ]]; then
    rm "$LGSM_SERVERFILES/bin/libgcc_s.so.1" "$LGSM_SERVERFILES/bin/dedicated/libgcc_s.so.1"
    log "Removed libgcc_s.so.1 for compatibility with extensions."
else
    log "libgcc_s.so.1 not detected locally."
fi

#####################################################
# Temporary directory
mkdir -p "$DIR_TMP"
cd "$DIR_TMP" || error_exit "Could not access the temporary directory $DIR_TMP."

# Create cache file if it does not exist
if [[ ! -f "$CACHE_FILE" ]]; then
    touch "$CACHE_FILE"
fi

#####################################################
# Auxiliary functions for Git
get_latest_commit_hash() {
    local repo_dir="$1"
    git -C "$repo_dir" rev-parse HEAD || error_exit "Could not get the latest hash in $repo_dir."
}

save_commit_hash() {
    local repo_name="$1"
    local commit_hash="$2"
    sed -i "/^${repo_name}:/d" "$CACHE_FILE"
    echo "$repo_name:$commit_hash" >> "$CACHE_FILE"
}

has_repo_changed() {
    local repo_name="$1"
    local new_hash="$2"
    if [[ -f "$CACHE_FILE" ]]; then
        local old_hash
        old_hash=$(grep "^${repo_name}:" "$CACHE_FILE" | cut -d':' -f2)
        if [[ "$old_hash" == "$new_hash" ]]; then
            return 1  # No changes
        fi
    fi
    return 0  # Changes or not found
}

#####################################################
# Clean server files
clean_instance_logs() {
    local index=1
    while true; do
        local DIR_NEW_SOURCEMOD="${DIR_SOURCEMOD}${index}"
        if [ -d "$DIR_NEW_SOURCEMOD" ]; then
            log "Cleaning logs in $DIR_NEW_SOURCEMOD..."
            if ls "$DIR_NEW_SOURCEMOD/logs/errors_"*.log &> /dev/null; then
                rm "$DIR_NEW_SOURCEMOD/logs/errors_"*.log
            fi
        else
            log "Directory $DIR_NEW_SOURCEMOD not found. Ending log cleaning."
            break
        fi
        ((index++))
    done
}

#####################################################
# Backup and restore system
backup_files() {
    local backup_json="$1"
    local base_dir="$2"
    jq -r 'to_entries[] | "\(.key) \(.value[])"' "$backup_json" | while read -r folder file; do
        local src="$base_dir/$folder/$file"
        local dest="$base_dir/$file"
        if [[ -f "$src" ]]; then
            mkdir -p "$(dirname "$dest")"
            mv "$src" "$dest"
            log "Backed up file $src to $dest"
        elif [[ -d "$src" ]]; then
            mkdir -p "$(dirname "$dest")"
            mv "$src" "$dest"
            log "Backed up directory $src to $dest"
        else
            log "Skipping $src as it does not exist or is not a valid file/directory"
        fi
    done
}

restore_files() {
    local backup_json="$1"
    local base_dir="$2"
    jq -r 'to_entries[] | "\(.key) \(.value[])"' "$backup_json" | while read -r folder file; do
        local src="$base_dir/$file"
        local dest="$base_dir/$folder/$file"
        if [[ -f "$src" ]]; then
            mkdir -p "$(dirname "$dest")"
            mv "$src" "$dest"
            log "Restored $src to $dest"
        fi
    done
}

#####################################################
# Process cleaning in case of update
if [ "$INSTALL_TYPE" == "update" ]; then
    # Backup files before cleaning
    backup_files "$BACKUP_JSON" "$DIR_SOURCEMOD"

    verify_and_delete_dir "$DIR_SOURCEMOD/data"
    verify_and_delete_dir "$DIR_SOURCEMOD/extensions"
    verify_and_delete_dir "$DIR_SOURCEMOD/gamedata"
    verify_and_delete_dir "$DIR_SOURCEMOD/configs"
    verify_and_delete_dir "$DIR_SOURCEMOD/plugins"
    verify_and_delete_dir "$DIR_SOURCEMOD/scripting"
    verify_and_delete_dir "$DIR_SOURCEMOD/translations"
    clean_instance_logs
    mkdir -p "$DIR_SOURCEMOD/configs"
    verify_and_delete_dir "$DIR_CFG/cfgogl"
    verify_and_delete_dir "$DIR_CFG/sourcemod"
    verify_and_delete_dir "$DIR_CFG/stripper"

    # Restore files after cleaning
    restore_files "$BACKUP_JSON" "$DIR_SOURCEMOD"
fi

#####################################################
# Repository installation
jq -c '.[]' "$REPOS_JSON" | while IFS= read -r repo_item; do
    # Extract values from JSON
    repo_url=$(echo "$repo_item" | jq -r '.repo_url' | envsubst)
    folder=$(echo "$repo_item" | jq -r '.folder')
    branch=$(echo "$repo_item" | jq -r '.branch')

    GIT_DOWNLOAD=false

    # If forced download, or if the folder does not exist, clone
    if [[ "${GIT_FORCE_DOWNLOAD:-false}" == "true" ]]; then
        GIT_DOWNLOAD=true
        rm -rf "$folder"
    elif [[ -d "$folder" ]]; then
        echo "Checking for changes in $folder..."
        if [[ "$branch" == "default" ]]; then
            remote_hash=$(git ls-remote "$repo_url" HEAD | awk '{print $1}')
        else
            remote_hash=$(git ls-remote -h "$repo_url" "$branch" | awk '{print $1}')
        fi

        if has_repo_changed "$folder" "$remote_hash"; then
            GIT_DOWNLOAD=true
            echo "The repository $folder has changed (will be updated)."
            rm -rf "$folder"
        else
            echo "The repository $folder has not changed. Using cache."
            GIT_DOWNLOAD=false
        fi
    else
        GIT_DOWNLOAD=true
    fi

    # Clone or update the repository if necessary
    if [[ "$GIT_DOWNLOAD" == "true" ]]; then
        echo "Cloning $repo_url into folder $folder (branch: $branch)..."
        if [[ "$branch" == "default" ]]; then
            git clone "$repo_url" "$folder" || { echo "Failed to clone $repo_url"; exit 1; }
        else
            git clone -b "$branch" "$repo_url" "$folder" || { echo "Failed to clone $repo_url on branch $branch"; exit 1; }
        fi
        latest_hash=$(get_latest_commit_hash "$folder")
        save_commit_hash "$folder" "$latest_hash"
    fi

    # Optional: execute a modification subscript for the repository
    subscript_file="$DIR_SCRIPTING/git-gameserver/${folder}.${branch}.sh"
    if [[ -f "$subscript_file" ]]; then
        echo "Executing subscript $subscript_file for $folder..."
        bash "$subscript_file" "$folder" "$INSTALL_TYPE" "$GIT_DOWNLOAD"
    else
        echo "No subscript found for $folder. Skipping..."
    fi

done

log "--------------------------------------"
log "L4D2 competitive mode installation"
log "complete in mode: $INSTALL_TYPE"
log "--------------------------------------"
