#!/bin/bash
set -euo pipefail

#####################################################
# Variables y validaciones de entorno
: "${DIR_SCRIPTING:?La variable DIR_SCRIPTING no está definida.}"
: "${DIR_ADDONS:?La variable DIR_ADDONS no está definida.}"

#####################################################
# Biblioteca de funciones
source "$DIR_SCRIPTING/git-gameserver/tools_gameserver.sh"

SCRIPT_NAME=$(basename "$0")
LOG_FILE="$DIR_TMP/${SCRIPT_NAME%.sh}.log"
DIR_MAPS="$DIR_TMP/maps"
URL_CENTER="https://l4d2center.com/maps/servers/index.json"
CACHE_INDEX="$DIR_TMP/cache_maps_l4d2center.json"

# Forzar la descarga de todos los mapas (false por defecto)
L4D2_MAPS_FORCE_DOWNLOAD=${L4D2_MAPS_FORCE_DOWNLOAD:-false}

# Si se especifica, solo se procesará el mapa cuyo nombre (sin extensión) coincida
L4D2_MAP=${L4D2_MAP:-}

# Variable para omitir verificación MD5 (false por defecto)
L4D2_MAPS_NO_MD5=${L4D2_MAPS_NO_MD5:-false}

#####################################################
# Crear directorios necesarios
mkdir -p "$DIR_MAPS"
mkdir -p "$DIR_ADDONS"

#####################################################
# Función: log_message
log_message() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" | tee -a "$LOG_FILE"
}

#####################################################
# Función: verify_vpk_md5
# Extrae un archivo comprimido y verifica el MD5 del primer archivo .vpk.
# Parámetros:
#   $1: Archivo comprimido (.7z o .zip)
#   $2: MD5 esperado para el .vpk extraído.
verify_vpk_md5() {
    local archive="$1"
    local expected_md5="$2"
    local temp_dir
    temp_dir=$(mktemp -d)
    
    if [[ "$archive" == *.7z ]]; then
        7z x "$archive" -o"$temp_dir" -bsp1
    elif [[ "$archive" == *.zip ]]; then
        unzip -qq -d "$temp_dir" "$archive"
    else
        rm -rf "$temp_dir"
        return 1
    fi

    local vpk_file
    vpk_file=$(find "$temp_dir" -maxdepth 1 -type f -name "*.vpk" | head -n 1)
    if [ -z "$vpk_file" ]; then
        log_message "Error: No se encontró ningún archivo .vpk en $(basename "$archive")."
        rm -rf "$temp_dir"
        return 1
    fi

    if [[ "$L4D2_MAPS_NO_MD5" == "false" ]]; then
        local actual_md5
        actual_md5=$(md5sum "$vpk_file" | awk '{print $1}')
        rm -rf "$temp_dir"
        [[ "$actual_md5" == "$expected_md5" ]]
    else
        rm -rf "$temp_dir"
        return 0
    fi
}

#####################################################
# Función: process_map
# Extrae el archivo comprimido, verifica (si aplica) y mueve el .vpk a DIR_ADDONS.
# Luego, elimina el archivo comprimido.
# Parámetros:
#   $1: Archivo comprimido
#   $2: MD5 esperado para el .vpk extraído.
process_map() {
    local archive="$1"
    local expected_md5="$2"
    local temp_dir
    temp_dir=$(mktemp -d)
    
    log_message "Extrayendo $(basename "$archive") en $temp_dir..."
    if [[ "$archive" == *.7z ]]; then
        7z x "$archive" -o"$temp_dir" -bsp1
    elif [[ "$archive" == *.zip ]]; then
        unzip -qq -d "$temp_dir" "$archive"
    else
        log_message "Error: Formato no soportado para $(basename "$archive")."
        rm -rf "$temp_dir"
        return 1
    fi

    local vpk_file
    vpk_file=$(find "$temp_dir" -maxdepth 1 -type f -name "*.vpk" | head -n 1)
    if [ -z "$vpk_file" ]; then
        log_message "Error: No se encontró ningún archivo .vpk en $(basename "$archive")."
        rm -rf "$temp_dir"
        return 1
    fi

    if [[ "$L4D2_MAPS_NO_MD5" == "false" ]]; then
        local actual_md5
        actual_md5=$(md5sum "$vpk_file" | awk '{print $1}')
        if [[ "$actual_md5" != "$expected_md5" ]]; then
            log_message "Error: MD5 de $(basename "$archive") fallida. Esperado: $expected_md5, obtenido: $actual_md5."
            rm -rf "$temp_dir"
            return 1
        else
            log_message "Verificación MD5 exitosa para $(basename "$archive")."
        fi
    else
        log_message "L4D2_MAPS_NO_MD5 activado: se omite verificación MD5 para $(basename "$archive")."
    fi

    log_message "Moviendo $(basename "$vpk_file") a $DIR_ADDONS..."
    mv "$vpk_file" "$DIR_ADDONS/"
    rm -rf "$temp_dir"
    rm -f "$archive"  # Eliminar el archivo comprimido tras procesarlo
    return 0
}

