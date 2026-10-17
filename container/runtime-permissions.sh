#!/bin/bash
# Only entry points need executable permission. Never chmod persistent caches,
# game data, Git checkouts or downloaded archives recursively.
stack_set_runtime_executables() {
    local app="$1" directory entry
    for directory in "$app/container" "$app/installer/bin" "$app/stack/hooks" "$app/lgsm/modules"; do
        [[ -d "$directory" ]] || continue
        find "$directory" -type f -name '*.sh' -exec chmod a+x -- {} +
    done
    for entry in "$app/linuxgsm.sh" "$app"/l4d2server "$app"/l4d2server-*; do
        [[ -f "$entry" && ! -L "$entry" ]] || continue
        chmod a+x -- "$entry"
    done
}
