#!/bin/bash
# install_stack_runtime.sh - Helpers for install_stack orchestration.
source "${DIR_INSTALLER_LIB:-$(dirname "${BASH_SOURCE[0]}")}/artifact_cache.sh"

build_resolved_components_json() {
    local components_file="$1"
    local profile_file="$2"
    local resolved_rows
    local component_id
    local component_json
    local folder
    local branch_var_name
    local branch_value
    local release_tag_var_name
    local release_tag_value
    local first=true

    resolved_rows="$(
        jq -r \
            --slurpfile profile "$profile_file" \
            '
              . as $catalog |
              ($profile[0].components // []) as $selected |
              ($profile[0].overrides // {}) as $overrides |
              $selected[] as $id |
              ($catalog[$id] // error("Unknown component in profile: " + $id)) as $component |
              ($overrides[$id] // {}) as $override |
              ($component + $override + {id: $id}) as $resolved |
              [$id, $resolved.folder, ($resolved | @json)] | @tsv
            ' "$components_file"
    )" || return 1

    [[ "$(cut -f2 <<< "$resolved_rows" | sort | uniq -d)" == "" ]] || error_exit "Duplicate component folder in profile."
    printf '['
    while IFS=$'\t' read -r component_id folder component_json; do
        [[ -n "$component_id" ]] || continue

        [[ "$folder" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]*$ && "$folder" != *..* ]] || error_exit "Invalid component folder."
        branch_var_name="BRANCH_$(echo "$folder" | tr '[:lower:]' '[:upper:]')"
        branch_value=${!branch_var_name:-default}
        release_tag_var_name="RELEASE_TAG_$(echo "$folder" | tr '[:lower:]' '[:upper:]')"
        release_tag_value=${!release_tag_var_name:-default}

        if [ "$branch_value" != "default" ]; then
            component_json="$(printf '%s\n' "$component_json" | jq -c --arg val "$branch_value" '.branch = $val')"
        fi

        if [ "$release_tag_value" != "default" ]; then
            component_json="$(printf '%s\n' "$component_json" | jq -c --arg val "$release_tag_value" '.release_tag = $val')"
        fi

        component_json="$(printf '%s\n' "$component_json" | envsubst | jq -c '.')"
        local variant_var variant_override
        variant_var="HOOK_VARIANT_$(echo "$folder" | tr '[:lower:]' '[:upper:]')"
        variant_override="${!variant_var:-}"
        if [[ -n "$variant_override" ]]; then
            component_json="$(jq -c --arg value "$variant_override" '.hook_variant=$value' <<< "$component_json")"
        fi
        if [ "$first" = true ]; then
            first=false
        else
            printf ','
        fi

        printf '%s' "$component_json"
    done <<< "$resolved_rows"
    printf ']\n'
}

prepare_component_workspace() {
    local component_name="$1"
    local cache_dir="$2"
    local workspace_dir="${DIR_TMP}/${component_name}"

    rm -rf "$workspace_dir"

    if [ ! -d "$cache_dir" ]; then
        error_exit "Expected cached source directory for '${component_name}' at ${cache_dir}."
    fi

    mkdir -p "$workspace_dir"
    if [[ -f "$cache_dir/.stack-source.json" && "$(jq -r '.format // "legacy-tree"' "$cache_dir/.stack-source.json")" == original-archive ]]; then
        stack_expand_original_archive "$(jq -r .archive_cache "$cache_dir/.stack-source.json")" "$(jq -r .sha256 "$cache_dir/.stack-source.json")" "$workspace_dir" >&2 || error_exit "Failed to expand source: $component_name"
    else
        cp -a "${cache_dir}/." "$workspace_dir/"
    fi
    printf '%s\n' "$workspace_dir"
}

save_component_state() {
    local component_name="$1"
    local component_state="$2"

    mkdir -p "$(dirname "$CACHE_FILE")"

    if command -v flock > /dev/null 2>&1; then
        exec 9>>"$CACHE_LOCK_FILE"
        flock 9
    fi

    if [[ -f "$CACHE_FILE" ]]; then
        awk -F: -v name="$component_name" '$1 != name' "$CACHE_FILE" > "${CACHE_FILE}.tmp"
        mv "${CACHE_FILE}.tmp" "$CACHE_FILE"
    fi

    echo "$component_name:$component_state" >> "$CACHE_FILE"

    if command -v flock > /dev/null 2>&1; then
        flock -u 9
        exec 9>&-
    fi
}

has_component_changed() {
    local component_name="$1"
    local new_state="$2"

    if [[ "$(get_component_cached_state "$component_name")" == "$new_state" ]]; then
        return 1
    fi

    return 0
}

get_component_cached_state() {
    local component_name="$1"
    local old_state=""

    if command -v flock > /dev/null 2>&1; then
        exec 9>>"$CACHE_LOCK_FILE"
        flock 9
    fi

    if [[ -f "$CACHE_FILE" ]]; then
        old_state=$(awk -v name="$component_name" 'index($0, name ":") == 1 {value=substr($0,length(name)+2)} END {print value}' "$CACHE_FILE")
    fi

    if command -v flock > /dev/null 2>&1; then
        flock -u 9
        exec 9>&-
    fi

    printf '%s\n' "$old_state"
}

component_cache_matches_source_prefix() {
    local component_name="$1"
    local expected_prefix="$2"
    local cached_state=""

    cached_state="$(get_component_cached_state "$component_name")"
    [[ -n "$cached_state" && "$cached_state" == "${expected_prefix}"* ]]
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
    local asset_api_url=""
    local asset_updated_at=""
    local candidate_name
    local candidate_url
    local candidate_updated_at

    encoded_tag=$(jq -rn --arg value "$release_tag" '$value|@uri')
    api_url="https://api.github.com/repos/${github_repo}/releases/tags/${encoded_tag}"
    release_json=$(github_api_request "$api_url") || {
        warn "Could not fetch release metadata for ${github_repo}@${release_tag}." >&2
        return 1
    }

    if [[ -n "$asset_name" && "$asset_name" != "null" ]]; then
        matched_asset_name="$asset_name"
        asset_download_url=$(echo "$release_json" | jq -r --arg asset_name "$asset_name" '.assets[] | select(.name == $asset_name) | .browser_download_url' | head -n 1)
        asset_api_url=$(echo "$release_json" | jq -r --arg asset_name "$asset_name" '.assets[] | select(.name == $asset_name) | .url' | head -n 1)
        asset_updated_at=$(echo "$release_json" | jq -r --arg asset_name "$asset_name" '.assets[] | select(.name == $asset_name) | .updated_at' | head -n 1)
    else
        while IFS=$'\t' read -r candidate_name candidate_url candidate_api_url candidate_updated_at; do
            [[ -n "$candidate_name" ]] || continue

            if [[ "$candidate_name" == $asset_name_glob ]]; then
                if [[ -z "$asset_updated_at" || "$candidate_updated_at" > "$asset_updated_at" ]]; then
                    matched_asset_name="$candidate_name"
                    asset_download_url="$candidate_url"
                    asset_api_url="$candidate_api_url"
                    asset_updated_at="$candidate_updated_at"
                fi
            fi
        done < <(echo "$release_json" | jq -r '.assets[] | [.name, .browser_download_url, .url, .updated_at] | @tsv')
    fi

    if [[ -z "$asset_download_url" || "$asset_download_url" == "null" ]]; then
        if [[ -n "$asset_name_glob" && "$asset_name_glob" != "null" ]]; then
            warn "No asset matching '${asset_name_glob}' was found in ${github_repo}@${release_tag}." >&2
            return 1
        fi

        warn "Asset '${asset_name}' not found in ${github_repo}@${release_tag}." >&2
        return 1
    fi

    if [[ -z "$asset_updated_at" || "$asset_updated_at" == "null" ]]; then
        warn "Could not determine update state for asset '${matched_asset_name}' in ${github_repo}@${release_tag}." >&2
        return 1
    fi

    if [[ -z "$asset_api_url" || "$asset_api_url" == "null" ]]; then
        warn "Could not determine API URL for asset '${matched_asset_name}' in ${github_repo}@${release_tag}." >&2
        return 1
    fi

    printf '%s\n%s\n%s\n%s\n' "$matched_asset_name" "$asset_download_url" "$asset_api_url" "$asset_updated_at"
    printf '%s\n' "$(printf '%s' "$release_json" | jq -r --arg name "$matched_asset_name" '.assets[] | select(.name==$name) | .id, (.digest // "")')"
}

preflight_github_release_access() {
    local github_repo="$1"
    local release_tag="$2"
    local asset_name="$3"
    local asset_name_glob="$4"
    local encoded_tag
    local api_url
    local body_file
    local http_status
    local release_json
    local matched_asset_name=""
    local asset_download_url=""
    local asset_updated_at=""
    local asset_api_url=""
    local candidate_name
    local candidate_url
    local candidate_updated_at
    local body_message=""

    encoded_tag=$(jq -rn --arg value "$release_tag" '$value|@uri')
    api_url="https://api.github.com/repos/${github_repo}/releases/tags/${encoded_tag}"
    body_file="$DIR_TMP/github-release-preflight-$$.json"
    rm -f "$body_file"

    http_status="$(github_http_status "$api_url" "$body_file")" || http_status="000"

    if [[ -f "$body_file" ]]; then
        body_message="$(jq -r '.message // empty' "$body_file" 2> /dev/null || true)"
        release_json="$(cat "$body_file")"
    else
        release_json=""
    fi

    case "$http_status" in
        200)
            ;;
        401)
            error_exit "GitHub authentication failed for ${github_repo}@${release_tag}. Check the configured token."
            ;;
        403)
            if [[ "$body_message" == *"rate limit"* ]]; then
                error_exit "GitHub API rate limit exceeded for ${github_repo}@${release_tag}. Configure GITHUB_TOKEN in .env.secrets (or the component's github_token_env) and retry after the limit resets."
            fi
            error_exit "GitHub access forbidden for ${github_repo}@${release_tag}. The configured token lacks permission or hit a policy/rate limit${body_message:+: ${body_message}}."
            ;;
        429)
            error_exit "GitHub API rate limit exceeded for ${github_repo}@${release_tag}. Configure GITHUB_TOKEN in .env.secrets (or the component's github_token_env) and retry after the limit resets."
            ;;
        404)
            error_exit "GitHub release ${github_repo}@${release_tag} is not accessible. Verify the tag exists and that the configured token can read the repository."
            ;;
        *)
            error_exit "GitHub preflight failed for ${github_repo}@${release_tag} with HTTP ${http_status}${body_message:+: ${body_message}}."
            ;;
    esac

    if [[ -n "$asset_name" && "$asset_name" != "null" ]]; then
        matched_asset_name="$asset_name"
        asset_download_url=$(echo "$release_json" | jq -r --arg value "$asset_name" '.assets[] | select(.name == $value) | .browser_download_url' | head -n 1)
        asset_api_url=$(echo "$release_json" | jq -r --arg value "$asset_name" '.assets[] | select(.name == $value) | .url' | head -n 1)
        asset_updated_at=$(echo "$release_json" | jq -r --arg value "$asset_name" '.assets[] | select(.name == $value) | .updated_at' | head -n 1)
    else
        while IFS=$'\t' read -r candidate_name candidate_url candidate_api_url candidate_updated_at; do
            [[ -n "$candidate_name" ]] || continue
            if [[ "$candidate_name" == $asset_name_glob ]]; then
                if [[ -z "$asset_updated_at" || "$candidate_updated_at" > "$asset_updated_at" ]]; then
                    matched_asset_name="$candidate_name"
                    asset_download_url="$candidate_url"
                    asset_api_url="$candidate_api_url"
                    asset_updated_at="$candidate_updated_at"
                fi
            fi
        done < <(echo "$release_json" | jq -r '.assets[] | [.name, .browser_download_url, .url, .updated_at] | @tsv')
    fi

    if [[ -z "$asset_download_url" || "$asset_download_url" == "null" ]]; then
        if [[ -n "$asset_name_glob" && "$asset_name_glob" != "null" ]]; then
            error_exit "GitHub preflight could read ${github_repo}@${release_tag}, but no asset matching '${asset_name_glob}' was found."
        fi
        error_exit "GitHub preflight could read ${github_repo}@${release_tag}, but asset '${asset_name}' was not found."
    fi

    if [[ -z "$asset_api_url" || "$asset_api_url" == "null" ]]; then
        error_exit "GitHub preflight could read ${github_repo}@${release_tag}, but the asset API URL for '${matched_asset_name}' is missing."
    fi

    success "GitHub release access verified for ${github_repo}@${release_tag} (${matched_asset_name})" >&2
}