#####################################################
# Función: download_and_process_map
# Descarga el archivo comprimido, lo procesa y lo reintenta hasta 3 veces.
# Parámetros:
#   $1: URL de descarga
#   $2: Archivo destino para el comprimido
#   $3: MD5 esperado para el .vpk extraído.
download_and_process_map() {
    local url="$1"
    local file="$2"
    local md5_expected="$3"
    local attempts=3
    local attempt=1

    while [ $attempt -le $attempts ]; do
        log_message "Intento $attempt: Descargando $(basename "$file") desde $url..."
        curl -L -o "$file" -# "$url"
        if [[ -f "$file" ]]; then
            if process_map "$file" "$md5_expected"; then
                log_message "$(basename "$file") procesado correctamente."
                return 0
            else
                log_message "Error: Procesamiento de $(basename "$file") fallido (intentó $attempt de $attempts)."
                rm -f "$file"
            fi
        fi
        attempt=$((attempt + 1))
    done
    return 1
}

#####################################################
# Descargar el nuevo index.json a un archivo temporal
NEW_INDEX="$DIR_MAPS/index_new.json"
log_message "Descargando la lista de mapas desde $URL_CENTER..."
curl -L -o "$NEW_INDEX" -# "$URL_CENTER"

#####################################################
# Comparar el nuevo index con el cache previo
if [[ -f "$CACHE_INDEX" ]]; then
    if diff -q "$NEW_INDEX" "$CACHE_INDEX" > /dev/null && [[ "$L4D2_MAPS_FORCE_DOWNLOAD" != "true" ]]; then
        log_message "El index.json no ha cambiado y no se forzó la descarga. Se copiarán los mapas del cache."
        log_message "Proceso completado (sin cambios)."
        exit 0
    else
        log_message "Se detectaron cambios en el index.json o se forzó la descarga."
    fi
else
    log_message "No se encontró un cache previo. Se realizará una descarga completa."
fi

#####################################################
# Comparar cada mapa del nuevo index con el cache previo para determinar cuáles actualizar.
declare -A old_cache
if [[ -f "$CACHE_INDEX" ]]; then
    while IFS="=" read -r key value; do
        old_cache["$key"]="$value"
    done < <(jq -r 'to_entries[] | "\(.key)=\(.value)"' "$CACHE_INDEX")
fi

MAPS_TO_UPDATE=()
while IFS= read -r map_entry; do
    map_name=$(echo "$map_entry" | jq -r '.name')
    # Si se especificó L4D2_MAP, comparar el nombre sin extensión
    if [[ -n "$L4D2_MAP" ]]; then
        map_base="${map_name%.vpk}"
        if [[ "$map_base" != "$L4D2_MAP" ]]; then
            log_message "Mapa \"$map_name\" no coincide con L4D2_MAP ($L4D2_MAP), se omite."
            continue
        fi
    fi
    map_md5=$(echo "$map_entry" | jq -r '.md5')
    if [[ "$L4D2_MAPS_FORCE_DOWNLOAD" == "true" ]] || [[ "${old_cache[$map_name]:-}" != "$map_md5" ]]; then
        log_message "Mapa \"$map_name\" ha cambiado o se forzará la descarga (cache: \"${old_cache[$map_name]:-none}\", nuevo: \"$map_md5\")."
        MAPS_TO_UPDATE+=("$map_entry")
    else
        log_message "Mapa \"$map_name\" no ha cambiado."
    fi
done < <(jq -c '.[]' "$NEW_INDEX")

#####################################################
# Procesar únicamente los mapas que han cambiado o se requiera actualizar
if [ ${#MAPS_TO_UPDATE[@]} -eq 0 ]; then
    log_message "No se detectaron cambios en los mapas (o L4D2_MAP no se especificó). Se copiarán los archivos del cache."
else
    log_message "Se actualizarán ${#MAPS_TO_UPDATE[@]} mapa(s)."
    for map_entry in "${MAPS_TO_UPDATE[@]}"; do
        NAME=$(echo "$map_entry" | jq -r '.name')
        URL=$(echo "$map_entry" | jq -r '.download_link' | sed 's/ /%20/g')
        MD5_EXPECTED=$(echo "$map_entry" | jq -r '.md5')
        FILE_NAME="${NAME%.vpk}.7z"
        FILE_PATH="$DIR_MAPS/$FILE_NAME"
        
        if [[ -f "$FILE_PATH" ]]; then
            log_message "$FILE_NAME ya existe pero se actualizará (no pasó la verificación del cache)."
            rm -f "$FILE_PATH"
        fi
        
        if ! download_and_process_map "$URL" "$FILE_PATH" "$MD5_EXPECTED"; then
            log_message "Error definitivo: No se pudo actualizar $FILE_NAME tras varios intentos."
        fi
    done
fi

#####################################################
# Actualizar el cache con el nuevo index.
NEW_CACHE=$(jq 'reduce .[] as $map ({}; .[$map.name] = $map.md5)' "$NEW_INDEX")
echo "$NEW_CACHE" > "$CACHE_INDEX"
log_message "Cache actualizado: $CACHE_INDEX"

#####################################################
# Extraer y mover archivos .vpk desde los archivos comprimidos restantes
# Sólo se procesan los archivos que aún existan en DIR_MAPS (los actualizados se han eliminado)
log_message "Extrayendo archivos y moviendo .vpk a $DIR_ADDONS..."
find "$DIR_MAPS" -type f \( -iname "*.7z" -o -iname "*.zip" \) | while IFS= read -r file; do
    base=$(basename "$file")
    map_name="${base%.7z}.vpk"
    expected_md5=$(jq -r --arg name "$map_name" '.[$name]' "$CACHE_INDEX")
    process_map "$file" "$expected_md5" || true
done

log_message "Proceso completado."
