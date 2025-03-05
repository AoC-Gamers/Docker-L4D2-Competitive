#!/bin/bash
set -euo pipefail

#####################################################
# Configuración básica
: "${DIR_SCRIPTING:?Error: La variable DIR_SCRIPTING no está definida.}"
: "${DIR_LEFT4DEAD2:?Error: La variable DIR_LEFT4DEAD2 no está definida.}"
: "${DIR_CFG:?Error: La variable DIR_CFG no está definida.}"
: "${REPOS_JSON:=$DIR_SCRIPTING/repos.json}"

#####################################################
# Biblioteca de funciones
source "$DIR_SCRIPTING/git-gameserver/tools_gameserver.sh"

#####################################################
# Variables
GIT_FORCE_DOWNLOAD="${GIT_FORCE_DOWNLOAD:-false}"
SUBSCRIPT_DIR="$DIR_SCRIPTING/git-gameserver"
LOG_FILE="$DIR_SCRIPTING/install_gameserver.log"
CACHE_FILE="$DIR_TMP/cache_gameserver.log"

#####################################################
# Verificar existencia de repos.json
if [[ ! -f "$REPOS_JSON" ]]; then
    echo "Error: El archivo repos.json no se encontró en $DIR_SCRIPTING."
    exit 1
fi

#####################################################
# Verificar si el script se ejecuta como el usuario TARGET_USER
check_user "linuxgsm"

#####################################################
# Cargar variables desde .env
if [[ -f "$DIR_SCRIPTING/.env" ]]; then
    # Cargar las variables ignorando líneas comentadas
    export $(grep -v '^#' "$DIR_SCRIPTING/.env" | xargs)
else
    echo "El archivo .env no se encontró en $DIR_SCRIPTING."
fi

#####################################################
# Definir tipo de instalación (install/update)
if [[ -n "${1:-}" ]]; then
    case "$1" in
        install|0) INSTALL_TYPE="install" ;;
        update|1)  INSTALL_TYPE="update"  ;;
        *) error_exit "Argumento inválido. Usa 'install' (o 0) para instalación limpia o 'update' (o 1) para actualización." ;;
    esac
else
    read -rp "¿Instalación limpia (0) o actualización (1)? " OPTION
    case "$OPTION" in
        0) INSTALL_TYPE="install" ;;
        1) INSTALL_TYPE="update" ;;
        *) error_exit "Opción inválida. Usa '0' para instalación limpia o '1' para actualización." ;;
    esac
fi

#####################################################
# Preparar librerías de 32 bits y eliminar duplicados
if [ -d "$HOME/.steam/sdk32" ]; then
    rm -rf "$HOME/.steam/sdk32"
fi
if [ -d "$HOME/.steam/sdk64" ]; then
    rm -rf "$HOME/.steam/sdk64"
fi

mkdir -p "$HOME/.steam/sdk32" "$HOME/.steam/sdk64"

cp -v "$HOME/.local/share/Steam/steamcmd/linux32/"* "$HOME/.steam/sdk32"
cp -v "$HOME/.local/share/Steam/steamcmd/linux64/steamclient.so" "$HOME/.steam/sdk64/steamclient.so"

if [[ -e "$LGSM_SERVERFILES/bin/libstdc++.so.6" ]]; then
    rm "$LGSM_SERVERFILES/bin/libstdc++.so.6" "$LGSM_SERVERFILES/bin/dedicated/libstdc++.so.6"
    log "Se eliminó libstdc++.so.6 por compatibilidad con extensiones."
else
    log "libstdc++.so.6 no se detectó localmente."
fi

if [[ -e "$LGSM_SERVERFILES/bin/libgcc_s.so.1" ]]; then
    rm "$LGSM_SERVERFILES/bin/libgcc_s.so.1" "$LGSM_SERVERFILES/bin/dedicated/libgcc_s.so.1"
    log "Se eliminó libgcc_s.so.1 por compatibilidad con extensiones."
else
    log "libgcc_s.so.1 no se detectó localmente."
fi

#####################################################
# Directorio temporal
mkdir -p "$DIR_TMP"
cd "$DIR_TMP" || error_exit "No se pudo acceder al directorio temporal $DIR_TMP."

# Crear archivo de cache si no existe
if [[ ! -f "$CACHE_FILE" ]]; then
    touch "$CACHE_FILE"
fi

#####################################################
# Funciones auxiliares para Git
get_latest_commit_hash() {
    local repo_dir="$1"
    git -C "$repo_dir" rev-parse HEAD || error_exit "No se pudo obtener el último hash en $repo_dir."
}

save_commit_hash() {
    local repo_name="$1"
    local commit_hash="$2"
    sed -i "/^${repo_name}:/d" "$CACHE_FILE"
    echo "$repo_name:$commit_hash" >> "$CACHE_FILE"
}

