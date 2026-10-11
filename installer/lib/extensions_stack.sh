#!/bin/bash
# Two synchronous extension slots. A configured path is mandatory, errors abort.
stack_run_extension() {
    local phase="$1" script
    case "$phase" in after-sync|idle) ;; *) error_exit "Unknown extension phase: $phase" ;; esac
    script="${DIR_CONTAINER_EXTENSIONS:-${DIR_APP:-/app}/container/extensions}/${phase}.sh"
    local required=false policy="${DIR_STACK:-/nonexistent}/extension-policy.json"
    if [[ -f "$policy" ]]; then
        required="$(jq -r --arg phase "$phase" '.[$phase] // false' "$policy")"
    fi
    if [[ -f "$script" ]]; then
        bash "$script" "$phase"
    elif [[ "$required" == true ]]; then
        error_exit "Required extension missing: $phase"
    fi
}

stack_validate_extensions() {
    local phase script policy="${DIR_STACK:-/nonexistent}/extension-policy.json"
    [[ -f "$policy" ]] || return 0
    jq -e 'type=="object" and (keys - ["after-sync","idle"] | length)==0 and all(.[]; type=="boolean")' "$policy" >/dev/null
    for phase in after-sync idle; do
        script="${DIR_CONTAINER_EXTENSIONS:-${DIR_APP:-/app}/container/extensions}/$phase.sh"
        if [[ "$(jq -r --arg phase "$phase" '.[$phase] // false' "$policy")" == true ]]; then
            [[ -f "$script" ]] || error_exit "Required extension missing: $phase"
            bash -n "$script"
        fi
    done
}
