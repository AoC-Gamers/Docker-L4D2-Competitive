#!/bin/bash
set -euo pipefail

#####################################################
# Variables and environment validations
: "${DIR_SCRIPTING:?The DIR_SCRIPTING variable is not defined.}"
: "${DIR_ADDONS:?The DIR_ADDONS variable is not defined.}"

#####################################################
# Function library
source "$DIR_SCRIPTING/tools_gameserver.sh"

#####################################################
# Verify if the script is run as the user ${USER}
check_user "${USER}"

#####################################################
# Variables and constants
SCRIPT_NAME=$(basename "$0")
LOG_FILE="$DIR_TMP/${SCRIPT_NAME%.sh}.log"
DIR_MAPS="$DIR_TMP/maps"
URL_CENTER="https://l4d2center.com/maps/servers/index.json"
CACHE_INDEX="$DIR_TMP/cache_maps_l4d2center.json"

# Force download of all maps (false by default)
L4D2_MAPS_FORCE_DOWNLOAD=${L4D2_MAPS_FORCE_DOWNLOAD:-false}

# If specified, only the map whose name (without extension) matches will be processed
L4D2_MAP=${L4D2_MAP:-}

# Variable to skip MD5 verification (false by default)
L4D2_MAPS_NO_MD5=${L4D2_MAPS_NO_MD5:-false}

#####################################################
# Create necessary directories
mkdir -p "$DIR_MAPS"
mkdir -p "$DIR_ADDONS"

#####################################################
# Function: log_message
log_message() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" | tee -a "$LOG_FILE"
}

#####################################################
# Function: verify_vpk_md5
# Extracts a compressed file and verifies the MD5 of the first .vpk file.
# Parameters:
#   $1: Compressed file (.7z or .zip)
#   $2: Expected MD5 for the extracted .vpk.
verify_vpk_md5() {
    local archive="$1"
    local expected_md5="$2"
    local temp_dir
    temp_dir=$(mktemp -d)
    
    if [[ "$archive" == *.7z ]]; then
        7z x "$archive" -o"$temp_dir" -bsp1
    elif [[ "$archive" == *.zip ]]; then
        unzip -qq -d "$temp_dir" "$archive"
    else
        rm -rf "$temp_dir"
        return 1
    fi

    local vpk_file
    vpk_file=$(find "$temp_dir" -maxdepth 1 -type f -name "*.vpk" | head -n 1)
    if [ -z "$vpk_file" ]; then
        log_message "Error: No .vpk file found in $(basename "$archive")."
        rm -rf "$temp_dir"
        return 1
    fi

    if [[ "$L4D2_MAPS_NO_MD5" == "false" ]]; then
        local actual_md5
        actual_md5=$(md5sum "$vpk_file" | awk '{print $1}')
        rm -rf "$temp_dir"
        [[ "$actual_md5" == "$expected_md5" ]]
    else
        rm -rf "$temp_dir"
        return 0
    fi
}

#####################################################
# Function: process_map
# Extracts the compressed file, verifies (if applicable), and moves the .vpk to DIR_ADDONS.
# Then, deletes the compressed file.
# Parameters:
#   $1: Compressed file
#   $2: Expected MD5 for the extracted .vpk.
process_map() {
    local archive="$1"
    local expected_md5="$2"
    local temp_dir
    temp_dir=$(mktemp -d)
    
    log_message "Extracting $(basename "$archive") in $temp_dir..."
    if [[ "$archive" == *.7z ]]; then
        7z x "$archive" -o"$temp_dir" -bsp1
    elif [[ "$archive" == *.zip ]]; then
        unzip -qq -d "$temp_dir" "$archive"
    else
        log_message "Error: Unsupported format for $(basename "$archive")."
        rm -rf "$temp_dir"
        return 1
    fi

    local vpk_file
    vpk_file=$(find "$temp_dir" -maxdepth 1 -type f -name "*.vpk" | head -n 1)
    if [ -z "$vpk_file" ]; then
        log_message "Error: No .vpk file found in $(basename "$archive")."
        rm -rf "$temp_dir"
        return 1
    fi

    if [[ "$L4D2_MAPS_NO_MD5" == "false" ]]; then
        local actual_md5
        actual_md5=$(md5sum "$vpk_file" | awk '{print $1}')
        if [[ "$actual_md5" != "$expected_md5" ]]; then
            log_message "Error: MD5 verification failed for $(basename "$archive"). Expected: $expected_md5, got: $actual_md5."
            rm -rf "$temp_dir"
            return 1
        else
            log_message "MD5 verification successful for $(basename "$archive")."
        fi
    else
        log_message "L4D2_MAPS_NO_MD5 enabled: skipping MD5 verification for $(basename "$archive")."
    fi

    log_message "Moving $(basename "$vpk_file") to $DIR_ADDONS..."
    mv "$vpk_file" "$DIR_ADDONS/"
    rm -rf "$temp_dir"
    rm -f "$archive"  # Delete the compressed file after processing
    return 0
}

