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

validate_archive() {
    local archive_path="$1"

    if [ ! -s "$archive_path" ]; then
        return 1
    fi

    case "$archive_path" in
        *.zip)
            unzip -tq "$archive_path" > /dev/null 2>&1
            ;;
        *.tar.gz|*.tgz)
            tar -tzf "$archive_path" > /dev/null 2>&1
            ;;
        *.tar)
            tar -tf "$archive_path" > /dev/null 2>&1
            ;;
        *)
            return 1
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
