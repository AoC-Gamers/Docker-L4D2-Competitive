#!/bin/bash
set -euo pipefail

# Verificar que la variable LGSM_SERVERFILES esté definida
: "${LGSM_SERVERFILES:?La variable LGSM_SERVERFILES no está definida.}"

update_server() {
    local platform="$1"
    steamcmd +force_install_dir "${LGSM_SERVERFILES}" +login anonymous +@sSteamCmdForcePlatformType "$platform" +app_update 222860 validate +quit
}

# Actualizar el servidor para ambas plataformas
update_server "windows"
update_server "linux"

# Si existe el enlace simbólico en /app/serverfiles, se elimina
if [ -L "/app/serverfiles" ]; then
    rm "/app/serverfiles"
fi

# Crear el enlace simbólico apuntando a LGSM_SERVERFILES
ln -s "${LGSM_SERVERFILES}" "/app/serverfiles"
