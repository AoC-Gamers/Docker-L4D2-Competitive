#!/bin/bash
set -euo pipefail

#####################################################
# Verificar que las variables de entorno necesarias estén definidas
: "${DIR_SCRIPTING:?La variable DIR_SCRIPTING no está definida.}"
: "${DIR_SOURCEMOD:?La variable DIR_SOURCEMOD no está definida.}"
: "${DIR_CFG:?La variable DIR_CFG no está definida.}"

#####################################################
# Biblioteca de funciones
source "$DIR_SCRIPTING/git-gameserver/tools_gameserver.sh"

#####################################################
# Verificar si el script se ejecuta como el usuario TARGET_USER
check_user "linuxgsm"

#####################################################
# Variables y constantes
LGSM_L4D2SERVER="./linuxgsm.sh l4d2server"
L4D2_DEFAULT_SERVERCFG="server.cfg"
CLONE_L4D2SERVER="$DIR_SCRIPTING/clone_l4d2server.json"

# Archivo JSON con la lista de rutas que se deben copiar (relativas a DIR_SOURCEMOD)
CLONE_EXCLUDE_JSON="$DIR_SCRIPTING/clone_exclude.json"

#####################################################
# Función para crear enlaces simbólicos o copiar según el JSON
create_sourcemod_links() {
    local dest_dir="$1"
    # Lista de carpetas de primer nivel a procesar
    local folders=("bin" "configs" "data" "extensions" "gamedata" "plugins" "translations")
    
    for folder in "${folders[@]}"; do
        local source_folder="${DIR_SOURCEMOD}/${folder}"
        local dest_folder="${dest_dir}/${folder}"
        # Si el directorio origen no existe, saltar
        [ -d "$source_folder" ] || continue

        # Si el archivo JSON existe, cargar la lista de elementos a copiar para esta carpeta,
        # de lo contrario, se usa un array vacío.
        local copy_items=()
        if [ -f "$CLONE_EXCLUDE_JSON" ]; then
            mapfile -t copy_items < <(jq -r --arg key "$folder" '.[$key][]' "$CLONE_EXCLUDE_JSON")
        fi

        # Verificar que los elementos listados para copiar existan en el directorio origen
        for exclude in "${copy_items[@]}"; do
            if [ ! -e "${source_folder}/${exclude}" ]; then
                echo "Advertencia: El elemento a copiar '$folder/$exclude' no existe en ${source_folder}"
            fi
        done

        if [ ${#copy_items[@]} -eq 0 ]; then
            # Si no hay elementos para copiar, se crea un symlink del directorio completo
            ln -s "$source_folder" "$dest_folder" || error_exit "Error al crear symlink para el folder $folder"
            echo "Symlink creado para la carpeta completa: $folder"
        else
            # Crear el directorio destino
            mkdir -p "$dest_folder"
            # Procesar cada elemento dentro del directorio origen
            for item in "$source_folder"/*; do
                [ -e "$item" ] || continue
                local base_item
                base_item=$(basename "$item")
                local target="${dest_folder}/${base_item}"
                # Si el nombre del elemento coincide exactamente con uno de los listados se copia
                if printf "%s\n" "${copy_items[@]}" | grep -qx "$base_item"; then
                    cp -r "$item" "$target" || error_exit "Error al copiar $folder/$base_item a $target"
                    echo "Copiado: $folder/$base_item"
                else
                    ln -s "$item" "$target" || error_exit "Error al crear symlink para $folder/$base_item en $target"
                    echo "Symlink creado: $folder/$base_item"
                fi
            done
        fi
    done
}

#####################################################
# Procesar parámetros y solicitar la cantidad de clones si no se proporciona
if [ $# -eq 1 ]; then
    AMOUNT_CLONES="$1"
    if ! [[ "$AMOUNT_CLONES" =~ ^[2-9][0-9]*$ ]]; then
        echo "Debe ser un número natural superior a 1."
        exit 1
    fi
fi

if [ -z "${AMOUNT_CLONES:-}" ]; then
    read -rp "¿Cuántos clones de gameserver deseas crear? " AMOUNT_CLONES
fi

# Validar que AMOUNT_CLONES sea numérico
if ! [[ "$AMOUNT_CLONES" =~ ^[0-9]+$ ]]; then
    error_exit "El valor proporcionado no es un número válido."
fi

#####################################################
# Cambiar al directorio de instalación del servidor
cd "$DIR_APP" || error_exit "No se pudo acceder al directorio $DIR_APP"

#####################################################
# Verificar y crear el servidor principal si no existe
if [ ! -f "$DIR_APP/l4d2server" ]; then
    echo "El archivo $DIR_APP/l4d2server no existe. Creando el primer servidor."
    $LGSM_L4D2SERVER
    ./l4d2server details > /dev/null
fi

#####################################################
# Crear el directorio sourcemod1 si no existe
if [ ! -d "${DIR_SOURCEMOD}1" ]; then
    echo "Creando el subdirectorio sourcemod1 para el primer servidor..."
    mkdir "${DIR_SOURCEMOD}1" || error_exit "Error al crear el subdirectorio sourcemod1"
    create_sourcemod_links "${DIR_SOURCEMOD}1"
fi

#####################################################
# Bucle para crear clones de servidores
for (( i=2; i<=AMOUNT_CLONES+1; i++ )); do
    SERVER_NAME="l4d2server-$i"
    DIR_NEW_SOURCEMOD="${DIR_SOURCEMOD}${i}"
    
    if [ -f "$DIR_APP/$SERVER_NAME" ]; then
        echo "El servidor $SERVER_NAME ya existe. Saltando..."
    else
        echo "Creando el servidor $SERVER_NAME..."
        $LGSM_L4D2SERVER
        ./"$SERVER_NAME" details > /dev/null
    fi

    # Copiar configuración si no existe la copia específica para el servidor
    if [ ! -f "$DIR_CFG/$L4D2_DEFAULT_SERVERCFG" ]; then
        echo "El archivo de configuración predeterminado no existe: $DIR_CFG/$L4D2_DEFAULT_SERVERCFG"
    elif [ ! -f "$DIR_CFG/${SERVER_NAME}.cfg" ]; then
        echo "Copiando configuración de servidor para $SERVER_NAME..."
        cp "$DIR_CFG/$L4D2_DEFAULT_SERVERCFG" "$DIR_CFG/${SERVER_NAME}.cfg"
    fi

    # Crear el directorio SourceMod específico del servidor si no existe
    if [ -d "$DIR_NEW_SOURCEMOD" ]; then
        echo "El directorio $DIR_NEW_SOURCEMOD ya existe..."
        continue
    fi
    
    echo "Creando el directorio: $DIR_NEW_SOURCEMOD"
    mkdir "$DIR_NEW_SOURCEMOD" || error_exit "Error al crear el directorio $DIR_NEW_SOURCEMOD"
    create_sourcemod_links "$DIR_NEW_SOURCEMOD"
done

echo "Proceso de clonación completado."

#####################################################
# Guardar la última ejecución en un archivo JSON
echo "{\"last_execution\": \"$(date)\", \"amount_clones\": $AMOUNT_CLONES}" > "$CLONE_L4D2SERVER"
echo "Registro de la última ejecución guardado en $CLONE_L4D2SERVER."
