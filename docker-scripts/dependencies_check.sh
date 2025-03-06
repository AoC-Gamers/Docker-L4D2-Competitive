#!/bin/bash
set -euo pipefail

#####################################################
# Define LOG_FILE based on whether running as root or not
if [ "$(id -u)" -eq 0 ]; then
    LOG_FILE="/dev/null"
else
    LOG_FILE="${DIR_SCRIPTING:-.}/dependencies.log"
fi

echo "Starting dependency check..." | tee -a "$LOG_FILE"

#####################################################
# Flag to avoid multiple apt updates
APT_UPDATED=false

#####################################################
# Function to update package information only once
update_apt() {
    if [ "$APT_UPDATED" = false ]; then
        DEBIAN_FRONTEND=noninteractive apt-get update > /dev/null
        DEBIAN_FRONTEND=noninteractive apt-get upgrade -y > /dev/null
        APT_UPDATED=true
    fi
}

#####################################################
# Function to check and install a package
check_package() {
    local pkg="$1"
    echo "Checking package: $pkg" | tee -a "$LOG_FILE"
    if dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
        echo "[x] $pkg" | tee -a "$LOG_FILE"
    else
        echo "[ ] $pkg" | tee -a "$LOG_FILE"
        echo "Installing $pkg..." | tee -a "$LOG_FILE"
        update_apt
        if DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg" > /dev/null; then
            echo "Installed $pkg" | tee -a "$LOG_FILE"
        else
            echo "Error installing $pkg" | tee -a "$LOG_FILE"
        fi
    fi
}

#####################################################
# Function to iterate over the package list
print_checklist() {
    echo "Package checklist:" | tee -a "$LOG_FILE"
    for package in "$@"; do
        check_package "$package"
    done
}

#####################################################
# List of packages to check
packages=("openssh-server" "curl" "wget" "file" "tar" "bzip2" "gzip" "unzip" "bsdmainutils" "util-linux" "ca-certificates" "binutils" "bc" "jq" "tmux" "netcat-openbsd" "lib32gcc-s1" "lib32stdc++6" "libsdl2-2.0-0:i386" "steamcmd" "gdb" "lib32z1" "rsync" "libcurl4" "htop" "git" "p7zip-full" "p7zip-rar" "sed")

print_checklist "${packages[@]}"

echo "Dependency check completed." | tee -a "$LOG_FILE"
