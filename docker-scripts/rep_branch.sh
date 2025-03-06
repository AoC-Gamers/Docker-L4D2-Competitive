#!/bin/bash
# Script: rep_branch.sh
# Description: Updates the "branch" field in the repos.json file according to environment variables.
#              Each variable has the prefix "BRANCH_" followed by the folder name in uppercase.
#              If the variable is "default", the update is skipped for that repository.

# Path to the repos.json file
REPOS_FILE="/app/server-scripts/repos.json"

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
    # Construct the environment variable name (e.g., BRANCH_SIR)
    VAR_NAME="BRANCH_$(echo "$FOLDER" | tr '[:lower:]' '[:upper:]')"
    # Get the value of the variable; if not defined, use "default"
    VALUE=${!VAR_NAME:-default}

    # Check if the value is "default"
    if [ "$VALUE" != "default" ]; then
        # Update the "branch" field with the obtained value
        jq --arg val "$VALUE" ".[$i].branch = \$val" "$TMP_FILE" > "${TMP_FILE}.tmp" && mv "${TMP_FILE}.tmp" "$TMP_FILE"
        echo "Updated branch '$FOLDER' to '$VALUE'."
    fi
done

# Replace the original file with the updated version
mv "$TMP_FILE" "$REPOS_FILE"
echo "repos.json file updated."

exit 0