#!/bin/bash
# The parent keeps FD 8 open. A nested command verifies the actual inherited lock.
stack_acquire_target_lock() {
    local target key lock_root lock_file inherited
    target="$(realpath -m "$DIR_LEFT4DEAD2")"
    key="$(printf '%s' "$target" | sha256sum | cut -d' ' -f1)"
    lock_root="${STACK_LOCK_ROOT:-/tmp/l4d2-stack-locks-$(id -u)}"
    mkdir -p "$lock_root"
    chmod 700 "$lock_root"
    lock_file="$lock_root/$key.lock"
    if [[ "${STACK_LOCK_TARGET:-}" == "$target" && -e /proc/$$/fd/8 ]]; then
        inherited="$(readlink /proc/$$/fd/8)"
        if [[ "$inherited" == "$lock_file" ]] && flock -n 8; then
            return 0
        fi
    fi
    exec 8>"$lock_file"
    flock 8
    export STACK_LOCK_TARGET="$target"
}
