#!/bin/bash
# tools_stack.sh - Inclusion file with common functions for installer scripts.
#
# Usage:
#   source "$DIR_INSTALLER_LIB/tools_stack.sh"
DIR_APP="${DIR_APP:-/app}"
DIR_TMP="${DIR_TMP:-/app/tmp}"

supports_color() {
    if [ -n "${NO_COLOR:-}" ] || [ "${TERM:-}" = "dumb" ]; then
        return 1
    fi

    [ -t 1 ]
}

color_text() {
    local color_code="$1"
    shift

    if supports_color; then
        printf '\033[%sm%s\033[0m' "$color_code" "$*"
    else
        printf '%s' "$*"
    fi
}

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

print_divider() {
    color_text "2;37" "============================================================"
    printf '\n'
}

section() {
    printf '\n'
    print_divider
    color_text "1;36" "$1"
    printf '\n'
    print_divider
}

info() {
    log "$(color_text "1;34" "INFO") : $1"
}

warn() {
    log "$(color_text "1;33" "WARN") : $1"
}

success() {
    log "$(color_text "1;32" "OK")   : $1"
}

step() {
    log "$(color_text "1;35" "STEP") : $1"
}

github_auth_token() {
    if [ -n "${GITHUB_AUTH_TOKEN:-}" ]; then
        printf '%s\n' "${GITHUB_AUTH_TOKEN}"
        return 0
    fi

    if [ -n "${GITHUB_TOKEN:-}" ]; then
        printf '%s\n' "${GITHUB_TOKEN}"
        return 0
    fi

    return 1
}

github_auth_curl_args() {
    local auth_token=""

    if auth_token="$(github_auth_token)"; then
        printf '%s\n' "-H" "Authorization: Bearer ${auth_token}"
    fi
}

github_api_request() {
    local api_url="$1"
    local -a curl_args=(
        -fsSL
        -H "Accept: application/vnd.github+json"
        -H "X-GitHub-Api-Version: 2022-11-28"
    )

    mapfile -t auth_args < <(github_auth_curl_args)
    curl_args+=( "${auth_args[@]}" )

    curl "${curl_args[@]}" "$api_url"
}

github_http_status() {
    local url="$1"
    local destination="$2"
    local -a curl_args=(
        -sSL
        -o "$destination"
        -w "%{http_code}"
    )

    if [[ "$url" == https://api.github.com/* || "$url" == https://github.com/* ]]; then
        mapfile -t auth_args < <(github_auth_curl_args)
        curl_args+=( "${auth_args[@]}" )
    fi

    curl "${curl_args[@]}" "$url"
}

download_file() {
    local url="$1"
    local destination="$2"
    local -a curl_args=( -fsSL -o "$destination" )

    if [[ "$url" == https://api.github.com/* || "$url" == https://github.com/* ]]; then
        mapfile -t auth_args < <(github_auth_curl_args)
        curl_args+=( "${auth_args[@]}" )
    fi

    if [[ "$url" == https://api.github.com/repos/*/releases/assets/* ]]; then
        curl_args+=( -H "Accept: application/octet-stream" )
    fi

    curl "${curl_args[@]}" "$url"
}

extract_archive() {
    local archive_path="$1"
    local destination_dir="$2"

    mkdir -p "$destination_dir"

    case "$archive_path" in
        *.zip)
            unzip -oq "$archive_path" -d "$destination_dir"
            ;;
        *.tar.gz|*.tgz)
            tar -xzf "$archive_path" -C "$destination_dir"
            ;;
        *.tar)
            tar -xf "$archive_path" -C "$destination_dir"
            ;;
        *)
            error_exit "Unsupported archive format: $archive_path"
            ;;
    esac
}

dir_has_entries() {
    local dir_path="$1"

    [ -d "$dir_path" ] && [ -n "$(ls -A "$dir_path" 2> /dev/null)" ]
}

validate_archive() {
    local archive_path="$1"
    local validate_dir=""
    local validate_root="${DIR_TMP:-/tmp}"

    if [ ! -s "$archive_path" ]; then
        return 1
    fi

    if ! mkdir -p "$validate_root" 2> /dev/null; then
        validate_root="/tmp"
        mkdir -p "$validate_root" 2> /dev/null || return 1
    fi

    case "$archive_path" in
        *.zip)
            unzip -tq "$archive_path" > /dev/null 2>&1
            ;;
        *.tar.gz|*.tgz)
            gzip -t "$archive_path" > /dev/null 2>&1 || return 1
            validate_dir="$(mktemp -d "${validate_root%/}/validate-tgz-XXXXXX")" || return 1
            if tar -xzf "$archive_path" -C "$validate_dir" > /dev/null 2>&1 && dir_has_entries "$validate_dir"; then
                rm -rf "$validate_dir"
                return 0
            fi
            rm -rf "$validate_dir"
            return 1
            ;;
        *.tar)
            validate_dir="$(mktemp -d "${validate_root%/}/validate-tar-XXXXXX")" || return 1
            if tar -xf "$archive_path" -C "$validate_dir" > /dev/null 2>&1 && dir_has_entries "$validate_dir"; then
                rm -rf "$validate_dir"
                return 0
            fi
            rm -rf "$validate_dir"
            return 1
            ;;
        *)
            return 1
            ;;
    esac
}

debug_archive_validation_failure() {
    local archive_path="$1"

    log "Archive debug for: $archive_path" >&2

    if command -v file > /dev/null 2>&1; then
        file "$archive_path" >&2 || true
    fi

    if command -v od > /dev/null 2>&1; then
        od -An -tx1 -N16 "$archive_path" >&2 || true
    fi

    case "$archive_path" in
        *.tar.gz|*.tgz)
            gzip -t "$archive_path" >&2 || true
            if ! tar -tzf "$archive_path" > /dev/null 2> "${archive_path}.tar.stderr"; then
                log "tar -tzf stderr for $archive_path:" >&2
                sed -n '1,40p' "${archive_path}.tar.stderr" >&2 || true
            fi
            rm -f "${archive_path}.tar.stderr"
            ;;
        *.tar)
            if ! tar -tf "$archive_path" > /dev/null 2> "${archive_path}.tar.stderr"; then
                log "tar -tf stderr for $archive_path:" >&2
                sed -n '1,40p' "${archive_path}.tar.stderr" >&2 || true
            fi
            rm -f "${archive_path}.tar.stderr"
            ;;
        *.zip)
            unzip -t "$archive_path" >&2 || true
            ;;
    esac
}

error_exit() {
    log "$(color_text "1;31" "ERROR"): $1"
    exit 1
}

verify_and_delete_dir() {
    if [ -d "$1" ]; then
        rm -rf "$1"
        log "Directory '$1' deleted."
    else
        log "Directory '$1' does not exist."
    fi
}

verify_and_delete_file() {
    if [ -f "$1" ]; then
        rm "$1"
        log "File '$1' deleted."
    else
        log "File '$1' does not exist."
    fi
}

check_user() {
    if [ "$(whoami)" != "$1" ]; then
        if [ "$(whoami)" = "root" ]; then
            log "The script is running as root. Switching to user '$1'..."
            exec su - "$1" -c "$0"
        else
            error_exit "You must run this script as user '$1' or as root."
        fi
    fi
}
