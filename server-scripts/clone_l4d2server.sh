#!/bin/bash
set -euo pipefail

#####################################################
# Verify that the necessary environment variables are defined
: "${DIR_SCRIPTING:?The DIR_SCRIPTING variable is not defined.}"
: "${DIR_SOURCEMOD:?The DIR_SOURCEMOD variable is not defined.}"
: "${DIR_CFG:?The DIR_CFG variable is not defined.}"

#####################################################
# Function library
source "$DIR_SCRIPTING/tools_gameserver.sh"

#####################################################
# Verify if the script is run as the user ${USER}
check_user "${USER}"

#####################################################
# Variables and constants
LGSM_L4D2SERVER="./linuxgsm.sh l4d2server"
L4D2_DEFAULT_SERVERCFG="${L4D2_DEFAULT_SERVERCFG:-server.cfg}"
CLONE_L4D2SERVER="$DIR_SCRIPTING/clone_l4d2server.json"

# JSON file with the list of paths to be copied (relative to DIR_SOURCEMOD)
CLONE_EXCLUDE_JSON="$DIR_SCRIPTING/clone_exclude.json"

#####################################################
# Function to create symbolic links or copy according to the JSON
create_sourcemod_links() {
    local dest_dir="$1"
    # List of top-level folders to process
    local folders=("bin" "configs" "data" "extensions" "gamedata" "plugins" "translations")
    
    for folder in "${folders[@]}"; do
        local source_folder="${DIR_SOURCEMOD}/${folder}"
        local dest_folder="${dest_dir}/${folder}"
        # If the source directory does not exist, skip
        [ -d "$source_folder" ] || continue

        # If the JSON file exists, load the list of items to copy for this folder,
        # otherwise, use an empty array.
        local copy_items=()
        if [ -f "$CLONE_EXCLUDE_JSON" ]; then
            mapfile -t copy_items < <(jq -r --arg key "$folder" '.[$key][]' "$CLONE_EXCLUDE_JSON")
        fi

        # Verify that the listed items to copy exist in the source directory
        for exclude in "${copy_items[@]}"; do
            if [ ! -e "${source_folder}/${exclude}" ]; then
                echo "Warning: The item to copy '$folder/$exclude' does not exist in ${source_folder}"
            fi
        done

        if [ ${#copy_items[@]} -eq 0 ]; then
            # If there are no items to copy, create a symlink for the entire directory
            ln -s "$source_folder" "$dest_folder" || error_exit "Error creating symlink for folder $folder"
            echo "Symlink created for the entire folder: $folder"
        else
            # Create the destination directory
            mkdir -p "$dest_folder"
            # Process each item within the source directory
            for item in "$source_folder"/*; do
                [ -e "$item" ] || continue
                local base_item
                base_item=$(basename "$item")
                local target="${dest_folder}/${base_item}"
                # If the item name exactly matches one of the listed items, copy it
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
# Process parameters and request the number of clones if not provided
if [ $# -eq 1 ]; then
    AMOUNT_CLONES="$1"
    if ! [[ "$AMOUNT_CLONES" =~ ^[0-9]+$ ]]; then
        echo "Must be a natural number equal to or greater than 0."
        exit 1
    fi
fi

if [ -z "${AMOUNT_CLONES:-}" ]; then
    read -rp "How many gameserver clones do you want to create? " AMOUNT_CLONES
fi

# Validate that AMOUNT_CLONES is numeric
if ! [[ "$AMOUNT_CLONES" =~ ^[0-9]+$ ]]; then
    error_exit "The provided value is not a valid number."
fi

#####################################################
# Change to the server installation directory
cd "$DIR_APP" || error_exit "Could not access the directory $DIR_APP"

#####################################################
# Create directories for the first server
if [ "$AMOUNT_CLONES" -eq 0 ]; then

    if [ ! -f "$DIR_APP/l4d2server" ]; then
        echo "The file $DIR_APP/l4d2server does not exist. Creating the first server."
        $LGSM_L4D2SERVER
        ./l4d2server details > /dev/null
    fi

    if [ ! -d "${DIR_SOURCEMOD}1" ]; then
        echo "Creating the subdirectory sourcemod1 for the first server..."
        mkdir "${DIR_SOURCEMOD}1" || error_exit "Error creating the subdirectory sourcemod1"
        create_sourcemod_links "${DIR_SOURCEMOD}1"
    fi

    if [ ! -f "$DIR_CFG/$L4D2_DEFAULT_SERVERCFG" ]; then
        echo "The default configuration file does not exist: $DIR_CFG/$L4D2_DEFAULT_SERVERCFG"
    elif [ ! -f "$DIR_CFG/$GAMESERVER.cfg" ]; then
        echo "Copying server configuration for $GAMESERVER..."
        cp "$DIR_CFG/$L4D2_DEFAULT_SERVERCFG" "$DIR_CFG/$GAMESERVER.cfg"
    fi
fi

#####################################################
# Loop to create server clones
for (( i=1; i<=AMOUNT_CLONES+1; i++ )); do
    if [ "$AMOUNT_CLONES" -eq 1 ]; then
        if [ -d "${DIR_SOURCEMOD}1" ]; then
            echo "Verifying symbolic links for sourcemod1..."
            create_sourcemod_links "${DIR_SOURCEMOD}1"
        fi
        exit 0
    fi

    if [ "$i" -eq 1 ]; then
        SERVER_NAME="${GAMESERVER}"
    else
        SERVER_NAME="${GAMESERVER}-$i"
    fi

    DIR_NEW_SOURCEMOD="${DIR_SOURCEMOD}${i}"

    if [ -f "$DIR_APP/$SERVER_NAME" ]; then
        echo "The server $SERVER_NAME already exists. Skipping..."
    else
        echo "Creating the server $SERVER_NAME..."
        $LGSM_L4D2SERVER
        ./$SERVER_NAME details > /dev/null
    fi

    # Copy configuration if the specific copy for the server does not exist
    if [ ! -f "$DIR_CFG/$L4D2_DEFAULT_SERVERCFG" ]; then
        echo "The default configuration file does not exist: $DIR_CFG/$L4D2_DEFAULT_SERVERCFG"
    elif [ ! -f "$DIR_CFG/${SERVER_NAME}.cfg" ]; then
        echo "Copying server configuration for $SERVER_NAME..."
        cp "$DIR_CFG/$L4D2_DEFAULT_SERVERCFG" "$DIR_CFG/${SERVER_NAME}.cfg"
    fi

    # Create the server-specific SourceMod directory if it does not exist
    if [ -d "$DIR_NEW_SOURCEMOD" ]; then
        echo "The directory $DIR_NEW_SOURCEMOD already exists..."
        continue
    fi

    echo "Creating the directory: $DIR_NEW_SOURCEMOD"
    mkdir "$DIR_NEW_SOURCEMOD" || error_exit "Error creating the directory $DIR_NEW_SOURCEMOD"
    create_sourcemod_links "$DIR_NEW_SOURCEMOD"
done

echo "Cloning process completed."

#####################################################
# Save the last execution in a JSON file
echo "{\"last_execution\": \"$(date)\", \"amount_clones\": $AMOUNT_CLONES}" > "$CLONE_L4D2SERVER"
echo "Last execution record saved in $CLONE_L4D2SERVER."
