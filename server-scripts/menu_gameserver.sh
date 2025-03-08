#!/bin/bash
set -euo pipefail

#####################################################
# Check that the necessary environment variables are defined
: "${DIR_SCRIPTING:?The DIR_SCRIPTING variable is not defined.}"

#####################################################
# Function library
source "$DIR_SCRIPTING/tools_gameserver.sh"

#####################################################
# Variables and constants
CLONE_L4D2SERVER="$DIR_SCRIPTING/clone_l4d2server.json"

# It is assumed that the base file $DIR_APP/$GAMESERVER always exists.
if [[ -f "$DIR_APP/$GAMESERVER" ]]; then
    TOTAL_SERVERS=1
else
    echo "The base server ($DIR_APP/$GAMESERVER) does not exist."
    exit 1
fi

PATTERN="$DIR_APP/$GAMESERVER-"
CLONE_COUNT=0

for file in "$PATTERN"*; do
    if [[ -f "$file" ]]; then
        CLONE_COUNT=$(( CLONE_COUNT + 1 ))
    fi
done

TOTAL_SERVERS=$(( TOTAL_SERVERS + CLONE_COUNT ))

#####################################################
# If the JSON file exists, consistency is checked.
# The number of detected clones (CLONE_COUNT) is compared with the value in JSON.
if [[ -f "$CLONE_L4D2SERVER" ]]; then
    CLONED_SERVERS=$(jq '.amount_clones' "$CLONE_L4D2SERVER")
    if [[ $CLONED_SERVERS -ne $CLONE_COUNT ]]; then
        echo "An inconsistency was detected. Running the cloning script..."
        "$DIR_SCRIPTING/clone_l4d2server.sh" "$CLONED_SERVERS"
    fi
fi

#####################################################
# Function: menu
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

    # Edge case: if end_range is 0, force it to 1.
    if [[ $end_range -eq 0 ]]; then
        end_range=1
    fi

    for (( i = start_range; i <= end_range; i++ )); do
        local executable
        if [[ $i -eq 1 ]]; then
            executable="$DIR_APP/$GAMESERVER"
        else
            executable="$DIR_APP/$GAMESERVER-$i"
        fi

        if [[ -x "$executable" ]]; then
            # If it fails, a warning is displayed and it continues.
            "$executable" start || echo "[WARN] Could not start $executable, continuing..."
        else
            echo "The executable file $executable does not exist or does not have execution permissions."
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
            executable="$DIR_APP/$GAMESERVER"
        else
            executable="$DIR_APP/$GAMESERVER-$i"
        fi

        if [[ -x "$executable" ]]; then
            "$executable" stop || echo "[WARN] Could not stop $executable, continuing..."
        else
            echo "The executable file $executable does not exist or does not have execution permissions."
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
            executable="$DIR_APP/$GAMESERVER"
        else
            executable="$DIR_APP/$GAMESERVER-$i"
        fi

        if [[ -x "$executable" ]]; then
            "$executable" restart || echo "[WARN] Could not restart $executable, continuing..."
        else
            echo "The executable file $executable does not exist or does not have execution permissions."
        fi
    done
    echo "Done"
}

#####################################################
# Function: update_servers
# Updates the servers. If the update type is "automatic",
# they are stopped and restarted.
update_servers() {
    local update_type=${1:-manual}
    if [[ $update_type == "automatic" ]]; then
        stop_servers 1 "$TOTAL_SERVERS"
    fi
    "$DIR_SCRIPTING/install_gameserver.sh" 1
    if [[ $update_type == "automatic" ]]; then
        start_servers 1 "$TOTAL_SERVERS"
    fi
}

#####################################################
# Argument processing or interactive menu.
if [[ $# -eq 0 ]]; then
    menu
    read -rp "Selection: " choice
    case $choice in
        1)
            start_servers 1 "$TOTAL_SERVERS"
            ;;
        2)
            stop_servers 1 "$TOTAL_SERVERS"
            ;;
        3)
            restart_servers 1 "$TOTAL_SERVERS"
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
    # One parameter: applies the command to all servers.
    command=$1
    start_range=1
    end_range=$TOTAL_SERVERS
elif [[ $# -eq 2 ]]; then
    # Two parameters: the first is the command and the second is the start range;
    # the end range is defined as the total number of servers.
    command=$1
    start_range=$2
    end_range=$TOTAL_SERVERS
elif [[ $# -eq 3 ]]; then
    # Three parameters: explicitly define the command, start range, and end range.
    command=$1
    start_range=$2
    end_range=$3
else
    echo "Usage: $0 {command [start_range [end_range]]}"
    exit 1
fi

# If parameters were passed, the range is validated and the corresponding command is executed.
if [[ $# -ge 1 ]]; then
    if [[ $start_range -lt 1 || $end_range -gt $TOTAL_SERVERS || $start_range -gt $end_range ]]; then
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