resolve_component_github_token() {
    local github_token_env="$1"
    local github_auth_token=""

    if [[ -z "$github_token_env" || "$github_token_env" == "null" ]]; then
        return 0
    fi

    if [[ ! "$github_token_env" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
        error_exit "Invalid github_token_env '${github_token_env}'."
    fi

    github_auth_token="${!github_token_env:-}"
    if [[ -z "$github_auth_token" ]]; then
        error_exit "The environment variable '${github_token_env}' is required for this github_release source but is empty or undefined."
    fi

    printf '%s\n' "$github_auth_token"
}

download_git_source() {
    local repo_url="$1"
    local folder="$2"
    local branch="$3"
    local source_download=false
    local remote_state
    local remote_state_raw=""
    local sanitized_repo_url
    local source_prefix=""

    if [[ "${STACK_REUSE_SOURCES:-false}" == true && -d "$folder/.git" ]] && component_cache_matches_source_prefix "$folder" "git:${repo_url}@${branch}:"; then
        printf 'false\n'; return 0
    fi
    sanitized_repo_url="$(sanitize_url_for_log "$repo_url")"
    source_prefix="git:${repo_url}@${branch}:"

    if [[ "${GIT_FORCE_DOWNLOAD:-false}" == "true" ]]; then
        source_download=true
    elif [[ -d "$folder" ]]; then
        step "Checking Git source state for $folder" >&2
        if [[ "$branch" == "default" ]]; then
            remote_state_raw="$(git ls-remote "$repo_url" HEAD 2>/dev/null | awk '{print $1}' | head -n 1 || true)"
        else
            remote_state_raw="$(git ls-remote -h "$repo_url" "$branch" 2>/dev/null | awk '{print $1}' | head -n 1 || true)"
        fi

        if [[ -z "$remote_state_raw" ]]; then
            if component_cache_matches_source_prefix "$folder" "$source_prefix" && stack_git_original_clean "$folder"; then
                warn "Could not resolve remote Git state for $folder. Reusing compatible local cache."
                printf '%s\n' "false"
                return 0
            fi

            error_exit "Could not resolve remote Git state for $folder and no compatible local cache is available."
        fi

        remote_state="${source_prefix}${remote_state_raw}"

        if has_component_changed "$folder" "$remote_state" || ! stack_git_original_clean "$folder"; then
            source_download=true
            info "Repository $folder changed. Refreshing local cache." >&2
        else
            info "Repository $folder unchanged. Reusing local cache." >&2
        fi
    else
        source_download=true
    fi

    if [[ "$source_download" == "true" ]]; then
        step "Cloning $folder from $sanitized_repo_url (branch: $branch)" >&2
        rm -rf "$folder.new"
        if [[ "$branch" == "default" ]]; then
            git clone "$repo_url" "$folder.new" || error_exit "Failed to clone $sanitized_repo_url"
        else
            git clone -b "$branch" "$repo_url" "$folder.new" || error_exit "Failed to clone $sanitized_repo_url on branch $branch"
        fi
        rm -rf "$folder"
        mv "$folder.new" "$folder"
        remote_state="git:${repo_url}@${branch}:$(get_latest_commit_hash "$folder")"
        save_component_state "$folder" "$remote_state"
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
    local github_auth_token="${6:-}"
    local source_download=false
    local asset_metadata=()
    local asset_metadata_raw=""
    local resolved_asset_name
    local asset_download_url
    local remote_state
    local archive_path
    local sanitized_asset_download_url
    local source_prefix=""

    source_prefix="github_release:${github_repo}@${release_tag}:"
    if [[ "${STACK_REUSE_SOURCES:-false}" == true && -d "$folder" && ! -f "$folder/.stack-source.json" ]] && component_cache_matches_source_prefix "$folder" "$source_prefix"; then
        error_exit "Legacy release cache has no verifiable content identity: $folder. Establish a source lock with an explicit update or restore verified pinned sources."
    fi
    if [[ "${STACK_REUSE_SOURCES:-false}" == true && -d "$folder" && -f "$folder/.stack-source.json" ]] && component_cache_matches_source_prefix "$folder" "$source_prefix"; then
        if [[ -n "${STACK_EXPECTED_SHA256:-}" && "$(jq -r .sha256 "$folder/.stack-source.json")" != "$STACK_EXPECTED_SHA256" ]]; then
            error_exit "Cached asset checksum does not match the expected checksum."
        fi
        [[ "$(jq -r .tree_sha256 "$folder/.stack-source.json")" == "$(python3 "$DIR_INSTALLER_LIB/source_identity.py" "$folder" --payload)" ]] || error_exit "Cached release tree is corrupt: $folder"
        if [[ "$(jq -r '.format // "legacy-tree"' "$folder/.stack-source.json")" == original-archive ]]; then
            local original
            original="$(jq -r .archive_cache "$folder/.stack-source.json")"
            [[ -f "$original" && "$(sha256sum "$original" | cut -d' ' -f1)" == "$(jq -r .sha256 "$folder/.stack-source.json")" ]] || error_exit "Original archive missing/corrupt: $folder"
        fi
        printf 'false\n'; return 0
    fi

    if [[ -n "$github_auth_token" ]]; then
        asset_metadata_raw="$(GITHUB_AUTH_TOKEN="$github_auth_token" resolve_github_release_asset "$github_repo" "$release_tag" "$asset_name" "$asset_name_glob" || true)"
    else
        asset_metadata_raw="$(resolve_github_release_asset "$github_repo" "$release_tag" "$asset_name" "$asset_name_glob" || true)"
    fi

    if [[ -n "$asset_metadata_raw" ]]; then
        mapfile -t asset_metadata <<< "$asset_metadata_raw"
    fi

    if [[ ${#asset_metadata[@]} -lt 4 ]]; then
        warn "Could not resolve release asset metadata for ${github_repo}@${release_tag}. Running GitHub preflight for diagnostics." >&2
        if [[ -n "$github_auth_token" ]]; then
            GITHUB_AUTH_TOKEN="$github_auth_token" preflight_github_release_access "$github_repo" "$release_tag" "$asset_name" "$asset_name_glob"
        else
            preflight_github_release_access "$github_repo" "$release_tag" "$asset_name" "$asset_name_glob"
        fi

        if [[ -d "$folder" ]] && component_cache_matches_source_prefix "$folder" "$source_prefix"; then
            warn "Could not resolve release asset metadata for ${github_repo}@${release_tag}. Reusing compatible local cache."
            printf '%s\n' "false"
            return 0
        fi

        error_exit "Could not resolve release asset metadata for ${github_repo}@${release_tag} and no compatible local cache is available."
    fi

    resolved_asset_name="${asset_metadata[0]}"
    asset_download_url="${asset_metadata[1]}"
    asset_api_url="${asset_metadata[2]}"
    sanitized_asset_download_url="$(sanitize_url_for_log "$asset_download_url")"
    remote_state="github_release:${github_repo}@${release_tag}:${resolved_asset_name}@${asset_metadata[3]}:${asset_metadata[4]:-}:${asset_metadata[5]:-}"

    if [[ "${GIT_FORCE_DOWNLOAD:-false}" == "true" ]]; then
        source_download=true
    elif [[ -d "$folder" ]]; then
        step "Checking artifact source state for $folder" >&2
        local cached_expected="${STACK_EXPECTED_SHA256:-${asset_metadata[5]:-}}"
        cached_expected="${cached_expected#sha256:}"
        if [[ -z "$cached_expected" || ! -f "$folder/.stack-source.json" ]] || \
            ! stack_original_source_valid "$folder" || \
            [[ -n "$cached_expected" && "$(jq -r .sha256 "$folder/.stack-source.json")" != "$cached_expected" ]] || \
            [[ "$(jq -r .tree_sha256 "$folder/.stack-source.json")" != "$(python3 "$DIR_INSTALLER_LIB/source_identity.py" "$folder" --payload)" ]] || has_component_changed "$folder" "$remote_state"; then
            source_download=true
            info "Artifact source $folder changed. Refreshing local cache." >&2
        else
            info "Artifact source $folder unchanged. Reusing local cache." >&2
        fi
    else
        source_download=true
    fi

    if [[ "$source_download" == "true" ]]; then
        local content_sha expected_sha
        expected_sha="${STACK_EXPECTED_SHA256:-${asset_metadata[5]:-}}"
        expected_sha="${expected_sha#sha256:}"
        success "GitHub release access verified for ${github_repo}@${release_tag} (${resolved_asset_name})" >&2
        if [[ -n "$github_auth_token" ]]; then
            archive_path="$(GITHUB_AUTH_TOKEN="$github_auth_token" stack_acquire_original_archive "$asset_api_url" "$expected_sha" "$resolved_asset_name")" || error_exit "Failed to acquire original archive: $resolved_asset_name"
        else
            archive_path="$(stack_acquire_original_archive "$asset_api_url" "$expected_sha" "$resolved_asset_name")" || error_exit "Failed to acquire original archive: $resolved_asset_name"
        fi
        content_sha="$(sha256sum "$archive_path" | cut -d' ' -f1)"
        rm -rf "$folder.new"
        mkdir -p "$folder.new"
        if [[ "${STACK_FETCH_ONLY:-false}" != true ]]; then
            # Backward-compatible direct library call. The installer expands in phase 2.
            extract_archive "$archive_path" "$folder.new" || error_exit "Failed to extract original archive."
        fi
        local extracted_tree_sha format=original-archive
        [[ "${STACK_FETCH_ONLY:-false}" == true ]] || format=legacy-tree
        extracted_tree_sha="$(python3 "${DIR_INSTALLER_LIB:-$(dirname "${BASH_SOURCE[0]}")}/source_identity.py" "$folder.new" --payload)"
        jq -n --arg format "$format" --arg archive "$archive_path" --arg tree_sha "$extracted_tree_sha" --arg repo "$github_repo" --arg tag "$release_tag" --arg name "$resolved_asset_name" \
            --arg id "${asset_metadata[4]:-}" --arg sha256 "$content_sha" --arg expected "$expected_sha" \
            '{format:$format,archive_cache:$archive,tree_sha256:$tree_sha,source_type:"github_release",repo:$repo,reference:$tag,asset:$name,asset_id:$id,sha256:$sha256,expected_sha256:$expected}' > "$folder.new/.stack-source.json"
        rm -rf "$folder"
        mv "$folder.new" "$folder"
        save_component_state "$folder" "$remote_state"
        success "Release artifact ready for $folder" >&2
    fi

    printf '%s\n' "$source_download"
}

apply_stack_sources() {
    local component_json
    local source_type
    local folder
    local branch
    local repo_url
    local github_repo
    local release_tag
    local asset_name
    local asset_name_glob
    local github_token_env
    local github_auth_token
    local source_download
    local source_download_raw
    local subscript_file
    local component_cache_dir
    local component_work_dir

    section "Applying stack sources"
    while IFS= read -r component_json; do
        [[ -n "$component_json" ]] || continue

        source_type="$(printf '%s\n' "$component_json" | jq -r '.source_type // "git"')"
        folder="$(printf '%s\n' "$component_json" | jq -r '.folder')"
        branch="$(printf '%s\n' "$component_json" | jq -r '.branch // "default"')"
        repo_url="$(printf '%s\n' "$component_json" | jq -r '.repo_url // ""')"
        github_repo="$(printf '%s\n' "$component_json" | jq -r '.github_repo // ""')"
        release_tag="$(printf '%s\n' "$component_json" | jq -r '.release_tag // ""')"
        asset_name="$(printf '%s\n' "$component_json" | jq -r '.asset_name // ""')"
        asset_name_glob="$(printf '%s\n' "$component_json" | jq -r '.asset_name_glob // ""')"
        github_token_env="$(printf '%s\n' "$component_json" | jq -r '.github_token_env // ""')"

        branch="$(printf '%s\n' "$branch" | envsubst)"

        section "Component: ${folder}"
        info "Source type: ${source_type}"
        if [[ "$source_type" == "github_release" ]]; then
            info "Release tag: ${release_tag}"
        else
            info "Branch/channel: ${branch}"
        fi

        local source_key pinned_row pinned_key pinned_dir pinned_sha
        source_key="$(jq -cS 'if .source_type=="archive" then {source_type,folder,url,archive_name,sha256} else {source_type,folder,repo_url,github_repo,branch,release_tag,asset_name,asset_name_glob,sha256} end' <<< "$component_json" | sha256sum | cut -d' ' -f1)"
        pinned_row=""
        if [[ "${STACK_FETCH_ONLY:-false}" == true && "${STACK_REUSE_SOURCES:-false}" == true && -f "$STATE_ROOT/source-lock.json" ]]; then
            pinned_row="$(jq -c --arg folder "$folder" --arg key "$source_key" '.[] | select(.folder==$folder and .source_key==$key)' "$STATE_ROOT/source-lock.json")"
        fi
        source_download=false
        component_cache_dir=""
        component_work_dir=""

        if [[ -n "$pinned_row" && "$source_type" != hook_only ]]; then
            pinned_key="$(jq -r .snapshot_key <<< "$pinned_row")"
            pinned_dir="$STATE_ROOT/pinned-sources/$pinned_key"
            pinned_sha="$(jq -r .snapshot_sha256 <<< "$pinned_row")"
            [[ -d "$pinned_dir" && "$(python3 "$DIR_INSTALLER_LIB/source_identity.py" "$pinned_dir")" == "$pinned_sha" ]] || error_exit "Pinned source unavailable/corrupt: $folder. Restore cache or request an explicit update."
            component_cache_dir="$pinned_dir"
        elif [[ -n "${STACK_PREPARED_SOURCES_FILE:-}" ]]; then
            source_download=false
            component_cache_dir="$(jq -r --arg folder "$folder" '.[] | select(.folder==$folder) | .cache_dir' "$STACK_PREPARED_SOURCES_FILE")"
            [[ "$source_type" == hook_only || -d "$component_cache_dir" ]] || error_exit "Prepared source unavailable: $folder"
        else
        case "$source_type" in
            git)
                repo_url="$(printf '%s\n' "$repo_url" | envsubst)"
                source_download_raw=$(download_git_source "$repo_url" "$folder" "$branch")
                source_download=$(printf '%s\n' "$source_download_raw" | tail -n 1 | tr -d '\r')
                component_cache_dir="${PWD}/${folder}"
                ;;
            github_release)
                github_repo="$(printf '%s\n' "$github_repo" | envsubst)"
                release_tag="$(printf '%s\n' "$release_tag" | envsubst)"
                asset_name="$(printf '%s\n' "$asset_name" | envsubst)"
                asset_name_glob="$(printf '%s\n' "$asset_name_glob" | envsubst)"
                github_token_env="$(printf '%s\n' "$github_token_env" | envsubst)"
                github_auth_token="$(resolve_component_github_token "$github_token_env")"

                if [[ -z "$github_repo" || "$github_repo" == "null" ]]; then
                    error_exit "The field 'github_repo' is required for github_release sources."
                fi

                if [[ -z "$release_tag" || "$release_tag" == "null" ]]; then
                    error_exit "The field 'release_tag' is required for github_release sources."
                fi

                if [[ -z "$asset_name" && -z "$asset_name_glob" ]]; then
                    error_exit "The field 'asset_name' or 'asset_name_glob' is required for github_release sources."
                fi

                source_download_raw=$(STACK_EXPECTED_SHA256="$(jq -r '.sha256 // empty' <<< "$component_json")" download_github_release_source "$github_repo" "$release_tag" "$asset_name" "$asset_name_glob" "$folder" "$github_auth_token")
                source_download=$(printf '%s\n' "$source_download_raw" | tail -n 1 | tr -d '\r')
                component_cache_dir="${PWD}/${folder}"
                ;;
            archive)
                component_cache_dir="${PWD}/${folder}"
                source_download_raw="$(download_archive_source "$component_json" "$component_cache_dir")" || error_exit "Failed to acquire archive: $folder"
                source_download="$source_download_raw"
                ;;
            hook_only)
                source_download=false
                if [[ "${STACK_FETCH_ONLY:-false}" == true ]]; then
                    local asset name url
                    while IFS= read -r asset; do
                        name="$(jq -r .name <<< "$asset")"
                        url="$(jq -r .url <<< "$asset")"
                        stack_download_release_tarball_if_changed "$name" "$url" "" > /dev/null || error_exit "Declared hook asset acquisition failed: $name"
                    done < <(jq -c '.prepare_downloads // [] | .[]' <<< "$component_json")
                fi
                ;;
            *)
                error_exit "Unsupported source_type '$source_type' for folder '$folder'."
                ;;
        esac

        fi
        if [[ "${STACK_FETCH_ONLY:-false}" == true ]]; then
            local identity='{}'
            local snapshot_key='' snapshot_sha256=''
            if [[ "$source_type" == git ]]; then
                identity="$(jq -n --arg commit "$(git -C "$component_cache_dir" rev-parse HEAD)" '{source_type:"git",commit:$commit}')"
            elif [[ "$source_type" == github_release || "$source_type" == archive ]]; then
                identity="$(cat "$component_cache_dir/.stack-source.json")"
            elif [[ "$source_type" == hook_only && -f "${STACK_HOOK_ASSETS_FILE:-/nonexistent}" ]]; then
                identity="$(jq --argjson names "$(jq '[.prepare_downloads // [] | .[] | .name]' <<< "$component_json")" 'with_entries(select(.key as $k | $names | index($k)))' "$STACK_HOOK_ASSETS_FILE")"
            fi
            if [[ -f "$component_cache_dir/.stack-source.json" && "$(jq -r '.format // "legacy-tree"' "$component_cache_dir/.stack-source.json")" == original-archive ]]; then
                local original_archive original_sha
                original_archive="$(jq -r .archive_cache "$component_cache_dir/.stack-source.json")"
                original_sha="$(jq -r .sha256 "$component_cache_dir/.stack-source.json")"
                [[ -f "$original_archive" && "$(sha256sum "$original_archive" | cut -d' ' -f1)" == "$original_sha" ]] || error_exit "Original archive missing/corrupt: $folder"
            fi
            if [[ -n "$component_cache_dir" ]]; then
                snapshot_sha256="$(python3 "$DIR_INSTALLER_LIB/source_identity.py" "$component_cache_dir")"
                snapshot_key="$(printf '%s:%s' "$source_key" "$snapshot_sha256" | sha256sum | cut -d' ' -f1)"
                mkdir -p "$STATE_ROOT/pinned-sources"
                exec 4>"$STATE_ROOT/pinned-sources/$snapshot_key.lock"; flock 4
                if [[ ! -d "$STATE_ROOT/pinned-sources/$snapshot_key" ]]; then
                    rm -rf "$STATE_ROOT/pinned-sources/$snapshot_key.new"
                    mkdir -p "$STATE_ROOT/pinned-sources/$snapshot_key.new"
                    cp -a "$component_cache_dir/." "$STATE_ROOT/pinned-sources/$snapshot_key.new/"
                    mv "$STATE_ROOT/pinned-sources/$snapshot_key.new" "$STATE_ROOT/pinned-sources/$snapshot_key"
                fi
                flock -u 4; exec 4>&-
                component_cache_dir="$STATE_ROOT/pinned-sources/$snapshot_key"
            fi
            jq -n --arg source_key "$source_key" --arg snapshot_key "$snapshot_key" --arg snapshot_sha256 "$snapshot_sha256" \
                --arg folder "$folder" --arg cache_dir "$component_cache_dir" --argjson identity "$identity" \
                '{folder:$folder,source_key:$source_key,cache_dir:$cache_dir,snapshot_key:$snapshot_key,snapshot_sha256:$snapshot_sha256,identity:$identity}' >> "$STACK_SOURCES_ROWS"
            continue
        fi

        if [[ "$source_download" != "true" && "$source_download" != "false" ]]; then
            error_exit "Invalid source download state for '$folder': '$source_download'."
        fi

        local hook_variant hook_required
        hook_variant="$(printf '%s\n' "$component_json" | jq -r '.hook_variant // .branch // "default"')"
        hook_required="$(printf '%s\n' "$component_json" | jq -r 'if has("hook_required") then .hook_required else true end')"
        subscript_file="$DIR_STACK_HOOKS/${folder}.${hook_variant}.sh"
        if [[ -f "$subscript_file" ]]; then
            stack_prepare_component_hook "$component_json" "$component_cache_dir" "$subscript_file" "$source_download" "$source_type"
            success "Component ready for $folder"
        else
            [[ "$hook_required" == false ]] || error_exit "Required hook missing: $folder.$hook_variant"
            info "Optional hook absent for $folder."
        fi
    done < <(
        printf '%s\n' "$RESOLVED_COMPONENTS_JSON" | jq -c '.[]'
    )
}

