#!/bin/bash
set -euo pipefail

APP_STACK_DIR="${APP_STACK_DIR:-/app/stack}"
STACK_PROFILE="${STACK_PROFILE:-default}"
MANIFESTS_FILE="$APP_STACK_DIR/manifests/components.json"
PROFILE_FILE="$APP_STACK_DIR/profiles/${STACK_PROFILE}.json"
SOURCES_FILE="$APP_STACK_DIR/sources.json"

if [ ! -f "$MANIFESTS_FILE" ]; then
    echo "The manifests file $MANIFESTS_FILE does not exist."
    exit 1
fi

if [ ! -f "$PROFILE_FILE" ]; then
    echo "The profile file $PROFILE_FILE does not exist."
    exit 1
fi

jq -n \
    --slurpfile manifests "$MANIFESTS_FILE" \
    --slurpfile profile "$PROFILE_FILE" \
    '
    [
      $profile[0].components[] as $name |
      ($manifests[0][$name] // error("Unknown component: " + $name)) as $component |
      ($profile[0].overrides[$name] // {}) as $override |
      $component + $override
    ]
    ' > "$SOURCES_FILE"

NUM=$(jq length "$SOURCES_FILE")
for ((i=0; i<NUM; i++)); do
    FOLDER=$(jq -r ".[$i].folder" "$SOURCES_FILE")
    BRANCH_VAR_NAME="BRANCH_$(echo "$FOLDER" | tr '[:lower:]' '[:upper:]')"
    BRANCH_VALUE=${!BRANCH_VAR_NAME:-default}

    if [ "$BRANCH_VALUE" != "default" ]; then
        jq --arg val "$BRANCH_VALUE" ".[$i].branch = \$val" "$SOURCES_FILE" > "${SOURCES_FILE}.tmp" && mv "${SOURCES_FILE}.tmp" "$SOURCES_FILE"
        echo "Updated branch '$FOLDER' to '$BRANCH_VALUE'."
    fi

    RELEASE_TAG_VAR_NAME="RELEASE_TAG_$(echo "$FOLDER" | tr '[:lower:]' '[:upper:]')"
    RELEASE_TAG_VALUE=${!RELEASE_TAG_VAR_NAME:-default}

    if [ "$RELEASE_TAG_VALUE" != "default" ]; then
        jq --arg val "$RELEASE_TAG_VALUE" ".[$i].release_tag = \$val" "$SOURCES_FILE" > "${SOURCES_FILE}.tmp" && mv "${SOURCES_FILE}.tmp" "$SOURCES_FILE"
        echo "Updated release tag '$FOLDER' to '$RELEASE_TAG_VALUE'."
    fi
done

echo "Generated $SOURCES_FILE using profile '$STACK_PROFILE'."