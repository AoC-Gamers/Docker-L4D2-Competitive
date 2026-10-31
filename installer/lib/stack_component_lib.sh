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

source "${DIR_INSTALLER_LIB:-$(dirname "${BASH_SOURCE[0]}")}/artifact_cache.sh"

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
    subsection "Copy artifact tree: $(basename "$source_dir")"
    cp -r "$source_dir" "$target_root"
}

stack_replace_dir() {
    local source_dir="$1"
    local target_root="$2"
    local target_name=""
    local target_dir=""
    local staging_dir=""
    local backup_dir=""

    if [ ! -d "$source_dir" ]; then
        return 0
    fi

    target_name="$(basename "$source_dir")"
    target_dir="${target_root}/${target_name}"
    staging_dir="${target_dir}.staging.$$"
    backup_dir="${target_dir}.backup.$$"

    mkdir -p "$target_root"
    rm -rf "$staging_dir" "$backup_dir"

    cp -r "$source_dir" "$staging_dir"

    if [ -e "$target_dir" ] || [ -L "$target_dir" ]; then
        mv "$target_dir" "$backup_dir"
    fi

    if mv "$staging_dir" "$target_dir"; then
        rm -rf "$backup_dir"
        return 0
    fi

    rm -rf "$staging_dir"

    if [ -e "$backup_dir" ] || [ -L "$backup_dir" ]; then
        mv "$backup_dir" "$target_dir" || error_exit "Failed to restore ${target_dir} after replace failure."
    fi

    error_exit "Failed to replace directory ${target_dir}."
}

