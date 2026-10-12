#!/bin/bash
# Original bytes live in a content-addressed persistent cache. This function
# prints only the path; callers resolve a channel once and pass its exact URL.
stack_acquire_original_archive() (
    local url="$1" expected="${2#sha256:}" label="$3"
    local root="${STACK_ARTIFACT_CACHE:-${DIR_INSTALLER:-${DIR_TMP}}/cache/artifacts}"
    local archive part sha
    [[ "$label" =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ && "$label" != *..* ]] || error_exit "Invalid archive filename."
    mkdir -p "$root"
    if [[ -n "$expected" ]]; then
        [[ "$expected" =~ ^[a-f0-9]{64}$ ]] || error_exit "Invalid expected archive checksum."
        archive="$root/$expected/$label"
        exec 5>"$root/$expected.lock"; flock 5
        if [[ "${GIT_FORCE_DOWNLOAD:-false}" != true && -f "$archive" && "$(sha256sum "$archive" | cut -d' ' -f1)" == "$expected" ]]; then
            subsection "Reuse original archive: $label" >&2
            info "Original archive reused: $label (verified checksum)" >&2
            printf '%s\n' "$archive"; return
        fi
    fi
    part="$(mktemp "$root/.download-XXXXXX")"
    trap 'rm -f -- "$part"' EXIT
    subsection "Download original archive: $label" >&2
    download_file "$url" "$part" || return 1
    subsection "Validate original archive: $label" >&2
    sha="$(sha256sum "$part" | cut -d' ' -f1)"
    [[ -z "$expected" || "$sha" == "$expected" ]] || error_exit "Checksum mismatch for $label."
    validate_archive "$part" || error_exit "Invalid archive: $label."
    archive="$root/$sha/$label"
    mkdir -p "$(dirname "$archive")"
    mv -f "$part" "$archive" || return 1
    local verification="content identity only"
    [[ -z "$expected" ]] || verification="expected checksum"
    info "Original archive ready: $label (sha256=$sha; verification=$verification)" >&2
    printf '%s\n' "$archive"
)

# A validated pristine expansion is reusable even when the hook changes.
# Version the extractor in the key; hooks always receive an editable copy.
stack_expand_original_archive() (
    local archive="$1" sha="$2" destination="$3" key root expanded
    [[ -f "$archive" && "$(sha256sum "$archive" | cut -d' ' -f1)" == "$sha" ]] || error_exit "Original archive missing/corrupt."
    key="$(printf '%s:%s' "$sha" "$(sha256sum "$DIR_INSTALLER_LIB/safe_extract.py" | cut -d' ' -f1)" | sha256sum | cut -d' ' -f1)"
    root="${STACK_ARTIFACT_CACHE:-${DIR_INSTALLER}/cache/artifacts}/expanded"
    mkdir -p "$root"
    exec 5>"$root/$key.lock"; flock 5
    expanded="$root/$key"
    if [[ ! -d "$expanded" || ! -f "$expanded.sha256" || "$(python3 "$DIR_INSTALLER_LIB/source_identity.py" "$expanded" --archive-tree-v1)" != "$(cat "$expanded.sha256")" ]]; then
        subsection "Extract original archive: $(basename "$archive")" >&2
        rm -rf "$expanded.new"
        mkdir -p "$expanded.new"
        extract_archive "$archive" "$expanded.new" || return 1
        python3 "$DIR_INSTALLER_LIB/source_identity.py" "$expanded.new" --archive-tree-v1 > "$expanded.sha256.new" || return 1
        rm -rf "$expanded"
        mv "$expanded.new" "$expanded" || return 1
        mv "$expanded.sha256.new" "$expanded.sha256" || return 1
    else
        subsection "Reuse extracted archive: $(basename "$archive")" >&2
    fi
    subsection "Copy original archive to editable workspace" >&2
    cp -a "$expanded/." "$destination/"
)
