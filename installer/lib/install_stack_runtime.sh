#!/bin/bash
# install_stack_runtime.sh - Helpers for install_stack orchestration.

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
            return 1
        fi
    fi
    return 0
}

get_latest_commit_hash() {
    local repo_dir="$1"
    git -C "$repo_dir" rev-parse HEAD || error_exit "Could not get the latest hash in $repo_dir."
}

sanitize_url_for_log() {
    local value="$1"

    if [[ "$value" =~ ^(https?://)([^/@:]+):([^@/]+)@(.+)$ ]]; then
        printf '%s%s:%s@%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "***" "${BASH_REMATCH[4]}"
        return 0
    fi

    printf '%s\n' "$value"
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
    local asset_download_url=""
    local asset_updated_at=""
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
    local sanitized_repo_url

    sanitized_repo_url="$(sanitize_url_for_log "$repo_url")"

    if [[ "${GIT_FORCE_DOWNLOAD:-false}" == "true" ]]; then
        source_download=true
        rm -rf "$folder"
    elif [[ -d "$folder" ]]; then
        step "Checking Git source state for $folder" >&2
        if [[ "$branch" == "default" ]]; then
            remote_state=$(git ls-remote "$repo_url" HEAD | awk '{print $1}')
        else
            remote_state=$(git ls-remote -h "$repo_url" "$branch" | awk '{print $1}')
        fi

        if has_source_changed "$folder" "$remote_state"; then
            source_download=true
            info "Repository $folder changed. Refreshing local cache." >&2
            rm -rf "$folder"
        else
            info "Repository $folder unchanged. Reusing local cache." >&2
        fi
    else
        source_download=true
    fi

    if [[ "$source_download" == "true" ]]; then
        step "Cloning $folder from $sanitized_repo_url (branch: $branch)" >&2
        if [[ "$branch" == "default" ]]; then
            git clone "$repo_url" "$folder" || error_exit "Failed to clone $sanitized_repo_url"
        else
            git clone -b "$branch" "$repo_url" "$folder" || error_exit "Failed to clone $sanitized_repo_url on branch $branch"
        fi
        remote_state=$(get_latest_commit_hash "$folder")
        save_source_state "$folder" "$remote_state"
        success "Git source ready for $folder" >&2
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
    local asset_metadata=()
    local resolved_asset_name
    local asset_download_url
    local remote_state
    local archive_path
    local sanitized_asset_download_url

    mapfile -t asset_metadata < <(resolve_github_release_asset "$github_repo" "$release_tag" "$asset_name" "$asset_name_glob")
    if [[ ${#asset_metadata[@]} -lt 3 ]]; then
        error_exit "Could not resolve release asset metadata for ${github_repo}@${release_tag}."
    fi

    resolved_asset_name="${asset_metadata[0]}"
    asset_download_url="${asset_metadata[1]}"
    sanitized_asset_download_url="$(sanitize_url_for_log "$asset_download_url")"
    remote_state="${resolved_asset_name}@${asset_metadata[2]}"

    if [[ "${GIT_FORCE_DOWNLOAD:-false}" == "true" ]]; then
        source_download=true
        rm -rf "$folder"
    elif [[ -d "$folder" ]]; then
        step "Checking artifact source state for $folder" >&2
        if has_source_changed "$folder" "$remote_state"; then
            source_download=true
            info "Artifact source $folder changed. Refreshing local cache." >&2
            rm -rf "$folder"
        else
            info "Artifact source $folder unchanged. Reusing local cache." >&2
        fi
    else
        source_download=true
    fi

    if [[ "$source_download" == "true" ]]; then
        archive_path="$DIR_TMP/$resolved_asset_name"
        rm -f "$archive_path"
        mkdir -p "$folder"
        step "Downloading release asset $resolved_asset_name from $github_repo@$release_tag" >&2
        download_file "$asset_download_url" "$archive_path" || error_exit "Failed to download $resolved_asset_name from $sanitized_asset_download_url"
        rm -rf "$folder"
        mkdir -p "$folder"
        extract_archive "$archive_path" "$folder"
        save_source_state "$folder" "$remote_state"
        success "Release artifact ready for $folder" >&2
    fi

    printf '%s\n' "$source_download"
}

clean_instance_logs() {
    local index=1
    local sourcemod_dir

    while true; do
        sourcemod_dir="${DIR_SOURCEMOD}${index}"
        if [ -d "$sourcemod_dir" ]; then
            info "Cleaning logs in $sourcemod_dir"
            if ls "$sourcemod_dir/logs/errors_"*.log &> /dev/null; then
                rm "$sourcemod_dir/logs/errors_"*.log
            fi
        else
            info "Directory $sourcemod_dir not found. Ending log cleanup."
            break
        fi
        ((index++))
    done
}

backup_files() {
    local backup_json="$1"
    local base_dir="$2"

    jq -r 'to_entries[] | "\(.key) \(.value[])"' "$backup_json" | while read -r folder file; do
        local src="$base_dir/$folder/$file"
        local dest="$base_dir/$file"
        if [[ -f "$src" ]]; then
            mkdir -p "$(dirname "$dest")"
            mv "$src" "$dest"
            info "Backed up file $src to $dest"
        elif [[ -d "$src" ]]; then
            mkdir -p "$(dirname "$dest")"
            mv "$src" "$dest"
            info "Backed up directory $src to $dest"
        else
            warn "Skipping $src because it does not exist or is not a valid file/directory"
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
            info "Restored file $src to $dest"
        elif [[ -d "$src" ]]; then
            mkdir -p "$(dirname "$dest")"
            mv "$src" "$dest"
            info "Restored directory $src to $dest"
        else
            warn "Skipping $src because it does not exist or is not a valid file/directory"
        fi
    done
}

prepare_update_cleanup() {
    section "Preparing update"
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

    restore_files "$BACKUP_JSON" "$DIR_SOURCEMOD"
}

apply_stack_sources() {
    local repo_item
    local source_type
    local folder
    local branch
    local repo_url
    local github_repo
    local release_tag
    local asset_name
    local asset_name_glob
    local source_download
    local source_download_raw
    local subscript_file

    section "Applying stack sources"
    while IFS= read -r repo_item; do
        source_type=$(echo "$repo_item" | jq -r '.source_type // "git"')
        folder=$(echo "$repo_item" | jq -r '.folder')
        branch=$(echo "$repo_item" | jq -r '.branch // "default"' | envsubst)

        section "Component: ${folder}"
        info "Source type: ${source_type}"
        info "Branch/channel: ${branch}"

        source_download=false

        case "$source_type" in
            git)
                repo_url=$(echo "$repo_item" | jq -r '.repo_url' | envsubst)
                source_download_raw=$(download_git_source "$repo_url" "$folder" "$branch")
                source_download=$(printf '%s\n' "$source_download_raw" | tail -n 1 | tr -d '\r')
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

                source_download_raw=$(download_github_release_source "$github_repo" "$release_tag" "$asset_name" "$asset_name_glob" "$folder")
                source_download=$(printf '%s\n' "$source_download_raw" | tail -n 1 | tr -d '\r')
                ;;
            hook_only)
                source_download=false
                info "Hook-only component $folder does not download external sources."
                ;;
            *)
                error_exit "Unsupported source_type '$source_type' for folder '$folder'."
                ;;
        esac

        if [[ "$source_download" != "true" && "$source_download" != "false" ]]; then
            error_exit "Invalid source download state for '$folder': '$source_download'."
        fi

        subscript_file="$DIR_STACK_HOOKS/${folder}.${branch}.sh"
        if [[ -f "$subscript_file" ]]; then
            step "Executing hook $subscript_file"
            bash "$subscript_file" "$folder" "$INSTALL_TYPE" "$source_download" "$source_type"
            success "Hook completed for $folder"
        else
            warn "No hook found for $folder. Skipping post-processing."
        fi
    done < <(jq -c '.[]' "$REPOS_JSON")
}
