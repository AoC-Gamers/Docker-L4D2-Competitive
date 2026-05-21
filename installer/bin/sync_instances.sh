#!/bin/bash
set -euo pipefail

#####################################################
# Verify that the necessary environment variables are defined
: "${DIR_INSTALLER_BIN:?The DIR_INSTALLER_BIN variable is not defined.}"
: "${DIR_INSTALLER_LIB:?The DIR_INSTALLER_LIB variable is not defined.}"
: "${DIR_INSTALLER_CONFIG:?The DIR_INSTALLER_CONFIG variable is not defined.}"
: "${DIR_APP:?The DIR_APP variable is not defined.}"
: "${DIR_SOURCEMOD:?The DIR_SOURCEMOD variable is not defined.}"
: "${DIR_CFG:?The DIR_CFG variable is not defined.}"
: "${GAMESERVER:?The GAMESERVER variable is not defined.}"

#####################################################
# Function library
source "$DIR_INSTALLER_LIB/tools_stack.sh"
source "$DIR_INSTALLER_LIB/state_stack.sh"
source "$DIR_INSTALLER_LIB/instance_stack.sh"

state_init_paths

#####################################################
# Verify if the script is run as the user ${USER}
check_user "${USER}"

#####################################################
# Variables and constants
LGSM_PRIMARY_INSTANCE_SETUP="./linuxgsm.sh l4d2server"
L4D2_DEFAULT_SERVERCFG="${L4D2_DEFAULT_SERVERCFG:-server.cfg}"
INSTANCE_EXCLUDE_JSON="$DIR_INSTALLER_CONFIG/instances_exclude.json"

#####################################################
# Helper functions
remove_path_if_present() {
    local target_path="$1"

    if [ -L "$target_path" ] || [ -f "$target_path" ]; then
        rm -f "$target_path" || error_exit "Error deleting $target_path"
        info "Deleted file/symlink: $target_path"
        return 0
    fi

    if [ -d "$target_path" ]; then
        rm -rf "$target_path" || error_exit "Error deleting $target_path"
        info "Deleted directory: $target_path"
    fi
}

sync_sourcemod_layout() {
    local dest_dir="$1"

    if [ -e "$dest_dir" ] || [ -L "$dest_dir" ]; then
        step "Refreshing SourceMod layout in $dest_dir"
        remove_path_if_present "$dest_dir"
    else
        step "Creating SourceMod directory $dest_dir"
    fi

    mkdir "$dest_dir" || error_exit "Error creating the directory $dest_dir"
    create_sourcemod_links "$dest_dir"
}

cleanup_extra_instances() {
    local target_total_instances="$1"
    local max_index="$target_total_instances"
    local file=""
    local file_name=""
    local suffix=""
    local sourcemod_base=""
    local i=0
    local instance_name=""

    sourcemod_base="$(basename "$DIR_SOURCEMOD")"

    shopt -s nullglob

    for file in "$DIR_APP/$GAMESERVER"-* "$DIR_CFG/$GAMESERVER"-*.cfg "${DIR_SOURCEMOD}"*; do
        file_name="$(basename "$file")"
        suffix=""

        if [[ "$file" == "$DIR_APP/$GAMESERVER"-* ]]; then
            suffix="${file_name#${GAMESERVER}-}"
        elif [[ "$file" == "$DIR_CFG/$GAMESERVER"-*.cfg ]]; then
            suffix="${file_name#${GAMESERVER}-}"
            suffix="${suffix%.cfg}"
        elif [[ "$file" == "${DIR_SOURCEMOD}"* ]]; then
            suffix="${file_name#${sourcemod_base}}"
        fi

        if [[ "$suffix" =~ ^[0-9]+$ ]] && (( suffix > max_index )); then
            max_index="$suffix"
        fi
    done

    shopt -u nullglob

    if (( max_index <= target_total_instances )); then
        return 0
    fi

    for (( i=target_total_instances+1; i<=max_index; i++ )); do
        instance_name="$(instance_name_for_index "$i")"
        step "Removing runtime artifacts for extra instance ${instance_name}"
        remove_path_if_present "$DIR_APP/$instance_name"
        remove_path_if_present "$DIR_CFG/${instance_name}.cfg"
        remove_path_if_present "${DIR_SOURCEMOD}${i}"
    done
}