validate_stack_hooks() {
    python3 "$DIR_INSTALLER_LIB/validate_stack.py" "$DIR_STACK_HOOKS" <<< "$RESOLVED_COMPONENTS_JSON"
    local component folder variant required
    while IFS= read -r component; do
        folder="$(jq -r .folder <<< "$component")"
        variant="$(jq -r '.hook_variant // .branch // "default"' <<< "$component")"
        required="$(jq -r 'if has("hook_required") then .hook_required else true end' <<< "$component")"
        [[ "$folder" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]*$ && "$variant" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]*$ && "$folder" != *..* && "$variant" != *..* ]] || error_exit "Invalid component/hook name."
        if [[ -f "$DIR_STACK_HOOKS/$folder.$variant.sh" ]]; then
            bash -n "$DIR_STACK_HOOKS/$folder.$variant.sh"
        elif [[ "$required" != false ]]; then
            error_exit "Required hook missing: $folder.$variant"
        fi
    done < <(jq -c '.[]' <<< "$RESOLVED_COMPONENTS_JSON")
}

prepare_stack_sources() (
    exec 7>"${CACHE_FILE}.sources.lock"
    flock 7
    source "$DIR_INSTALLER_LIB/stack_component_lib.sh"
    export STACK_HOOK_ASSETS_FILE="$STACK_TRANSACTION/candidate/state/hook-assets.json"
    if [[ "${STACK_REUSE_SOURCES:-false}" == true && -f "$STATE_ROOT/hook-assets.json" ]]; then
        cp "$STATE_ROOT/hook-assets.json" "$STACK_HOOK_ASSETS_FILE"
    fi
    STACK_SOURCES_ROWS="$STACK_TRANSACTION/source-rows.jsonl"
    : > "$STACK_SOURCES_ROWS"
    STACK_FETCH_ONLY=true apply_stack_sources
    jq -s . "$STACK_SOURCES_ROWS" > "$STACK_TRANSACTION/prepared-sources.json"
    # Pinned sources are immutable. Hooks only receive a disposable working copy;
    # a second copy under the transaction adds no isolation or recovery value.
    export STACK_PREPARED_SOURCES_FILE="$STACK_TRANSACTION/prepared-sources.json"
    # Paths belong to the cache, not to the candidate; provenance omits URLs/tokens.
    jq '[.[] | {folder,source_key,snapshot_key,snapshot_sha256,identity}]' "$STACK_PREPARED_SOURCES_FILE" > "$STACK_TRANSACTION/candidate/state/source-lock.json"
)

