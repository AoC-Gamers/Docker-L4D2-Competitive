#!/bin/bash
set -euo pipefail
source "$DIR_INSTALLER_LIB/tools_stack.sh"
source "$DIR_INSTALLER_LIB/state_stack.sh"
source "$DIR_INSTALLER_LIB/instance_stack.sh"
source "$DIR_INSTALLER_LIB/target_lock.sh"
state_init_paths
stack_acquire_target_lock
mkdir -p "$STATE_ROOT"
intent="$STATE_ROOT/runtime-intent.json"
case "${1:-}" in
    capture)
        rows="$(mktemp "$STATE_ROOT/runtime-intent.XXXXXX")"
        trap 'rm -f "$rows"' EXIT
        for executable in "$DIR_APP/$GAMESERVER" "$DIR_APP/$GAMESERVER"-*; do
            [[ -x "$executable" && -f "$executable" ]] || continue
            name="$(basename "$executable")"
            [[ "$name" == "$GAMESERVER" || "$name" =~ ^${GAMESERVER}-[0-9]+$ ]] || continue
            if instance_is_running "$name"; then printf '%s\n' "$name" >> "$rows"; fi
        done
        jq -Rn '[inputs | select(length>0)]' < "$rows" > "$intent.tmp"
        mv "$intent.tmp" "$intent"
        sync -f "$intent"
        ;;
    resume)
        case "${L4D2_AUTOSTART:-true}" in
            [fF][aA][lL][sS][eE]|0|[nN][oO]|[oO][fF][fF]) exit 0 ;;
        esac
        [[ -f "$intent" ]] || exit 0
        while IFS= read -r name; do
            [[ "$name" == "$GAMESERVER" || "$name" =~ ^${GAMESERVER}-[0-9]+$ ]] || error_exit "Invalid saved runtime intent."
            [[ -x "$DIR_APP/$name" ]] || continue
            if ! instance_is_running "$name"; then "$DIR_APP/$name" start; fi
        done < <(jq -r '.[]' "$intent")
        ;;
    *) error_exit "Use capture or resume." ;;
esac
