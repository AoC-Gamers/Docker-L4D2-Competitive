#!/bin/bash
# instance_stack.sh - Helpers for multi-instance runtime operations.

instance_name_for_index() {
    local index="$1"

    if [ "$index" -eq 1 ]; then
        printf '%s\n' "$GAMESERVER"
    else
        printf '%s\n' "${GAMESERVER}-${index}"
    fi
}

instance_executable_path() {
    local index="$1"
    local instance_name

    instance_name="$(instance_name_for_index "$index")"
    printf '%s\n' "$DIR_APP/$instance_name"
}

instance_calculate_total() {
    local total_servers=0
    local additional_instance_count=0
    local file
    local pattern="$DIR_APP/$GAMESERVER-"

    if [[ -x "$DIR_APP/$GAMESERVER" ]]; then
        total_servers=1
        info "Primary instance detected: $DIR_APP/$GAMESERVER" >&2
    else
        error_exit "The primary instance ($DIR_APP/$GAMESERVER) does not exist or is not executable."
    fi

    shopt -s nullglob
    for file in "$pattern"*; do
        if [[ -x "$file" ]]; then
            additional_instance_count=$((additional_instance_count + 1))
            info "Additional instance detected: $file" >&2
        fi
    done
    shopt -u nullglob

    total_servers=$(( total_servers + additional_instance_count ))
    info "Calculated total: $total_servers instances ($additional_instance_count additional + 1 primary)" >&2
    printf '%s\n' "$total_servers"
}

instance_validate_range() {
    local start_range="$1"
    local end_range="$2"
    local total_servers="$3"

    if (( start_range < 1 || end_range > total_servers || start_range > end_range )); then
        error_exit "Invalid instance range."
    fi
}

instance_for_each_in_range() {
    local start_range="$1"
    local end_range="$2"
    local callback="$3"
    local index
    local executable

    (( end_range == 0 )) && end_range=1

    for (( index = start_range; index <= end_range; index++ )); do
        executable="$(instance_executable_path "$index")"
        "$callback" "$index" "$executable"
    done
}
