#!/bin/bash
set -euo pipefail

#####################################################
# Verificar que las variables de entorno necesarias estén definidas
: "${DIR_SCRIPTING:?La variable DIR_SCRIPTING no está definida.}"
: "${DIR_APP:?La variable DIR_APP no está definida.}"

#####################################################
# Biblioteca de funciones
source "$DIR_SCRIPTING/git-gameserver/tools_gameserver.sh"

#####################################################
# Variables y constantes
CLONE_L4D2SERVER="$DIR_SCRIPTING/clone_l4d2server.json"
SERVER_COUNT=0

#####################################################
# Verificar si el archivo JSON existe y extraer la cantidad de servidores clonados,
# luego contar los archivos de servidor en DIR_APP y comparar ambas cantidades.
if [[ -f "$CLONE_L4D2SERVER" ]]; then
    CLONED_SERVERS=$(jq '.amount_clones' "$CLONE_L4D2SERVER")

    # Contar el número de archivos l4d2server-* en el directorio
    for file in "$DIR_APP"/l4d2server-*; do
        if [[ -f "$file" ]]; then
            ((SERVER_COUNT++))
        fi
    done

    # Si la cantidad en el JSON no coincide con el número de archivos, se ejecuta el script de clonación.
    if [[ $CLONED_SERVERS -ne $SERVER_COUNT ]]; then
        echo "Inconsistencia detectada. Ejecutando el script de clonación de servidores..."
        "$DIR_SCRIPTING/clone_l4d2server.sh" "$CLONED_SERVERS"
    fi
fi

#####################################################
# Función: menu
# Muestra el menú interactivo y lee la opción seleccionada.
menu() {
    echo "Gameservers Menu"
    echo "1 - Start"
    echo "2 - Stop"
    echo "3 - Restart"
    echo "4 - Automatic Update"
    echo "5 - Update"
    echo "* - Exit"
    read -rp "Selection: " choice
    echo "$choice"
}

#####################################################
# Función: start_servers
# Inicia los servidores en el rango especificado.
start_servers() {
    local start_range=$1
    local end_range=$2
    for (( i = start_range; i <= end_range; i++ )); do
        local executable
        if [[ $i -eq 1 ]]; then
            executable="$DIR_APP/l4d2server"
        else
            executable="$DIR_APP/l4d2server-$i"
        fi

        if [[ -x "$executable" ]]; then
            "$executable" start
        else
            echo "Executable file $executable not found or does not have execution permissions."
        fi
    done
}

#####################################################
# Función: stop_servers
# Detiene los servidores en el rango especificado.
stop_servers() {
    local start_range=$1
    local end_range=$2
    for (( i = start_range; i <= end_range; i++ )); do
        local executable
        if [[ $i -eq 1 ]]; then
            executable="$DIR_APP/l4d2server"
        else
            executable="$DIR_APP/l4d2server-$i"
        fi

        if [[ -x "$executable" ]]; then
            "$executable" stop
        else
            echo "Executable file $executable not found or does not have execution permissions."
        fi
    done
    echo "Done"
}

#####################################################
# Función: restart_servers
# Reinicia los servidores en el rango especificado.
restart_servers() {
    local start_range=$1
    local end_range=$2
    for (( i = start_range; i <= end_range; i++ )); do
        local executable
        if [[ $i -eq 1 ]]; then
            executable="$DIR_APP/l4d2server"
        else
            executable="$DIR_APP/l4d2server-$i"
        fi

        if [[ -x "$executable" ]]; then
            "$executable" restart
        else
            echo "Executable file $executable not found or does not have execution permissions."
        fi
    done
    echo "Done"
}

#####################################################
# Función: update_servers
# Actualiza los servidores. Si el tipo de actualización es "automatic",
# se detienen y se reinician los servidores.
update_servers() {
    local update_type=${1:-manual}
    if [[ $update_type == "automatic" ]]; then
        stop_servers 1 "$SERVER_COUNT"
    fi
    "$DIR_SCRIPTING/install_gameserver.sh" 1
    if [[ $update_type == "automatic" ]]; then
        start_servers 1 "$SERVER_COUNT"
    fi
}

#####################################################
# Procesamiento de argumentos de línea de comandos o menú interactivo.
if [[ $# -gt 0 ]]; then
    command=$1
    range=${2:-}

    if [[ -z "$range" ]]; then
        start_range=1
        end_range=$SERVER_COUNT
    else
        if [[ "$range" == *-* ]]; then
            start_range=$(echo "$range" | cut -d'-' -f1)
            end_range=$(echo "$range" | cut -d'-' -f2)
        else
            start_range="$range"
            end_range="$range"
        fi
    fi

    if [[ $start_range -lt 1 || $end_range -gt $SERVER_COUNT || $start_range -gt $end_range ]]; then
        echo "Invalid range."
        exit 1
    fi

    case $command in
        st|start)
            start_servers "$start_range" "$end_range"
            ;;
        s|stop)
            stop_servers "$start_range" "$end_range"
            ;;
        r|restart)
            restart_servers "$start_range" "$end_range"
            ;;
        aup|aupdate)
            update_servers automatic
            ;;
        up|update)
            update_servers manual
            ;;
        *)
            echo "Invalid command."
            exit 1
            ;;
    esac
else
    choice=$(menu)
    case $choice in
        1)
            start_servers 1 "$SERVER_COUNT"
            ;;
        2)
            stop_servers 1 "$SERVER_COUNT"
            ;;
        3)
            restart_servers 1 "$SERVER_COUNT"
            ;;
        4)
            update_servers automatic
            ;;
        5)
            update_servers manual
            ;;
        *)
            echo "Done"
            ;;
    esac
fi