# Function to create symbolic links or copy according to the JSON
create_sourcemod_links() {
    local dest_dir="$1"
    local folders=("bin" "configs" "data" "extensions" "gamedata" "plugins" "translations")

    for folder in "${folders[@]}"; do
        local source_folder="${DIR_SOURCEMOD}/${folder}"
        local dest_folder="${dest_dir}/${folder}"
        [ -d "$source_folder" ] || continue

        local copy_items=()
        if [ -f "$INSTANCE_EXCLUDE_JSON" ]; then
            mapfile -t copy_items < <(jq -r --arg key "$folder" '.[$key] // [] | .[]' "$INSTANCE_EXCLUDE_JSON")
        fi

        for exclude in "${copy_items[@]}"; do
            if [ ! -e "${source_folder}/${exclude}" ]; then
                echo "Warning: The item to copy '$folder/$exclude' does not exist in ${source_folder}"
            fi
        done

        if [ ${#copy_items[@]} -eq 0 ]; then
            ln -s "$source_folder" "$dest_folder" || error_exit "Error creating symlink for folder $folder"
            echo "Symlink created for the entire folder: $folder"
        else
            mkdir -p "$dest_folder"
            for item in "$source_folder"/*; do
                [ -e "$item" ] || continue
                local base_item
                base_item=$(basename "$item")
                local target="${dest_folder}/${base_item}"
                if printf "%s\n" "${copy_items[@]}" | grep -qx "$base_item"; then
                    cp -r "$item" "$target" || error_exit "Error copying $folder/$base_item to $target"
                    echo "Copied: $folder/$base_item"
                else
                    ln -s "$item" "$target" || error_exit "Error creating symlink for $folder/$base_item in $target"
                    echo "Symlink created: $folder/$base_item"
                fi
            done
        fi
    done
}

#####################################################
# Process parameters and request the number of additional instances if not provided
if [ $# -eq 1 ]; then
    ADDITIONAL_INSTANCES="$1"
    if ! [[ "$ADDITIONAL_INSTANCES" =~ ^[0-9]+$ ]]; then
        warn "The number of additional instances must be a natural number greater than or equal to 0."
        exit 1
    fi
fi

if [ -z "${ADDITIONAL_INSTANCES:-}" ]; then
    read -rp "How many additional runtime instances do you want to create? " ADDITIONAL_INSTANCES
fi

if ! [[ "$ADDITIONAL_INSTANCES" =~ ^[0-9]+$ ]]; then
    error_exit "The provided value is not a valid number."
fi

section "Instance synchronization"
info "Primary instance: ${GAMESERVER}"
info "Requested additional instances: ${ADDITIONAL_INSTANCES}"

#####################################################
# Change to the server installation directory
cd "$DIR_APP" || error_exit "Could not access the directory $DIR_APP"

mkdir -p "$(dirname "$INSTANCES_STATE_FILE")"

#####################################################
# Ensure the primary instance exists
if [ ! -f "$DIR_APP/$GAMESERVER" ]; then
    step "Primary instance executable not found. Creating ${GAMESERVER}."
    $LGSM_PRIMARY_INSTANCE_SETUP
    ./"$GAMESERVER" details > /dev/null
fi

if [ ! -f "$DIR_CFG/$L4D2_DEFAULT_SERVERCFG" ]; then
    warn "Default configuration file not found: $DIR_CFG/$L4D2_DEFAULT_SERVERCFG"
elif [ ! -f "$DIR_CFG/$GAMESERVER.cfg" ]; then
    step "Copying configuration for primary instance ${GAMESERVER}"
    cp "$DIR_CFG/$L4D2_DEFAULT_SERVERCFG" "$DIR_CFG/$GAMESERVER.cfg"
fi

cleanup_extra_instances "$((ADDITIONAL_INSTANCES + 1))"

#####################################################
# Loop to create and align additional instances
for (( i=1; i<=ADDITIONAL_INSTANCES+1; i++ )); do
    instance_name="$(instance_name_for_index "$i")"

    DIR_NEW_SOURCEMOD="${DIR_SOURCEMOD}${i}"

    if [ -f "$DIR_APP/$instance_name" ]; then
        info "Instance $instance_name already exists. Skipping executable creation."
    else
        step "Creating instance ${instance_name}"
        $LGSM_PRIMARY_INSTANCE_SETUP
        ./$instance_name details > /dev/null
    fi

    if [ ! -f "$DIR_CFG/$L4D2_DEFAULT_SERVERCFG" ]; then
        warn "Default configuration file not found: $DIR_CFG/$L4D2_DEFAULT_SERVERCFG"
    elif [ ! -f "$DIR_CFG/${instance_name}.cfg" ]; then
        step "Copying configuration for ${instance_name}"
        cp "$DIR_CFG/$L4D2_DEFAULT_SERVERCFG" "$DIR_CFG/${instance_name}.cfg"
    fi

    sync_sourcemod_layout "$DIR_NEW_SOURCEMOD"

done

success "Instance synchronization completed"

#####################################################
# Save the last execution in a JSON file
state_write_instances_state "$ADDITIONAL_INSTANCES"
info "Instance state saved in $INSTANCES_STATE_FILE"
