#!/bin/bash
set -euo pipefail

# Verificar que DIR_SCRIPTING esté definida
: "${DIR_SCRIPTING:?La variable DIR_SCRIPTING no está definida.}"

########################################
# Función: create_symlinks
# Crea enlaces simbólicos para todos los archivos en un directorio fuente,
# copiándolos al directorio destino, aplicando filtros de exclusión para 'find'.
#
# Parámetros:
#   $1: Directorio fuente
#   $2: Directorio destino
#   $3...: Opciones adicionales para 'find' (filtros de exclusión)
########################################
create_symlinks() {
    local src_dir="$1"
    local dest_dir="$2"
    shift 2
    local find_filters=("$@")
    
    mkdir -p "$dest_dir"
    
    find "$src_dir" -type f "${find_filters[@]}" | while IFS= read -r src; do
        local filename
        filename=$(basename "$src")
        local target="$dest_dir/$filename"
        if [ ! -L "$target" ]; then
            ln -s "$src" "$target"
            echo "Symlink creado: $target"
        fi
    done
}

########################################
# Enlace especial para menu_gameserver.sh
########################################
echo "Creando symlink para menu_gameserver.sh (ubicado en /data)"
if [ ! -L "/data/menu_gameserver.sh" ]; then
    ln -s "/app/server-scripts/menu_gameserver.sh" "/data/menu_gameserver.sh"
    echo "Symlink creado: /data/menu_gameserver.sh"
fi

########################################
# Enlaces para archivos en /app/server-scripts, excepto
# menu_gameserver.sh y la subcarpeta git-gameserver
########################################
echo "Creando symlinks para archivos en /app/server-scripts"
mkdir -p "$DIR_SCRIPTING"
create_symlinks "/app/server-scripts" "$DIR_SCRIPTING" ! -name "menu_gameserver.sh" ! -path "/app/server-scripts/git-gameserver/*"

########################################
# Enlaces para archivos en /app/server-scripts/git-gameserver
########################################
echo "Creando symlinks para archivos en /app/server-scripts/git-gameserver"
create_symlinks "/app/server-scripts/git-gameserver" "$DIR_SCRIPTING/git-gameserver"

echo "Proceso de creación de symlinks completado."
