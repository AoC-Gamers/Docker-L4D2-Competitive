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

find "$HOME/.local/share/Steam/steamcmd/linux32/" -maxdepth 1 -type f -exec cp -v {} "$HOME/.steam/sdk32" \;
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
save_source_state() {
    local source_name="$1"
    local source_state="$2"

    if [[ -f "$CACHE_FILE" ]]; then
        grep -Fv "${source_name}:" "$CACHE_FILE" > "${CACHE_FILE}.tmp" || true
        mv "${CACHE_FILE}.tmp" "$CACHE_FILE"
    fi

    echo "$source_name:$source_state" >> "$CACHE_FILE"
}

has_source_changed() {
    local source_name="$1"
    local new_state="$2"

    if [[ -f "$CACHE_FILE" ]]; then
        local old_state
        old_state=$(grep -F "${source_name}:" "$CACHE_FILE" | tail -n 1 | cut -d':' -f2-)
        if [[ "$old_state" == "$new_state" ]]; then
            return 1  # No changes
        fi
    fi
    return 0  # Changes or not found
}

get_latest_commit_hash() {
    local repo_dir="$1"
    git -C "$repo_dir" rev-parse HEAD || error_exit "Could not get the latest hash in $repo_dir."
}

resolve_github_release_asset() {
    local github_repo="$1"
    local release_tag="$2"
    local asset_name="$3"
    local asset_name_glob="$4"
    local encoded_tag
    local api_url
    local release_json
    local matched_asset_name=""
    local asset_download_url
    local asset_updated_at
    local candidate_name
    local candidate_url
    local candidate_updated_at

    encoded_tag=$(jq -rn --arg value "$release_tag" '$value|@uri')
    api_url="https://api.github.com/repos/${github_repo}/releases/tags/${encoded_tag}"
    release_json=$(github_api_request "$api_url") || error_exit "Could not fetch release metadata for ${github_repo}@${release_tag}."

    if [[ -n "$asset_name" && "$asset_name" != "null" ]]; then
        matched_asset_name="$asset_name"
        asset_download_url=$(echo "$release_json" | jq -r --arg asset_name "$asset_name" '.assets[] | select(.name == $asset_name) | .browser_download_url' | head -n 1)
        asset_updated_at=$(echo "$release_json" | jq -r --arg asset_name "$asset_name" '.assets[] | select(.name == $asset_name) | .updated_at' | head -n 1)
    else
        while IFS=$'\t' read -r candidate_name candidate_url candidate_updated_at; do
            [[ -n "$candidate_name" ]] || continue

            if [[ "$candidate_name" == $asset_name_glob ]]; then
                if [[ -z "$asset_updated_at" || "$candidate_updated_at" > "$asset_updated_at" ]]; then
                    matched_asset_name="$candidate_name"
                    asset_download_url="$candidate_url"
                    asset_updated_at="$candidate_updated_at"
                fi
            fi
        done < <(echo "$release_json" | jq -r '.assets[] | [.name, .browser_download_url, .updated_at] | @tsv')
    fi

    if [[ -z "$asset_download_url" || "$asset_download_url" == "null" ]]; then
        if [[ -n "$asset_name_glob" && "$asset_name_glob" != "null" ]]; then
            error_exit "No asset matching '${asset_name_glob}' was found in ${github_repo}@${release_tag}."
        fi

        error_exit "Asset '${asset_name}' not found in ${github_repo}@${release_tag}."
    fi

    if [[ -z "$asset_updated_at" || "$asset_updated_at" == "null" ]]; then
        error_exit "Could not determine update state for asset '${matched_asset_name}' in ${github_repo}@${release_tag}."
    fi

    printf '%s\n%s\n%s\n' "$matched_asset_name" "$asset_download_url" "$asset_updated_at"
}

download_git_source() {
    local repo_url="$1"
    local folder="$2"
    local branch="$3"
    local source_download=false
    local remote_state

    if [[ "${GIT_FORCE_DOWNLOAD:-false}" == "true" ]]; then
        source_download=true
        rm -rf "$folder"
    elif [[ -d "$folder" ]]; then
        echo "Checking for changes in $folder..."
        if [[ "$branch" == "default" ]]; then
            remote_state=$(git ls-remote "$repo_url" HEAD | awk '{print $1}')
        else
            remote_state=$(git ls-remote -h "$repo_url" "$branch" | awk '{print $1}')
        fi

        if has_source_changed "$folder" "$remote_state"; then
            source_download=true
            echo "The repository $folder has changed (will be updated)."
            rm -rf "$folder"
        else
            echo "The repository $folder has not changed. Using cache."
        fi
    else
        source_download=true
    fi

    if [[ "$source_download" == "true" ]]; then
        echo "Cloning $repo_url into folder $folder (branch: $branch)..."
        if [[ "$branch" == "default" ]]; then
            git clone "$repo_url" "$folder" || error_exit "Failed to clone $repo_url"
        else
            git clone -b "$branch" "$repo_url" "$folder" || error_exit "Failed to clone $repo_url on branch $branch"
        fi
        remote_state=$(get_latest_commit_hash "$folder")
        save_source_state "$folder" "$remote_state"
    fi

    printf '%s\n' "$source_download"
}