# Only explicitly declared deterministic hooks may skip execution. Capture their
# candidate effects (including deletions), not modifications to original sources.
stack_prepare_component_hook() (
    local component_json="$1" cache_dir="$2" hook="$3" downloaded="$4" kind="$5"
    local name key='' entry='' before='' exclusions='' source='{}'
    name="$(jq -r .folder <<< "$component_json")"
    if [[ "$(jq -r '.prepare_cache // false' <<< "$component_json")" == true && -n "${STACK_PREPARED_SOURCES_FILE:-}" ]]; then
        source="$(jq -c --arg name "$name" '.[] | select(.folder==$name) | {snapshot_sha256,identity}' "$STACK_PREPARED_SOURCES_FILE")"
        key="$(python3 "$DIR_INSTALLER_LIB/prepared_cache.py" key "$STACK_TRANSACTION/candidate" "$component_json" "$source" "$STACK_PREPARATION_LOGIC_SHA" "$INSTALL_TYPE")"
        entry="$STACK_PREPARED_CACHE/$name/$key"
        mkdir -p "$(dirname "$entry")"
        exec 6>"$entry.lock"; flock 6
        if python3 "$DIR_INSTALLER_LIB/prepared_cache.py" replay "$STACK_TRANSACTION/candidate" "$entry"; then
            info "Prepared cache reused: $name ($key)"
            return 0
        else
            local cache_status=$?
            [[ "$cache_status" == 1 ]] || error_exit "Prepared cache replay failed for $name; candidate discarded."
        fi
        before="$STACK_TRANSACTION/$name.before.json"
        exclusions="$STACK_TRANSACTION/$name.exclusions"
        : > "$exclusions"
        export STACK_EXCLUSION_RECORD="$exclusions"
        python3 "$DIR_INSTALLER_LIB/prepared_cache.py" inventory "$STACK_TRANSACTION/candidate" "$before"
    fi
    local workspace="$name"
    if [[ "$kind" != hook_only ]]; then
        workspace="$(prepare_component_workspace "$name" "$cache_dir")"
    fi
    step "Preparing component $name using $hook"
    bash "$hook" "$workspace" "$INSTALL_TYPE" "$downloaded" "$kind" || exit $?
    if [[ -n "$entry" ]]; then
        python3 "$DIR_INSTALLER_LIB/prepared_cache.py" store "$STACK_TRANSACTION/candidate" "$before" "$entry" "$exclusions"
    fi
)