stack_sync_file() {
    local source_file="$1"
    local target_root="$2"
    local target_file
    target_file="$target_root/$(basename "$source_file")"

    if [ ! -f "$source_file" ]; then
        return 0
    fi

    mkdir -p "$target_root"
    subsection "Copy artifact file: $(basename "$source_file")"
    # Replace the directory entry as part of copying; never follow a destination
    # symlink or report normal replacement as an exclusion/missing file.
    cp -T --remove-destination -- "$source_file" "$target_file"
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

stack_replace_tree_if_present() {
    local source_root="$1"
    local relative_path="$2"
    local target_root="$3"

    stack_replace_dir "$source_root/$relative_path" "$target_root"
}

stack_install_addons_tree() {
    local source_root="$1"
    stack_install_tree_if_present "$source_root" "addons" "$DIR_LEFT4DEAD2"
}

stack_replace_addons_tree() {
    local source_root="$1"
    stack_replace_tree_if_present "$source_root" "addons" "$DIR_LEFT4DEAD2"
}

stack_install_sourcemod_tree() {
    local source_root="$1"
    mkdir -p "$DIR_LEFT4DEAD2/addons"
    stack_install_tree_if_present "$source_root" "sourcemod" "$DIR_LEFT4DEAD2/addons"
}

stack_replace_sourcemod_tree() {
    local source_root="$1"
    mkdir -p "$DIR_LEFT4DEAD2/addons"
    stack_replace_tree_if_present "$source_root" "sourcemod" "$DIR_LEFT4DEAD2/addons"
}

stack_install_cfg_tree() {
    local source_root="$1"
    stack_install_tree_if_present "$source_root" "cfg" "$DIR_LEFT4DEAD2"
}

stack_replace_cfg_tree() {
    local source_root="$1"
    stack_replace_tree_if_present "$source_root" "cfg" "$DIR_LEFT4DEAD2"
}

stack_install_scripts_tree() {
    local source_root="$1"
    stack_install_tree_if_present "$source_root" "scripts" "$DIR_LEFT4DEAD2"
}

stack_replace_scripts_tree() {
    local source_root="$1"
    stack_replace_tree_if_present "$source_root" "scripts" "$DIR_LEFT4DEAD2"
}

#######################################
# Post-deploy mutation helpers
#######################################

stack_move_plugins_to_subdir() {
    local plugins_dir="$1"
    local subdir_name="$2"
    shift
    shift

    if [ ! -d "$plugins_dir" ]; then
        return 0
    fi

    mkdir -p "$plugins_dir/$subdir_name"

    local plugin_name=""
    for plugin_name in "$@"; do
        if [ -f "$plugins_dir/$plugin_name" ]; then
            mv -f "$plugins_dir/$plugin_name" "$plugins_dir/$subdir_name/$plugin_name"
            log "Plugin $plugin_name moved to: $plugins_dir/$subdir_name"
        fi
    done
}

stack_move_plugins_to_custom() {
    local plugins_dir="$1"
    shift

    stack_move_plugins_to_subdir "$plugins_dir" "custom" "$@"
}

stack_remove_paths_if_present() {
    local target_path=""
    local status=0
    for target_path in "$@"; do
        if [[ -L "$target_path" || -f "$target_path" ]]; then
            status=0
            rm -f -- "$target_path" || status=$?
        elif [[ -d "$target_path" ]]; then
            status=0
            rm -rf -- "$target_path" || status=$?
        elif [[ -e "$target_path" ]]; then
            stack_log_exclusion "$target_path" failed >&2
            error_exit "Excluded artifact is not a file, directory or symlink: $target_path"
        else
            stack_log_exclusion "$target_path" absent
            continue
        fi
        if (( status != 0 )); then
            stack_log_exclusion "$target_path" failed >&2
            return "$status"
        fi
        stack_log_exclusion "$target_path" removed
    done
}

stack_remove_files_if_present() {
    local target_path=""
    for target_path in "$@"; do
        # A declared file exclusion must never recursively remove a directory.
        if [[ -e "$target_path" && ! -f "$target_path" && ! -L "$target_path" ]]; then
            stack_log_exclusion "$target_path" failed >&2
            error_exit "Excluded artifact is not a regular file or symlink: $target_path"
        fi
        stack_remove_paths_if_present "$target_path" || return
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

stack_normalize_accelerator_execstack() {
    local library="$1" headers hash
    [[ -f "$library" ]] || return 0
    [[ ! -L "$library" ]] || error_exit "Accelerator build copy must not be a symlink: $library"
    headers="$(LC_ALL=C readelf -W -l "$library")" || return 1
    grep -q GNU_STACK <<< "$headers" \
        || error_exit "Accelerator artifact has no GNU_STACK header; obtain a reviewed binary."
    if ! grep -Eq 'GNU_STACK.*RWE' <<< "$headers"; then return 0; fi

    hash="$(sha256sum "$library" | cut -d ' ' -f 1)"
    # Rework's legacy x86 build requests execstack. Upstream now links with
    # -z noexecstack. Only normalize this known artifact in the hook workspace.
    [[ "$hash" == e74fdebd0f0eafb721caf4f8fe96e1f5763d73e1cbb2f94a470017bffdc62b76 ]] \
        || error_exit "Unknown Accelerator artifact requests an executable stack: $hash"
    stack_require_command patchelf "Rebuild the Competitive image with its required packages."
    patchelf --clear-execstack "$library"
    headers="$(LC_ALL=C readelf -W -l "$library")" || return 1
    if grep -Eq 'GNU_STACK.*RWE' <<< "$headers"; then
        error_exit "Accelerator still requests an executable stack after normalization."
    fi
    log "Normalized legacy Accelerator GNU_STACK to non-executable in the build copy."
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
    # shellcheck disable=SC2034 # Shared hook/library contract; may be consumed by sourced helpers.
    local file_pattern="$3"

    local record="${STACK_HOOK_ASSETS_FILE:-${DIR_INSTALLER_STATE:-/data/installer/state}/hook-assets.json}"
    local filename archive sha resolved_url metadata
    local -a resolved=()
    local previous='{}'
    mkdir -p "$(dirname "$record")"
    [[ ! -f "$record" ]] || previous="$(cat "$record")"
    if [[ "${STACK_REUSE_SOURCES:-false}" == true || "${STACK_PREPARED_HOOK_ASSETS:-false}" == true ]] && jq -e --arg name "$package_name" '.[$name]' <<< "$previous" >/dev/null; then
        archive="$(jq -r --arg name "$package_name" '.[$name].cache_path' <<< "$previous")"
        sha="$(jq -r --arg name "$package_name" '.[$name].sha256' <<< "$previous")"
        [[ -f "$archive" && "$(sha256sum "$archive" | cut -d' ' -f1)" == "$sha" ]] || error_exit "Pinned hook asset unavailable: $package_name. Restore its cache or request an explicit update."
        printf '%s\n' "$archive"
        return 0
    fi
    metadata="$(stack_resolve_archive_url "$download_url")" || return 1
    mapfile -t resolved <<< "$metadata"
    filename="${resolved[0]:-}"
    resolved_url="${resolved[1]:-}"
    [[ "$filename" =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ && "$filename" != *..* && -n "$resolved_url" ]] || error_exit "Invalid asset filename for $package_name."
    archive="$(stack_acquire_original_archive "$resolved_url" "" "$filename")" || return 1
    sha="$(sha256sum "$archive" | cut -d' ' -f1)"
    jq --arg name "$package_name" --arg sha "$sha" --arg path "$archive" --arg asset "$filename" \
        '.[$name]={asset:$asset,sha256:$sha,cache_path:$path,verification:"content identity only"}' <<< "$previous" > "$record.tmp"
    mv "$record.tmp" "$record"
    printf '%s\n' "$archive"
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
        # stdout is the digest consumed by build-cache keys, not diagnostics.
        verify_and_delete_dir "$extract_root" >&2
        mkdir -p "$extract_root"
        extract_archive "$archive_path" "$extract_root"
        printf '%s\n' "$current_sha256" > "$stamp_file"
    fi

    printf '%s\n' "$current_sha256"
}

# Optional overlays share one versioned contract across inherited images.
deploy_optional_archive_tree_if_present() {
    python3 "$DIR_INSTALLER_LIB/overlay_stack.py" "$1" "$2" "$3" "$4" "$5" \
        "${OPTIONAL_OVERLAY_STATE_DIR:-${DIR_INSTALLER_STATE:-/data/installer/state}/optional-overlays}"
}

# Resolve the public hook archive once; download that exact URL rather than
# resolving a mobile latest.php channel again. Never persist signed URLs.
stack_resolve_archive_url() {
    local url="$1" headers effective filename
    mkdir -p "$DIR_TMP"
    headers="$(mktemp "$DIR_TMP/archive-headers.XXXXXX")"
    if ! effective="$(curl -fsSLI -D "$headers" -o /dev/null -w '%{url_effective}' "$url")"; then
        rm -f "$headers"
        return 1
    fi
    filename="$(sed -nE 's/.*filename="?([^";[:space:]]+).*/\1/p' "$headers" | tail -n 1 | tr -d '\r')"
    rm -f "$headers"
    [[ -n "$filename" ]] || filename="$(basename "${effective%%\?*}")"
    printf '%s\n%s\n' "$filename" "$effective"
}
