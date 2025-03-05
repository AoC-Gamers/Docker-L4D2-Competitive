#!/bin/bash
set -euo pipefail

#####################################################
# Verify that the necessary environment variables are defined
: "${DIR_SCRIPTING:?The DIR_SCRIPTING variable is not defined.}"

#####################################################
# Function library
source "$DIR_SCRIPTING/git-gameserver/tools_gameserver.sh"

#####################################################
# Variables and constants
CLONE_L4D2SERVER="$DIR_SCRIPTING/clone_l4d2server.json"

# Reinitialize the server counter
SERVER_COUNT=0

#####################################################
# Count the main server (without hyphen) and the clones.
if [[ -x "$DIR_APP/l4d2server" ]]; then
    ((SERVER_COUNT++))
fi

for file in "$DIR_APP"/l4d2server-*; do
    if [[ -f "$file" ]]; then
        ((SERVER_COUNT++))
    fi
done

# If no server is found, an error message is displayed.
if [[ $SERVER_COUNT -eq 0 ]]; then
    echo "No servers found (file $DIR_APP/l4d2server or clones)."
    exit 1
fi

#####################################################
# If the JSON file exists, check consistency.
if [[ -f "$CLONE_L4D2SERVER" ]]; then
    CLONED_SERVERS=$(jq '.amount_clones' "$CLONE_L4D2SERVER")
    
    if [[ $CLONED_SERVERS -ne $SERVER_COUNT ]]; then
        echo "Inconsistency detected. Running the server cloning script..."
        "$DIR_SCRIPTING/clone_l4d2server.sh" "$CLONED_SERVERS"
    fi
fi

#####################################################
# Function: menu
# Displays the interactive menu and reads the selected option.
menu() {
    echo "Gameservers Menu"
    echo "1 - Start"
    echo "2 - Stop"
    echo "3 - Restart"
    echo "4 - Automatic Update"
    echo "5 - Update"
    echo "* - Exit"
}

#####################################################
# Function: start_servers
# Starts the servers in the specified range.
start_servers() {
    local start_range=$1
    local end_range=$2

    # If end_range is 0, force it to 1 (edge case)
    if [[ $end_range -eq 0 ]]; then
        end_range=1
    fi

    for (( i = start_range; i <= end_range; i++ )); do
        local executable
        if [[ $i -eq 1 ]]; then
            executable="$DIR_APP/l4d2server"
        else
            executable="$DIR_APP/l4d2server-$i"
        fi

        if [[ -x "$executable" ]]; then
            "$executable" start
        else
            echo "Executable file $executable not found or does not have execution permissions."
        fi
    done
}

#####################################################
# Function: stop_servers
# Stops the servers in the specified range.
stop_servers() {
    local start_range=$1
    local end_range=$2

    if [[ $end_range -eq 0 ]]; then
        end_range=1
    fi

    for (( i = start_range; i <= end_range; i++ )); do
        local executable
        if [[ $i -eq 1 ]]; then
            executable="$DIR_APP/l4d2server"
        else
            executable="$DIR_APP/l4d2server-$i"
        fi

        if [[ -x "$executable" ]]; then
            "$executable" stop
        else
            echo "Executable file $executable not found or does not have execution permissions."
        fi
    done
    echo "Done"
}

#####################################################
# Function: restart_servers
# Restarts the servers in the specified range.
restart_servers() {
    local start_range=$1
    local end_range=$2

    if [[ $end_range -eq 0 ]]; then
        end_range=1
    fi
    
    for (( i = start_range; i <= end_range; i++ )); do
        local executable
        if [[ $i -eq 1 ]]; then
            executable="$DIR_APP/l4d2server"
        else
            executable="$DIR_APP/l4d2server-$i"
        fi

        if [[ -x "$executable" ]]; then
            "$executable" restart
        else
            echo "Executable file $executable not found or does not have execution permissions."
        fi
    done
    echo "Done"
}

#####################################################
# Function: update_servers
# Updates the servers. If the update type is "automatic",
# the servers are stopped and restarted.
update_servers() {
    local update_type=${1:-manual}
    if [[ $update_type == "automatic" ]]; then
        stop_servers 1 "$SERVER_COUNT"
    fi
    "$DIR_SCRIPTING/install_gameserver.sh" 1
    if [[ $update_type == "automatic" ]]; then
        start_servers 1 "$SERVER_COUNT"
    fi
}

#####################################################
# Command line arguments processing or interactive menu.
if [[ $# -eq 0 ]]; then
    # No parameters: the interactive menu is displayed.
    menu
    read -rp "Selection: " choice
    case $choice in
        1)
            start_servers 1 "$SERVER_COUNT"
            ;;
        2)
            stop_servers 1 "$SERVER_COUNT"
            ;;
        3)
            restart_servers 1 "$SERVER_COUNT"
            ;;
        4)
            update_servers automatic
            ;;
        5)
            update_servers manual
            ;;
        *)
            echo "Done"
            ;;
    esac
elif [[ $# -eq 1 ]]; then
    # One parameter: applies the command to all gameservers.
    command=$1
    start_range=1
    end_range=$SERVER_COUNT
elif [[ $# -eq 2 ]]; then
    # Two parameters: the first is the command and the second is the start range;
    # the end range is defined as the maximum number of gameservers.
    command=$1
    start_range=$2
    end_range=$SERVER_COUNT
elif [[ $# -eq 3 ]]; then
    # Three parameters: the command, the start range, and the end range are explicitly defined.
    command=$1
    start_range=$2
    end_range=$3
else
    echo "Usage: $0 {command [start_range [end_range]]}"
    exit 1
fi

# If parameters were passed, the range is checked and the corresponding command is executed.
if [[ $# -ge 1 ]]; then
    if [[ $start_range -lt 1 || $end_range -gt $SERVER_COUNT || $start_range -gt $end_range ]]; then
        echo "Invalid range."
        exit 1
    fi

    case $command in
        st|start)
            start_servers "$start_range" "$end_range"
            ;;
        s|stop)
            stop_servers "$start_range" "$end_range"
            ;;
        r|restart)
            restart_servers "$start_range" "$end_range"
            ;;
        aup|aupdate)
            update_servers automatic
            ;;
        up|update)
            update_servers manual
            ;;
        *)
            echo "Invalid command."
            exit 1
            ;;
    esac
fi
