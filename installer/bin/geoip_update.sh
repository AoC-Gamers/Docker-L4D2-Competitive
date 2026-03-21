#!/bin/bash
set -euo pipefail

if [ -f /etc/environment ]; then
  set -o allexport
  source /etc/environment
  set +o allexport
fi

: "${DIR_SOURCEMOD:?The DIR_SOURCEMOD variable is not defined.}"
: "${DIR_INSTALLER_STATE:?The DIR_INSTALLER_STATE variable is not defined.}"
: "${DIR_INSTALLER_LIB:?The DIR_INSTALLER_LIB variable is not defined.}"

source "$DIR_INSTALLER_LIB/tools_stack.sh"

is_geoip_update_enabled() {
  local value="${GEOIPUPDATE_ENABLED:-false}"

  case "${value,,}" in
    true|1|yes|on)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

download_geoip_database() {
  local edition_id="${GEOIPUPDATE_EDITION_ID:-GeoLite2-City}"
  local account_id="${GEOIPUPDATE_ACCOUNT_ID:-}"
  local license_key="${GEOIPUPDATE_LICENSE_KEY:-}"
  local geoip_dir="${DIR_SOURCEMOD}/configs/geoip"
  local state_dir="${DIR_INSTALLER_STATE}/geoip"
  local work_dir="${DIR_TMP}/geoipupdate"
  local archive_path="${work_dir}/${edition_id}.tar.gz"
  local extracted_mmdb=""
  local target_mmdb="${geoip_dir}/${edition_id}.mmdb"
  local config_file="${state_dir}/GeoIP.conf"
  local download_url=""

  if [ -z "$account_id" ] || [ -z "$license_key" ]; then
    warn "Skipping GeoIP update because GEOIPUPDATE_ACCOUNT_ID or GEOIPUPDATE_LICENSE_KEY is not defined."
    return 0
  fi

  mkdir -p "$geoip_dir" "$state_dir" "$work_dir"

  cat > "$config_file" <<EOF
AccountID ${account_id}
LicenseKey ${license_key}
EditionIDs ${edition_id}
EOF

  download_url="https://download.maxmind.com/app/geoip_download?edition_id=${edition_id}&license_key=${license_key}&suffix=tar.gz"
  step "Downloading ${edition_id} database from MaxMind"
  curl -fsSL "$download_url" -o "$archive_path"

  verify_and_delete_dir "${work_dir}/extract"
  mkdir -p "${work_dir}/extract"
  tar -xzf "$archive_path" -C "${work_dir}/extract"

  extracted_mmdb="$(find "${work_dir}/extract" -type f -name "${edition_id}.mmdb" | head -n 1)"
  if [ -z "$extracted_mmdb" ]; then
    error_exit "GeoIP update failed: ${edition_id}.mmdb was not found in the downloaded archive."
  fi

  cp "$extracted_mmdb" "$target_mmdb"
  success "GeoIP database updated: ${target_mmdb}"
}

main() {
  if ! is_geoip_update_enabled; then
    info "GeoIP update disabled. Set GEOIPUPDATE_ENABLED=true to enable it."
    return 0
  fi

  download_geoip_database
}

main "$@"
