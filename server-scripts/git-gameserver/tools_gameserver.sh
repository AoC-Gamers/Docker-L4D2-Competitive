#!/bin/bash
# tools_gameserver.sh - Archivo de inclusión con funciones comunes para los scripts.
#
# Uso:
#   source $DIR_SCRIPTING/git-gameserver/tools_gameserver.sh
#
# Este archivo incluye funciones de log, manejo de errores, utilidades para
# la verificación y eliminación de archivos y directorios, y funciones para
# buscar y modificar archivos de configuración compartida.

DIR_APP="/app"
DIR_TMP="/app/tmp"

#######################################
# Función: log
# Registra un mensaje con timestamp.
# Parámetros:
#   $1: Mensaje a registrar.
#######################################
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

#######################################
# Función: error_exit
# Registra un mensaje de error y finaliza el script.
# Parámetros:
#   $1: Mensaje de error.
#######################################
error_exit() {
    log "ERROR: $1"
    exit 1
}

#######################################
# Función: verify_and_delete_dir
# Verifica si existe un directorio y lo elimina.
# Parámetros:
#   $1: Ruta del directorio.
#######################################
verify_and_delete_dir() {
    if [ -d "$1" ]; then
        rm -rf "$1"
        log "Directorio '$1' eliminado."
    else
        log "Directorio '$1' no existe."
    fi
}

#######################################
# Función: verify_and_delete_file
# Verifica si existe un archivo y lo elimina.
# Parámetros:
#   $1: Ruta del archivo.
#######################################
verify_and_delete_file() {
    if [ -f "$1" ]; then
        rm "$1"
        log "Archivo '$1' eliminado."
    else
        log "Archivo '$1' no existe."
    fi
}

#######################################
# Función: check_user
# Verifica si el script se está ejecutando como el usuario correcto.
# Si se ejecuta como root, cambia al usuario TARGET_USER.
#######################################
check_user() {
if [ "$(whoami)" != "$1" ]; then
    if [ "$(whoami)" = "root" ]; then
        log "El script se está ejecutando como root. Cambiando al usuario '$1'..."
        exec su - "$1" -c "$0"
    else
        error_exit "Debes ejecutar este script como usuario '$1' o como root."
    fi
fi
}