has_repo_changed() {
    local repo_name="$1"
    local new_hash="$2"
    if [[ -f "$CACHE_FILE" ]]; then
        local old_hash
        old_hash=$(grep "^${repo_name}:" "$CACHE_FILE" | cut -d':' -f2)
        if [[ "$old_hash" == "$new_hash" ]]; then
            return 1  # Sin cambios
        fi
    fi
    return 0  # Con cambios o no encontrado
}

#####################################################
# Limpieza de archivos en el servidor
limpiar_logs_instancias() {
    local index=1
    while true; do
        local DIR_NEW_SOURCEMOD="${DIR_SOURCEMOD}${index}"
        if [ -d "$DIR_NEW_SOURCEMOD" ]; then
            log "Limpiando logs en $DIR_NEW_SOURCEMOD..."
            if ls "$DIR_NEW_SOURCEMOD/logs/errors_"*.log &> /dev/null; then
                rm "$DIR_NEW_SOURCEMOD/logs/errors_"*.log
            fi
        else
            log "Directorio $DIR_NEW_SOURCEMOD no encontrado. Terminando limpieza de logs."
            break
        fi
        ((index++))
    done
}

#####################################################
# Procesar limpieza en caso de actualización
if [ "$INSTALL_TYPE" == "update" ]; then
    verify_and_delete_dir "$DIR_SOURCEMOD/data"
    verify_and_delete_dir "$DIR_SOURCEMOD/extensions"
    verify_and_delete_dir "$DIR_SOURCEMOD/gamedata"
    verify_and_delete_dir "$DIR_SOURCEMOD/configs"
    verify_and_delete_dir "$DIR_SOURCEMOD/plugins"
    verify_and_delete_dir "$DIR_SOURCEMOD/scripting"
    verify_and_delete_dir "$DIR_SOURCEMOD/translations"
    limpiar_logs_instancias
    mkdir -p "$DIR_SOURCEMOD/configs"
    verify_and_delete_dir "$DIR_CFG/cfgogl"
    verify_and_delete_dir "$DIR_CFG/sourcemod"
    verify_and_delete_dir "$DIR_CFG/stripper"
fi

#####################################################
# Instalación de repositorios
jq -c '.[]' "$REPOS_JSON" | while IFS= read -r repo_item; do
    # Extraer los valores del JSON
    repo_url=$(echo "$repo_item" | jq -r '.repo_url' | envsubst)
    folder=$(echo "$repo_item" | jq -r '.folder')
    branch=$(echo "$repo_item" | jq -r '.branch')

    GIT_DOWNLOAD=false

    # Si se fuerza la descarga, o si la carpeta no existe, se clona
    if [[ "${GIT_FORCE_DOWNLOAD:-false}" == "true" ]]; then
        GIT_DOWNLOAD=true
        rm -rf "$folder"
    elif [[ -d "$folder" ]]; then
        echo "Verificando cambios en $folder..."
        if [[ "$branch" == "default" ]]; then
            remote_hash=$(git ls-remote "$repo_url" HEAD | awk '{print $1}')
        else
            remote_hash=$(git ls-remote -h "$repo_url" "$branch" | awk '{print $1}')
        fi

        if has_repo_changed "$folder" "$remote_hash"; then
            GIT_DOWNLOAD=true
            echo "El repositorio $folder ha cambiado (se actualizará)."
            rm -rf "$folder"
        else
            echo "El repositorio $folder no ha cambiado. Usando cache."
            GIT_DOWNLOAD=false
        fi
    else
        GIT_DOWNLOAD=true
    fi

    # Clonar o actualizar el repositorio si es necesario
    if [[ "$GIT_DOWNLOAD" == "true" ]]; then
        echo "Clonando $repo_url en la carpeta $folder (rama: $branch)..."
        if [[ "$branch" == "default" ]]; then
            git clone "$repo_url" "$folder" || { echo "Fallo la clonación de $repo_url"; exit 1; }
        else
            git clone -b "$branch" "$repo_url" "$folder" || { echo "Fallo la clonación de $repo_url en la rama $branch"; exit 1; }
        fi
        latest_hash=$(get_latest_commit_hash "$folder")
        save_commit_hash "$folder" "$latest_hash"
    fi

    # Opcional: ejecutar un subscript de modificaciones para el repositorio
    subscript_file="$DIR_SCRIPTING/git-gameserver/${folder}.${branch}.sh"
    if [[ -f "$subscript_file" ]]; then
        echo "Ejecutando subscript $subscript_file para $folder..."
        bash "$subscript_file" "$folder" "$INSTALL_TYPE" "$GIT_DOWNLOAD"
    else
        echo "No se encontró subscript para $folder. Saltando..."
    fi

done

log "--------------------------------------"
log "Instalación de modo competitivo de "
log "L4D2 completa en modo: $INSTALL_TYPE"
log "--------------------------------------"
