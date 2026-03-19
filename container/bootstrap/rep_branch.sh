#!/bin/bash
# Script: rep_branch.sh
# Description: Updates dynamic fields in repos.json according to environment variables.
#              Git sources use BRANCH_{FOLDER} and GitHub release sources can use
#              RELEASE_TAG_{FOLDER}. If the value is "default", the update is skipped.

# Path to the sources.json file
REPOS_FILE="/app/stack/sources.json"

# Check if the file exists
if [ ! -f "$REPOS_FILE" ]; then
    echo "The file $REPOS_FILE does not exist."
    exit 1
fi

# Create a temporary file to work with
TMP_FILE=$(mktemp)
cp "$REPOS_FILE" "$TMP_FILE"

# Get the number of objects in the JSON array
NUM=$(jq length "$TMP_FILE")

# Iterate over each element in the array
for ((i=0; i<NUM; i++)); do
    # Get the value of the "folder" field
    FOLDER=$(jq -r ".[$i].folder" "$TMP_FILE")
    BRANCH_VAR_NAME="BRANCH_$(echo "$FOLDER" | tr '[:lower:]' '[:upper:]')"
    BRANCH_VALUE=${!BRANCH_VAR_NAME:-default}

    if [ "$BRANCH_VALUE" != "default" ]; then
        jq --arg val "$BRANCH_VALUE" ".[$i].branch = \$val" "$TMP_FILE" > "${TMP_FILE}.tmp" && mv "${TMP_FILE}.tmp" "$TMP_FILE"
        echo "Updated branch '$FOLDER' to '$BRANCH_VALUE'."
    fi

    RELEASE_TAG_VAR_NAME="RELEASE_TAG_$(echo "$FOLDER" | tr '[:lower:]' '[:upper:]')"
    RELEASE_TAG_VALUE=${!RELEASE_TAG_VAR_NAME:-default}

    if [ "$RELEASE_TAG_VALUE" != "default" ]; then
        jq --arg val "$RELEASE_TAG_VALUE" ".[$i].release_tag = \$val" "$TMP_FILE" > "${TMP_FILE}.tmp" && mv "${TMP_FILE}.tmp" "$TMP_FILE"
        echo "Updated release tag '$FOLDER' to '$RELEASE_TAG_VALUE'."
    fi
done

# Replace the original file with the updated version
mv "$TMP_FILE" "$REPOS_FILE"
echo "sources.json file updated."

exit 0