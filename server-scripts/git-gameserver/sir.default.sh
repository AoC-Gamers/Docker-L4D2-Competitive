#!/bin/bash
# sir.default.sh
# Subscript para aplicar modificaciones específicas a la rama 'default' de L4D2-Competitive-Rework.

if [ -z "$1" ]; then
    echo "Uso: $0 <REPO_DIR> <INSTALL_TYPE> <GIT_DOWNLOAD>"
    echo "  REPO_DIR: Ubicación del repositorio."
    echo "  INSTALL_TYPE: ('install'|'update') Tipo de instalación. def: install"
    echo "  GIT_DOWNLOAD: (true|false) Se descargo de repositorio remoto. def: false"
    echo ""
    echo "Ejemplo:"
    echo "  bash sir.default.sh /app/tmp/sir update true"
    exit 1
fi

# Recursos
source $DIR_SCRIPTING/git-gameserver/tools_gameserver.sh

REPO_DIR="$1"
INSTALL_TYPE="${2:-install}"
GIT_DOWNLOAD="${3:-false}"

##############################
# Variables de entorno:
##############################
DIR_SIR="$REPO_DIR"
DIR_SIR_ADDONS="$DIR_SIR/addons"
DIR_SIR_SOURCEMOD="$DIR_SIR_ADDONS/sourcemod"
DIR_SIR_METAMOD="$DIR_SIR_ADDONS/metamod"

##############################
# Funciones auxiliares:
##############################
CopyFiles() {
    cp -r "$DIR_SIR/addons" "$DIR_LEFT4DEAD2"
    cp -r "$DIR_SIR/cfg" "$DIR_LEFT4DEAD2"
    cp -r "$DIR_SIR/scripts" "$DIR_LEFT4DEAD2"
}

##############################
# Script Principal:
##############################
if [ "$GIT_DOWNLOAD" = "false" ]; then
    CopyFiles
    echo "Copia del cache completada."
    exit 0
fi

# Eliminar archivo server.cfg
verify_and_delete_file "$DIR_SIR/cfg/server.cfg"

# Eliminar archivos .dll en la carpeta addons
find "$DIR_SIR_ADDONS" -type f -name "*.dll" -delete

CopyFiles
log "Modificaciones del repositorio completados."