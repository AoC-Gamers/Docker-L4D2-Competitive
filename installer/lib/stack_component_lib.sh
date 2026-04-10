#!/bin/bash
# stack_component_lib.sh - Shared helpers for stack bootstrap scripts and component hooks.
#
# Usage:
#   source "$DIR_INSTALLER_LIB/tools_stack.sh"
#   source "$DIR_INSTALLER_LIB/stack_component_lib.sh"
#
# Layout:
#   1. Environment helpers: persist small runtime variables.
#   2. Deploy/sync helpers: copy trees or named files into DIR_LEFT4DEAD2.
#   3. Post-deploy helpers: move, remove or patch deployed files.
#   4. Validation helpers: check local prerequisites before continuing.
#   5. Download/archive helpers: fetch remote assets or validate local archives.
#
# When adding new helpers, keep them in the section that matches their purpose.

#######################################
# Environment helpers
#######################################

persist_env_var() {
    local key="$1"
    local value="$2"
    local env_file="${3:-/etc/environment}"
    local tmp_file="${env_file}.tmp"

    if [ -f "$env_file" ]; then
        grep -v -E "^${key}=" "$env_file" > "$tmp_file"
    else
        : > "$tmp_file"
    fi

    printf '%s=%s\n' "$key" "$value" >> "$tmp_file"
    mv "$tmp_file" "$env_file"
}

#######################################
# Deploy and sync helpers
#######################################

stack_sync_dir() {
    local source_dir="$1"
    local target_root="$2"

    if [ ! -d "$source_dir" ]; then
        return 0
    fi

    mkdir -p "$target_root"
    cp -r "$source_dir" "$target_root"
}

stack_sync_file() {
    local source_file="$1"
    local target_root="$2"
    local target_file="$target_root/$(basename "$source_file")"

    if [ ! -f "$source_file" ]; then
        return 0
    fi

    verify_and_delete_file "$target_file"
    mkdir -p "$target_root"
    cp "$source_file" "$target_file"
}

stack_install_named_files_if_present() {
    local source_root="$1"
    local target_root="$2"
    shift 2

    local relative_path=""
    for relative_path in "$@"; do
        stack_sync_file "$source_root/$relative_path" "$target_root"
    done
}

stack_install_tree_if_present() {
    local source_root="$1"
    local relative_path="$2"
    local target_root="$3"

    stack_sync_dir "$source_root/$relative_path" "$target_root"
}

stack_install_addons_tree() {
    local source_root="$1"
    stack_install_tree_if_present "$source_root" "addons" "$DIR_LEFT4DEAD2"
}

stack_install_sourcemod_tree() {
    local source_root="$1"
    mkdir -p "$DIR_LEFT4DEAD2/addons"
    stack_install_tree_if_present "$source_root" "sourcemod" "$DIR_LEFT4DEAD2/addons"
}

stack_install_cfg_tree() {
    local source_root="$1"
    stack_install_tree_if_present "$source_root" "cfg" "$DIR_LEFT4DEAD2"
}

stack_install_scripts_tree() {
    local source_root="$1"
    stack_install_tree_if_present "$source_root" "scripts" "$DIR_LEFT4DEAD2"
}

#######################################
# Post-deploy mutation helpers
#######################################

stack_move_plugins_to_custom() {
    local plugins_dir="$1"
    shift

    if [ ! -d "$plugins_dir" ]; then
        return 0
    fi

    mkdir -p "$plugins_dir/custom"

    local plugin_name=""
    for plugin_name in "$@"; do
        if [ -f "$plugins_dir/$plugin_name" ]; then
            mv -f "$plugins_dir/$plugin_name" "$plugins_dir/custom/$plugin_name"
            log "Plugin $plugin_name moved to: $plugins_dir/custom"
        fi
    done
}

stack_remove_paths_if_present() {
    local target_path=""
    for target_path in "$@"; do
        if [ -d "$target_path" ]; then
            rm -rf "$target_path"
            log "Excluded path from deployment: ${target_path#$DIR_LEFT4DEAD2/}"
            continue
        fi

        if [ -f "$target_path" ]; then
            rm -f "$target_path"
            log "Excluded path from deployment: ${target_path#$DIR_LEFT4DEAD2/}"
        fi
    done
}

