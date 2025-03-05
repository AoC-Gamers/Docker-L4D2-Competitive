#!/bin/bash
# tools_gameserver.sh - Inclusion file with common functions for scripts.
#
# Usage:
#   source $DIR_SCRIPTING/git-gameserver/tools_gameserver.sh
#
# This file includes logging functions, error handling, utilities for
# verifying and deleting files and directories, and functions for
# searching and modifying shared configuration files.

DIR_APP="/app"
DIR_TMP="/app/tmp"

#######################################
# Function: log
# Logs a message with a timestamp.
# Parameters:
#   $1: Message to log.
#######################################
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

#######################################
# Function: error_exit
# Logs an error message and exits the script.
# Parameters:
#   $1: Error message.
#######################################
error_exit() {
    log "ERROR: $1"
    exit 1
}

#######################################
# Function: verify_and_delete_dir
# Verifies if a directory exists and deletes it.
# Parameters:
#   $1: Directory path.
#######################################
verify_and_delete_dir() {
    if [ -d "$1" ]; then
        rm -rf "$1"
        log "Directory '$1' deleted."
    else
        log "Directory '$1' does not exist."
    fi
}

#######################################
# Function: verify_and_delete_file
# Verifies if a file exists and deletes it.
# Parameters:
#   $1: File path.
#######################################
verify_and_delete_file() {
    if [ -f "$1" ]; then
        rm "$1"
        log "File '$1' deleted."
    else
        log "File '$1' does not exist."
    fi
}

#######################################
# Function: check_user
# Verifies if the script is running as the correct user.
# If running as root, switches to the TARGET_USER.
#######################################
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