download_github_release_source() {
    local github_repo="$1"
    local release_tag="$2"
    local asset_name="$3"
    local asset_name_glob="$4"
    local folder="$5"
    local source_download=false
    local resolved_asset_name
    local asset_download_url
    local remote_state
    local archive_path

    mapfile -t asset_metadata < <(resolve_github_release_asset "$github_repo" "$release_tag" "$asset_name" "$asset_name_glob")
    resolved_asset_name="${asset_metadata[0]}"
    asset_download_url="${asset_metadata[1]}"
    remote_state="${resolved_asset_name}@${asset_metadata[2]}"

    if [[ "${GIT_FORCE_DOWNLOAD:-false}" == "true" ]]; then
        source_download=true
        rm -rf "$folder"
    elif [[ -d "$folder" ]]; then
        echo "Checking for changes in artifact source $folder..."
        if has_source_changed "$folder" "$remote_state"; then
            source_download=true
            echo "The artifact source $folder has changed (will be updated)."
            rm -rf "$folder"
        else
            echo "The artifact source $folder has not changed. Using cache."
        fi
    else
        source_download=true
    fi

    if [[ "$source_download" == "true" ]]; then
        archive_path="$DIR_TMP/$resolved_asset_name"
        rm -f "$archive_path"
        mkdir -p "$folder"
        echo "Downloading release asset $resolved_asset_name from $github_repo@$release_tag..."
        download_file "$asset_download_url" "$archive_path" || error_exit "Failed to download $resolved_asset_name from $asset_download_url"
        rm -rf "$folder"
        mkdir -p "$folder"
        extract_archive "$archive_path" "$folder"
        save_source_state "$folder" "$remote_state"
    fi

    printf '%s\n' "$source_download"
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
            log "Restored file $src to $dest"
        elif [[ -d "$src" ]]; then
            mkdir -p "$(dirname "$dest")"
            mv "$src" "$dest"
            log "Restored directory $src to $dest"
        else
            log "Skipping $src as it does not exist or is not a valid file/directory"
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
# Source installation
jq -c '.[]' "$REPOS_JSON" | while IFS= read -r repo_item; do
    source_type=$(echo "$repo_item" | jq -r '.source_type // "git"')
    folder=$(echo "$repo_item" | jq -r '.folder')
    branch=$(echo "$repo_item" | jq -r '.branch // "default"')

    SOURCE_DOWNLOAD=false

    case "$source_type" in
        git)
            repo_url=$(echo "$repo_item" | jq -r '.repo_url' | envsubst)
            SOURCE_DOWNLOAD=$(download_git_source "$repo_url" "$folder" "$branch")
            ;;
        github_release)
            github_repo=$(echo "$repo_item" | jq -r '.github_repo' | envsubst)
            release_tag=$(echo "$repo_item" | jq -r '.release_tag' | envsubst)
            asset_name=$(echo "$repo_item" | jq -r '.asset_name // empty' | envsubst)
            asset_name_glob=$(echo "$repo_item" | jq -r '.asset_name_glob // empty' | envsubst)

            if [[ -z "$github_repo" || "$github_repo" == "null" ]]; then
                error_exit "The field 'github_repo' is required for github_release sources."
            fi

            if [[ -z "$release_tag" || "$release_tag" == "null" ]]; then
                error_exit "The field 'release_tag' is required for github_release sources."
            fi

            if [[ -z "$asset_name" && -z "$asset_name_glob" ]]; then
                error_exit "The field 'asset_name' or 'asset_name_glob' is required for github_release sources."
            fi

            SOURCE_DOWNLOAD=$(download_github_release_source "$github_repo" "$release_tag" "$asset_name" "$asset_name_glob" "$folder")
            ;;
        *)
            error_exit "Unsupported source_type '$source_type' for folder '$folder'."
            ;;
    esac

    # Optional: execute a modification subscript for the source
    subscript_file="$DIR_SCRIPTING/git-gameserver/${folder}.${branch}.sh"
    if [[ -f "$subscript_file" ]]; then
        echo "Executing subscript $subscript_file for $folder..."
        bash "$subscript_file" "$folder" "$INSTALL_TYPE" "$SOURCE_DOWNLOAD" "$source_type"
    else
        echo "No subscript found for $folder. Skipping..."
    fi

done

log "--------------------------------------"
log "L4D2 competitive mode installation"
log "complete in mode: $INSTALL_TYPE"
log "--------------------------------------"