stack_run_sed_on_named_files() {
    local base_dir="$1"
    local file_name="$2"
    local sed_expression="$3"

    if [ ! -d "$base_dir" ]; then
        return 0
    fi

    find "$base_dir" -type f -name "$file_name" -exec sed -ri "$sed_expression" {} \;
}

#######################################
# Validation helpers
#######################################

stack_require_command() {
    local command_name="$1"
    local install_hint="$2"

    if ! command -v "$command_name" > /dev/null 2>&1; then
        error_exit "Missing required command '${command_name}'. ${install_hint}"
    fi
}

#######################################
# Download and archive helpers
#######################################

stack_get_filename_from_url() {
    local url="$1"
    local header=""
    local filename=""
    local location=""

    header=$(curl -sI "$url")
    filename=$(echo "$header" | grep -o -E 'filename="[^"]+"' | sed -e 's/filename="//' -e 's/"//')

    if [ -z "$filename" ]; then
        location=$(echo "$header" | grep -i '^location:' | awk '{print $2}' | tr -d '\r')
        if [ -n "$location" ]; then
            filename=$(basename "$location")
        fi
    fi

    printf '%s\n' "$filename"
}

stack_download_release_tarball_if_changed() {
    local package_name="$1"
    local download_url="$2"
    local file_pattern="$3"

    local remote_filename=""
    local remote_git=""
    local local_file=""
    local local_git=""
    local target_file=""
    local timeout=60

    remote_filename=$(stack_get_filename_from_url "$download_url")
    if [ -z "$remote_filename" ]; then
        log "Error: Could not get the filename for ${package_name} from the URL."
        return 1
    fi
    log "The remote filename for ${package_name} is: ${remote_filename}"

    remote_git=$(echo "$remote_filename" | grep -oP 'git\d+' || true)

    local_file=$(ls $file_pattern 2>/dev/null | head -n 1 || true)
    if [ -z "$local_file" ]; then
        log "No local file found matching the pattern: $file_pattern"
    else
        local_git=$(echo "$local_file" | grep -oP 'git\d+' || true)
        log "Local version of ${package_name}: ${local_git:-unknown}"
    fi

    if [ -n "$local_file" ] && [ -n "$remote_git" ] && [ "$local_git" = "$remote_git" ]; then
        log "${package_name} is already up to date (version ${local_git})."
        printf '%s\n' "$local_file"
        return 0
    fi

    log "${package_name} is outdated or has no local copy. Downloading version ${remote_git:-unknown}."
    wget --directory-prefix="$DIR_TMP" --content-disposition -q "$download_url"

    target_file="$DIR_TMP/$remote_filename"
    while [ ! -s "$target_file" ] && [ $timeout -gt 0 ]; do
        sleep 1
        timeout=$((timeout-1))
    done

    if [ ! -s "$target_file" ]; then
        log "Error: The download of ${package_name} did not complete in the expected time."
        return 1
    fi

    if [ -n "$local_file" ] && [ -n "$remote_git" ] && [ "$local_git" != "$remote_git" ]; then
        verify_and_delete_dir "$local_file"
        log "The old version of ${package_name} ($local_file) was deleted."
    fi

    log "${package_name} updated to version ${remote_git:-unknown}."
    printf '%s\n' "$target_file"
}

stack_require_local_archive() {
    local archive_name="$1"
    local resources_dir="${2:-${REPO_RESOURCES_DIR:-/data/resources}}"
    local archive_path="${resources_dir}/${archive_name}"

    mkdir -p "$resources_dir"

    if [ ! -f "$archive_path" ]; then
        error_exit "Missing required archive at ${archive_path}."
    fi

    printf '%s\n' "$archive_path"
}

stack_extract_cached_archive_by_sha() {
    local archive_path="$1"
    local extract_root="$2"
    local stamp_file="${extract_root}/archive.sha256"
    local current_sha256=""
    local cached_sha256=""

    current_sha256="$(sha256sum "$archive_path" | awk '{print $1}')"
    if [ -f "$stamp_file" ]; then
        cached_sha256="$(tr -d '\r\n' < "$stamp_file")"
    fi

    if [ "$cached_sha256" != "$current_sha256" ]; then
        verify_and_delete_dir "$extract_root"
        mkdir -p "$extract_root"
        extract_archive "$archive_path" "$extract_root"
        printf '%s\n' "$current_sha256" > "$stamp_file"
    fi

    printf '%s\n' "$current_sha256"
}