# Direct archives require an expected checksum: their mutable URL has no release
# metadata contract. Authentication for private GitHub releases stays in the
# github_release adapter; Git uses normal credential helpers/SSH agents.
download_archive_source() {
    local component="$1" destination="$2" url name sha archive
    url="$(jq -r .url <<< "$component")"
    name="$(jq -r '.archive_name // "artifact.zip"' <<< "$component")"
    sha="$(jq -r .sha256 <<< "$component")"
    archive="$(stack_acquire_original_archive "$url" "$sha" "$name")" || error_exit "Direct archive acquisition failed."
    rm -rf "$destination.new"; mkdir -p "$destination.new"
    jq -n --arg archive "$archive" --arg name "$name" --arg sha "$sha" \
        '{format:"original-archive",source_type:"archive",archive_cache:$archive,asset:$name,sha256:$sha,expected_sha256:$sha}' > "$destination.new/.stack-source.json"
    rm -rf "$destination"; mv "$destination.new" "$destination"
    printf 'false\n'
}

stack_original_source_valid() {
    local folder="$1" archive sha
    [[ -f "$folder/.stack-source.json" ]] || return 1
    [[ "$(jq -r '.format // "legacy-tree"' "$folder/.stack-source.json")" == original-archive ]] || return 0
    archive="$(jq -r .archive_cache "$folder/.stack-source.json")"
    sha="$(jq -r .sha256 "$folder/.stack-source.json")"
    [[ -f "$archive" && "$(sha256sum "$archive" | cut -d' ' -f1)" == "$sha" ]]
}

stack_git_original_clean() {
    local folder="$1"
    GIT_OPTIONAL_LOCKS=0 git -C "$folder" diff --quiet HEAD -- || return 1
    [[ -z "$(GIT_OPTIONAL_LOCKS=0 git -C "$folder" ls-files --others --exclude-standard)" ]]
}
