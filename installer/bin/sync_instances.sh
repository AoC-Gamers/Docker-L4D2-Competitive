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
source "$DIR_INSTALLER_LIB/target_lock.sh"
stack_acquire_target_lock

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
normalize_relative_path() {
    local value="$1"

    value="${value#./}"
    value="${value#/}"
    value="${value%/}"

    printf '%s\n' "$value"
}

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

path_is_exact_match() {
    local relative_path="$1"
    shift
    local candidate=""

    for candidate in "$@"; do
        if [ "$relative_path" = "$candidate" ]; then
            return 0
        fi
    done

    return 1
}

path_has_excluded_descendant() {
    local relative_path="$1"
    shift
    local candidate=""

    for candidate in "$@"; do
        if [[ "$candidate" == "${relative_path}/"* ]]; then
            return 0
        fi
    done

    return 1
}

warn_missing_excluded_paths() {
    local source_folder="$1"
    shift
    local excluded_paths=("$@")
    local excluded_path=""

    for excluded_path in "${excluded_paths[@]}"; do
        if [ ! -e "${source_folder}/${excluded_path}" ]; then
            warn "The item to copy '${excluded_path}' does not exist in ${source_folder}"
        fi
    done
}

sync_tree_with_exclusions() {
    local source_dir="$1"
    local dest_dir="$2"
    local relative_prefix="$3"
    shift 3
    local excluded_paths=("$@")
    local item=""
    local base_item=""
    local item_relative_path=""
    local target=""

    mkdir -p "$dest_dir"

    for item in "$source_dir"/*; do
        [ -e "$item" ] || continue
        base_item="$(basename "$item")"

        if [ -n "$relative_prefix" ]; then
            item_relative_path="${relative_prefix}/${base_item}"
        else
            item_relative_path="$base_item"
        fi

        target="${dest_dir}/${base_item}"

        if path_is_exact_match "$item_relative_path" "${excluded_paths[@]}"; then
            cp -a "$item" "$target" || error_exit "Error copying ${item_relative_path} to ${target}"
            echo "Copied: ${item_relative_path}"
        elif [ -d "$item" ] && path_has_excluded_descendant "$item_relative_path" "${excluded_paths[@]}"; then
            sync_tree_with_exclusions "$item" "$target" "$item_relative_path" "${excluded_paths[@]}"
        else
            ln -s "$item" "$target" || error_exit "Error creating symlink for ${item_relative_path} in ${target}"
            echo "Symlink created: ${item_relative_path}"
        fi
    done
}

sync_sourcemod_layout() {
    local dest_dir="$1" stable="${DIR_SOURCEMOD%/*}/.instance-data/$(basename "$1")"
    local new="${1}.next" old="${1}.previous" folder relative source_path stable_path parent linked
    # Recover the layout rename. Private data uses a stable location and is never copied.
    if [[ ! -e "$dest_dir" && -d "$old" ]]; then mv "$old" "$dest_dir"; fi
    mkdir -p "$stable"
    for folder in data logs configs; do
        if [[ -d "$dest_dir/$folder" && ! -L "$dest_dir/$folder" && ! -e "$stable/$folder" ]]; then
            mv "$dest_dir/$folder" "$stable/$folder"
        fi
    done
    while IFS=$'\t' read -r folder relative; do
        [[ "$folder" != data && "$folder" != logs && "$folder" != configs ]] || continue
        [[ "$relative" != /* && "/$relative/" != *"/../"* ]] || error_exit "Unsafe instance exclusion."
        source_path="$dest_dir/$folder/$relative"
        stable_path="$stable/overrides/$folder/$relative"
        parent="$(dirname "$source_path")"; linked=false
        while [[ "$parent" != "$dest_dir" && "$parent" != / ]]; do
            [[ ! -L "$parent" ]] || linked=true
            parent="$(dirname "$parent")"
        done
        if [[ "$linked" == false && ( -e "$source_path" || -L "$source_path" ) && ! -e "$stable_path" && ! -L "$stable_path" ]]; then
            mkdir -p "$(dirname "$stable_path")"
            mv "$source_path" "$stable_path"
        fi
    done < <(jq -r 'to_entries[] | .key as $key | .value[] | [$key,.] | @tsv' "$INSTANCE_EXCLUDE_JSON")
    rm -rf "$new"
    mkdir -p "$new"
    create_sourcemod_links "$new"
    for folder in data logs configs; do
        if [[ -d "$stable/$folder" ]]; then
            rm -rf "$new/$folder"
            ln -s "$stable/$folder" "$new/$folder"
        fi
    done
    while IFS=$'\t' read -r folder relative; do
        stable_path="$stable/overrides/$folder/$relative"
        if [[ -e "$stable_path" || -L "$stable_path" ]]; then
            rm -rf "$new/$folder/$relative"
            mkdir -p "$(dirname "$new/$folder/$relative")"
            ln -s "$stable_path" "$new/$folder/$relative"
        fi
    done < <(jq -r 'to_entries[] | .key as $key | .value[] | [$key,.] | @tsv' "$INSTANCE_EXCLUDE_JSON")
    rm -rf "$old" # Contains only prior shared links; private paths moved above.
    if [[ -e "$dest_dir" || -L "$dest_dir" ]]; then mv "$dest_dir" "$old"; fi
    mv "$new" "$dest_dir"
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
    local folder=""
    local source_folder=""
    local dest_folder=""
    local excluded_paths=()
    local excluded_path=""

    for folder in "${folders[@]}"; do
        source_folder="${DIR_SOURCEMOD}/${folder}"
        dest_folder="${dest_dir}/${folder}"
        [ -d "$source_folder" ] || continue

        excluded_paths=()
        if [ -f "$INSTANCE_EXCLUDE_JSON" ]; then
            mapfile -t excluded_paths < <(jq -r --arg key "$folder" '.[$key] // [] | .[]' "$INSTANCE_EXCLUDE_JSON" | while IFS= read -r line; do normalize_relative_path "$line"; done)
        fi

        if [[ "$folder" == data ]]; then
            local stable_data="${DIR_SOURCEMOD%/*}/.instance-data/$(basename "${dest_dir%.next}")/data"
            mkdir -p "$stable_data"
            # Static shared entries link to the primary; private subtrees start empty.
            local entry base
            for entry in "$source_folder"/*; do
                [[ -e "$entry" ]] || continue
                base="$(basename "$entry")"
                if path_is_exact_match "$base" "${excluded_paths[@]}" || path_has_excluded_descendant "$base" "${excluded_paths[@]}"; then
                    [[ -e "$stable_data/$base" ]] || mkdir -p "$stable_data/$base"
                elif [[ ! -e "$stable_data/$base" && ! -L "$stable_data/$base" ]]; then
                    ln -s "$entry" "$stable_data/$base"
                fi
            done
            ln -s "$stable_data" "$dest_folder"
            continue
        fi

        warn_missing_excluded_paths "$source_folder" "${excluded_paths[@]}"

        if [ ${#excluded_paths[@]} -eq 0 ]; then
            ln -s "$source_folder" "$dest_folder" || error_exit "Error creating symlink for folder $folder"
            echo "Symlink created for the entire folder: $folder"
        else
            sync_tree_with_exclusions "$source_folder" "$dest_folder" "" "${excluded_paths[@]}"
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

for executable in "$DIR_APP/$GAMESERVER" "$DIR_APP/$GAMESERVER"-*; do
    [[ -x "$executable" ]] || continue
    if tmux has-session -t "=$(basename "$executable")" 2>/dev/null; then
        error_exit "Stop affected instances before direct sync_instances.sh."
    fi
done
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
