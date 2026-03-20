#!/bin/bash
set -euo pipefail

# =============================================================================
# L4D2Updater - Sistema de Actualizaciones Automáticas
# =============================================================================
# Configura el servidor L4D2 para usar el sistema nativo de actualizaciones de Valve
# mediante srcds_l4d2 personalizado y scripts de actualización automática.

# Verify that required environment variables are defined
: "${LGSM_SERVERFILES:?The LGSM_SERVERFILES variable is not defined.}"
: "${LGSM_CONFIG:?The LGSM_CONFIG variable is not defined.}"
: "${GAMESERVER:?The GAMESERVER variable is not defined.}"

is_l4d2_updater_enabled() {
  local value="${L4D2_UPDATER:-}"

  if [ -z "$value" ]; then
    return 0
  fi

  case "${value,,}" in
    true|1|yes|on)
      return 0
      ;;
    false|0|no|off)
      return 1
      ;;
    *)
      echo -e "Invalid L4D2_UPDATER value: ${value}"
      exit 1
      ;;
  esac
}

# Function to install L4D2Updater system
install_l4d2_updater() {
  echo -e ""
  echo -e "Installing L4D2Updater system"
  echo -e "================================="
  
  local SRCDS_ORIGINAL="${LGSM_SERVERFILES}/srcds_run"
  local SRCDS_L4D2="${LGSM_SERVERFILES}/srcds_l4d2"
  local UPDATE_SCRIPT="${LGSM_SERVERFILES}/update_l4d2.txt"
  local LGSM_COMMON_CFG="${LGSM_CONFIG}/${GAMESERVER}/common.cfg"
  
  # Check if srcds_run exists (game must be installed first)
  if [ ! -f "${SRCDS_ORIGINAL}" ]; then
    echo -e "Warning: srcds_run not found. L4D2 server must be installed first."
    echo -e "   Expected location: ${SRCDS_ORIGINAL}"
    return 1
  fi
  
  # Create srcds_l4d2 clone if it doesn't exist
  if [ ! -f "${SRCDS_L4D2}" ]; then
    echo -e "Creating srcds_l4d2 clone from srcds_run..."
    cp "${SRCDS_ORIGINAL}" "${SRCDS_L4D2}"
    chmod +x "${SRCDS_L4D2}"
    
    # Modify srcds_l4d2 for auto-update functionality
    echo -e "Configuring srcds_l4d2 for auto-updates..."
    
    # Check if the variables exist before trying to modify them
    if grep -q 'AUTO_UPDATE=""' "${SRCDS_L4D2}"; then
      sed -i 's/AUTO_UPDATE=""/AUTO_UPDATE="yes"/' "${SRCDS_L4D2}"
      echo -e "  AUTO_UPDATE set to 'yes'"
    else
      echo -e "  Warning: AUTO_UPDATE variable not found, adding manually..."
      echo 'AUTO_UPDATE="yes"' >> "${SRCDS_L4D2}"
    fi
    
    if grep -q 'STEAM_DIR=""' "${SRCDS_L4D2}"; then
      sed -i 's|STEAM_DIR=""|STEAM_DIR="$HOME/.steam/steam/steamcmd"|' "${SRCDS_L4D2}"
      echo -e "  STEAM_DIR configured"
    else
      echo -e "  Warning: STEAM_DIR variable not found, adding manually..."
      echo 'STEAM_DIR="$HOME/.steam/steam/steamcmd"' >> "${SRCDS_L4D2}"
    fi
    
    if grep -q 'STEAMCMD_SCRIPT=""' "${SRCDS_L4D2}"; then
      sed -i 's|STEAMCMD_SCRIPT=""|STEAMCMD_SCRIPT="$HOME/serverfiles/update_l4d2.txt"|' "${SRCDS_L4D2}"
      echo -e "  STEAMCMD_SCRIPT configured"
    else
      echo -e "  Warning: STEAMCMD_SCRIPT variable not found, adding manually..."
      echo 'STEAMCMD_SCRIPT="$HOME/serverfiles/update_l4d2.txt"' >> "${SRCDS_L4D2}"
    fi
    
    echo -e "srcds_l4d2 created and configured"
  else
    echo -e "srcds_l4d2 already exists, skipping creation"
  fi
  
  # Create update_l4d2.txt script if it doesn't exist
  if [ ! -f "${UPDATE_SCRIPT}" ]; then
    echo -e "Creating update_l4d2.txt script..."
    
    # Always use anonymous login for updates to avoid SteamGuard prompts
    # Using Steam credentials would require manual approval on each server start
    echo -e "Using anonymous login for updates (avoids SteamGuard prompts)"
    create_anonymous_update_script "${UPDATE_SCRIPT}"
    
    echo -e "update_l4d2.txt created"
  else
    echo -e "update_l4d2.txt already exists, skipping creation"
  fi
  
  # Configure LGSM to use srcds_l4d2
  if [ -f "${LGSM_COMMON_CFG}" ]; then
    if ! grep -q 'executable="./srcds_l4d2"' "${LGSM_COMMON_CFG}"; then
      echo -e "Configuring LGSM to use srcds_l4d2..."
      echo "" >> "${LGSM_COMMON_CFG}"
      echo "## Game Server Directories" >> "${LGSM_COMMON_CFG}"
      echo 'executable="./srcds_l4d2"' >> "${LGSM_COMMON_CFG}"
      echo -e "LGSM configured to use srcds_l4d2"
    else
      echo -e "LGSM already configured to use srcds_l4d2"
    fi
  else
    echo -e "Warning: LGSM common.cfg not found at: ${LGSM_COMMON_CFG}"
    echo -e "   Will be configured when LGSM creates the file"
  fi
  
  echo -e "L4D2Updater system installation completed."
  echo -e "   The server will now automatically check for updates using Valve's native system."
  echo -e "   Files created:"
  echo -e "   - ${SRCDS_L4D2}"
  echo -e "   - ${UPDATE_SCRIPT}"
  echo -e "   - Configuration in ${LGSM_COMMON_CFG}"
}

# Helper function to create anonymous update script
create_anonymous_update_script() {
  local script_path="$1"
  cat > "${script_path}" << 'EOF'
@ShutdownOnFailedCommand 1
@NoPromptForPassword 1
force_install_dir /data/serverfiles/
login anonymous
app_update 222860
quit
EOF
}

# Main execution
main() {
  # Check if L4D2Updater is disabled
  if ! is_l4d2_updater_enabled; then
    echo -e ""
    echo -e "L4D2Updater installation skipped"
    echo -e "================================="
    return 0
  fi
  
  # Check if server files exist
  if [ ! -d "${LGSM_SERVERFILES}" ]; then
    echo -e "Skipping L4D2Updater installation"
    echo -e "================================="
    echo -e "Server files directory not found yet: ${LGSM_SERVERFILES}"
    echo -e "   L4D2Updater will be installed after the base server is present."
    return 0
  fi
  
  # Check if srcds_run exists
  if [ ! -f "${LGSM_SERVERFILES}/srcds_run" ]; then
    echo -e "Skipping L4D2Updater installation"
    echo -e "================================="
    echo -e "srcds_run not found in: ${LGSM_SERVERFILES}"
    echo -e "   L4D2Updater will be installed after the L4D2 server is fully installed."
    return 0
  fi
  
  # Install L4D2Updater system
  install_l4d2_updater
}

# Execute main function
main "$@"
