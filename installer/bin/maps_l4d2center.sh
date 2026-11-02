#!/bin/bash
set -euo pipefail

: "${DIR_INSTALLER_LIB:?The DIR_INSTALLER_LIB variable is not defined.}"
: "${DIR_ADDONS:?The DIR_ADDONS variable is not defined.}"
source "$DIR_INSTALLER_LIB/tools_stack.sh"

# This command must inherit the unprivileged runtime identity.
[[ "$EUID" != 0 ]] || error_exit "Run map synchronization as linuxgsm, never as root."
L4D2_MAPS_FORCE_DOWNLOAD=${L4D2_MAPS_FORCE_DOWNLOAD:-false}
L4D2_MAPS_NO_MD5=${L4D2_MAPS_NO_MD5:-false}
L4D2_MAP=${L4D2_MAP:-}
for flag in "$L4D2_MAPS_FORCE_DOWNLOAD" "$L4D2_MAPS_NO_MD5"; do
    [[ "$flag" == true || "$flag" == false ]] || error_exit "Map flags must be true or false."
done
for cmd in curl jq md5sum 7z stat flock mktemp realpath; do
    command -v "$cmd" >/dev/null || error_exit "Required command '$cmd' is not installed."
done

mkdir -p "$DIR_TMP/maps" "$DIR_ADDONS"
# Resolve shared addons links so instances serialize on the same destination.
DIR_ADDONS=$(realpath -e "$DIR_ADDONS")
LOG_FILE="$DIR_TMP/maps_l4d2center.log"
CACHE_INDEX="$DIR_TMP/cache_maps_l4d2center.json"
URL_CENTER="https://l4d2center.com/maps/servers/index.json"
exec 9>"$DIR_ADDONS/.maps_l4d2center.lock"
flock 9
WORK_DIR=$(mktemp -d "$DIR_TMP/maps/sync.XXXXXXXX")
STAGE_DIR=""
cleanup() {
    rm -rf -- "$WORK_DIR"
    if [[ -n "$STAGE_DIR" ]]; then rm -rf -- "$STAGE_DIR"; fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

log_message() {
    printf '%s - %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" | tee -a "$LOG_FILE"
}

log_message "Downloading map list from $URL_CENTER..."
curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
    --connect-timeout 20 --max-time 120 --retry 2 \
    --output "$WORK_DIR/index.json" "$URL_CENTER"

# Validate the whole index before writing maps. Names are plain VPK basenames,
# never paths or archive wildcard patterns. Official download URLs contain spaces.
jq -e '
    type == "array" and length > 0 and
    all(.[];
        (.name | type == "string" and test("^[A-Za-z0-9][A-Za-z0-9 ._()-]*\\.vpk$")) and
        (.md5 | type == "string" and test("^[a-fA-F0-9]{32}$")) and
        (.size | type == "number" and . > 0 and . == floor) and
        (.download_link | type == "string" and test("^https://[^/\\s]+/[^\\r\\n\\t]*$"))) and
    ([.[].name] | length == (unique | length))
' "$WORK_DIR/index.json" >/dev/null || error_exit "Invalid L4D2Center map index; existing maps preserved."
jq --arg map "$L4D2_MAP" '[.[] | select($map == "" or (.name | rtrimstr(".vpk")) == $map)]' \
    "$WORK_DIR/index.json" > "$WORK_DIR/selected.json"
[[ "$(jq length "$WORK_DIR/selected.json")" != 0 ]] || error_exit "L4D2_MAP did not match a catalog entry."
# Stage beside the destination, so replacement by rename stays on one filesystem.
STAGE_DIR=$(mktemp -d "$DIR_ADDONS/.maps_l4d2center.XXXXXXXX")

verify_vpk() {
    local file="$1" size="$2" expected_md5="$3" actual_md5
    [[ -f "$file" && ! -L "$file" ]] || return 1
    [[ "$(stat -c %s -- "$file")" == "$size" ]] || return 1
    if [[ "$L4D2_MAPS_NO_MD5" != true ]]; then
        actual_md5=$(md5sum -- "$file") || return 1
        [[ "${actual_md5%% *}" == "${expected_md5,,}" ]] || return 1
    fi
    return 0
}

download_map() {
    local name="$1" size="$2" expected_md5="$3" url="$4" attempt
    for attempt in 1 2 3; do
        log_message "Downloading $name (attempt $attempt/3)..."
        if curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
            --connect-timeout 20 --max-time 1800 --output "$WORK_DIR/map.archive" "${url// /%20}" &&
            # Stream the exact member; no archive paths, links or other addons
            # are extracted onto disk. 7z detects both ZIP and 7z archives.
            7z e -so -spd "$WORK_DIR/map.archive" "$name" > "$STAGE_DIR/map.vpk" &&
            verify_vpk "$STAGE_DIR/map.vpk" "$size" "$expected_md5"; then
            chmod 0644 "$STAGE_DIR/map.vpk" &&
                mv -fT -- "$STAGE_DIR/map.vpk" "$DIR_ADDONS/$name" || return 1
            rm -f -- "$WORK_DIR/map.archive"
            log_message "Verified and installed: $name"
            return 0
        fi
        log_message "Download, extraction or verification failed for $name; existing VPK preserved."
        rm -f -- "$WORK_DIR/map.archive" "$STAGE_DIR/map.vpk"
    done
    return 1
}

if [[ "$L4D2_MAPS_NO_MD5" == true ]]; then
    log_message "Warning: L4D2_MAPS_NO_MD5=true; only file name and size will be verified."
fi
failed=0
while IFS= read -r entry; do
    name=$(jq -r .name <<< "$entry")
    size=$(jq -r .size <<< "$entry")
    md5=$(jq -r .md5 <<< "$entry")
    url=$(jq -r .download_link <<< "$entry")
    if [[ -L "$DIR_ADDONS/$name" || ( -e "$DIR_ADDONS/$name" && ! -f "$DIR_ADDONS/$name" ) ]]; then
        log_message "Refusing to replace symlink or non-regular destination: $name"
        failed=1
    elif [[ "$L4D2_MAPS_FORCE_DOWNLOAD" != true ]] && verify_vpk "$DIR_ADDONS/$name" "$size" "$md5"; then
        log_message "Verified: $name is up to date."
    elif ! download_map "$name" "$size" "$md5" "$url"; then
        failed=1
    fi
done < <(jq -c '.[]' "$WORK_DIR/selected.json")

[[ "$failed" == 0 ]] || error_exit "Map synchronization failed; cache receipt unchanged. See $LOG_FILE"
# The receipt is informational: every invocation checks actual files. Filtered
# runs record only selected entries, never claim the entire catalog was checked.
jq 'reduce .[] as $map ({}; .[$map.name] = $map.md5)' \
    "$WORK_DIR/selected.json" > "$WORK_DIR/cache.json"
mv -fT -- "$WORK_DIR/cache.json" "$CACHE_INDEX"
log_message "Map synchronization complete; custom VPKs outside the catalog were preserved."
