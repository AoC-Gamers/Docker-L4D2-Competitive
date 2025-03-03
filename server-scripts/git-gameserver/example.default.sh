#!/bin/bash
# example.default.sh
# Subscript para aplicar modificaciones específicas a la rama 'default' de Example.

if [ -z "$1" ]; then
    echo "Uso: $0 <REPO_DIR> <INSTALL_TYPE> <GIT_DOWNLOAD>"
    echo "  REPO_DIR: Ubicación del repositorio."
    echo "  INSTALL_TYPE: ('install'|'update') Tipo de instalación. def: install"
    echo "  GIT_DOWNLOAD: (true|false) Se descargo de repositorio remoto. def: false"
    echo ""
    echo "Ejemplo:"
    echo "  bash example.default.sh /app/tmp/example update true"
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

##############################
# Funciones auxiliares:
##############################
CopyFiles() {
}

##############################
# Script Principal:
##############################
if [ "$GIT_DOWNLOAD" = "false" ]; then
    CopyFiles
    echo "Copia del cache completada."
    exit 0
fi

CopyFiles
log "Modificaciones del repositorio completados."