#####################################################
# Function: download_and_process_map
# Downloads the compressed file, processes it, and retries up to 3 times.
# Parameters:
#   $1: Download URL
#   $2: Destination file for the compressed file
#   $3: Expected MD5 for the extracted .vpk.
download_and_process_map() {
    local url="$1"
    local file="$2"
    local md5_expected="$3"
    local attempts=3
    local attempt=1

    while [ $attempt -le $attempts ]; do
        log_message "Attempt $attempt: Downloading $(basename "$file") from $url..."
        curl -L -o "$file" -# "$url"
        if [[ -f "$file" ]]; then
            if process_map "$file" "$md5_expected"; then
                log_message "$(basename "$file") processed successfully."
                return 0
            else
                log_message "Error: Processing $(basename "$file") failed (attempt $attempt of $attempts)."
                rm -f "$file"
            fi
        fi
        attempt=$((attempt + 1))
    done
    return 1
}

#####################################################
# Download the new index.json to a temporary file
NEW_INDEX="$DIR_MAPS/index_new.json"
log_message "Downloading map list from $URL_CENTER..."
curl -L -o "$NEW_INDEX" -# "$URL_CENTER"

#####################################################
# Compare the new index with the previous cache
if [[ -f "$CACHE_INDEX" ]]; then
    if diff -q "$NEW_INDEX" "$CACHE_INDEX" > /dev/null && [[ "$L4D2_MAPS_FORCE_DOWNLOAD" != "true" ]]; then
        log_message "The index.json has not changed and download was not forced. Maps will be copied from the cache."
        log_message "Process completed (no changes)."
        exit 0
    else
        log_message "Changes detected in index.json or download was forced."
    fi
else
    log_message "No previous cache found. A full download will be performed."
fi

#####################################################
# Compare each map in the new index with the previous cache to determine which ones to update.
declare -A old_cache
if [[ -f "$CACHE_INDEX" ]]; then
    while IFS="=" read -r key value; do
        old_cache["$key"]="$value"
    done < <(jq -r 'to_entries[] | "\(.key)=\(.value)"' "$CACHE_INDEX")
fi

MAPS_TO_UPDATE=()
while IFS= read -r map_entry; do
    map_name=$(echo "$map_entry" | jq -r '.name')
    # If L4D2_MAP is specified, compare the name without extension
    if [[ -n "$L4D2_MAP" ]]; then
        map_base="${map_name%.vpk}"
        if [[ "$map_base" != "$L4D2_MAP" ]]; then
            log_message "Map \"$map_name\" does not match L4D2_MAP ($L4D2_MAP), skipping."
            continue
        fi
    fi
    map_md5=$(echo "$map_entry" | jq -r '.md5')
    if [[ "$L4D2_MAPS_FORCE_DOWNLOAD" == "true" ]] || [[ "${old_cache[$map_name]:-}" != "$map_md5" ]]; then
        log_message "Map \"$map_name\" has changed or download will be forced (cache: \"${old_cache[$map_name]:-none}\", new: \"$map_md5\")."
        MAPS_TO_UPDATE+=("$map_entry")
    else
        log_message "Map \"$map_name\" has not changed."
    fi
done < <(jq -c '.[]' "$NEW_INDEX")

#####################################################
# Process only the maps that have changed or need to be updated
if [ ${#MAPS_TO_UPDATE[@]} -eq 0 ]; then
    log_message "No changes detected in maps (or L4D2_MAP was not specified). Files will be copied from the cache."
else
    log_message "Updating ${#MAPS_TO_UPDATE[@]} map(s)."
    for map_entry in "${MAPS_TO_UPDATE[@]}"; do
        NAME=$(echo "$map_entry" | jq -r '.name')
        URL=$(echo "$map_entry" | jq -r '.download_link' | sed 's/ /%20/g')
        MD5_EXPECTED=$(echo "$map_entry" | jq -r '.md5')
        FILE_NAME="${NAME%.vpk}.7z"
        FILE_PATH="$DIR_MAPS/$FILE_NAME"
        
        if [[ -f "$FILE_PATH" ]]; then
            log_message "$FILE_NAME already exists but will be updated (did not pass cache verification)."
            rm -f "$FILE_PATH"
        fi
        
        if ! download_and_process_map "$URL" "$FILE_PATH" "$MD5_EXPECTED"; then
            log_message "Final error: Could not update $FILE_NAME after several attempts."
        fi
    done
fi

#####################################################
# Update the cache with the new index.
NEW_CACHE=$(jq 'reduce .[] as $map ({}; .[$map.name] = $map.md5)' "$NEW_INDEX")
echo "$NEW_CACHE" > "$CACHE_INDEX"
log_message "Cache updated: $CACHE_INDEX"

#####################################################
# Extract and move .vpk files from the remaining compressed files
# Only process files that still exist in DIR_MAPS (updated ones have been deleted)
log_message "Extracting files and moving .vpk to $DIR_ADDONS..."
find "$DIR_MAPS" -type f \( -iname "*.7z" -o -iname "*.zip" \) | while IFS= read -r file; do
    base=$(basename "$file")
    map_name="${base%.7z}.vpk"
    expected_md5=$(jq -r --arg name "$map_name" '.[$name]' "$CACHE_INDEX")
    process_map "$file" "$expected_md5" || true
done

log_message "Process completed."
