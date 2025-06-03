#!/bin/bash
set -euo pipefail

#####################################################
# Dependencias requeridas
if ! command -v jq &> /dev/null; then
    echo -e "\e[31m❌ Error:\e[0m jq no está instalado."
    exit 1
fi

#####################################################
# Librería de funciones
source "$DIR_SCRIPTING/tools_gameserver.sh"

#####################################################
# Validación de entorno
: "${DIR_SCRIPTING:?❌ DIR_SCRIPTING no está definido.}"
: "${DIR_APP:?❌ DIR_APP no está definido.}"
: "${GAMESERVER:?❌ GAMESERVER no está definido.}"

#####################################################
# Variables y constantes
CLONE_L4D2SERVER="$DIR_SCRIPTING/clone_l4d2server.json"

# Función para calcular el número total de servidores
calculate_total_servers() {
    local total_servers=0
    local clone_count=0
    
    # Verificar servidor base
    if [[ -x "$DIR_APP/$GAMESERVER" ]]; then
        total_servers=1
        echo -e "\e[36m[DEBUG]\e[0m Servidor base encontrado: $DIR_APP/$GAMESERVER" >&2
    else
        echo -e "\e[31m❌ Error:\e[0m El servidor base ($DIR_APP/$GAMESERVER) no existe o no tiene permisos de ejecución."
        exit 1
    fi

    # Contar servidores clonados
    local pattern="$DIR_APP/$GAMESERVER-"
    shopt -s nullglob
    for file in "$pattern"*; do
        if [[ -x "$file" ]]; then
            clone_count=$((clone_count + 1))
            echo -e "\e[36m[DEBUG]\e[0m Servidor clonado encontrado: $file" >&2
        fi
    done
    shopt -u nullglob

    total_servers=$(( total_servers + clone_count ))
    echo -e "\e[36m[DEBUG]\e[0m Total calculado: $total_servers servidores ($clone_count clones + 1 base)" >&2
    echo "$total_servers"
}

# Calcular número inicial de servidores
TOTAL_SERVERS=$(calculate_total_servers)

#####################################################
# Verificación del JSON
if [[ -f "$CLONE_L4D2SERVER" ]]; then
    if jq -e 'has("amount_clones")' "$CLONE_L4D2SERVER" &>/dev/null; then
        CLONED_SERVERS=$(jq '.amount_clones' "$CLONE_L4D2SERVER")
        # Calcular el número actual de servidores clonados
        CURRENT_CLONE_COUNT=$(( TOTAL_SERVERS - 1 ))
        
        if [[ $CLONED_SERVERS -ne $CURRENT_CLONE_COUNT ]]; then
            echo -e "\e[33m⚠️ Inconsistencia detectada.\e[0m Ejecutando script de clonación..."
            "$DIR_SCRIPTING/clone_l4d2server.sh" "$CLONED_SERVERS"
            
            # Recalcular el total de servidores después de la clonación
            echo -e "\e[32m✅ Recalculando número total de servidores...\e[0m"
            TOTAL_SERVERS=$(calculate_total_servers)
        fi
    else
        echo -e "\e[33m⚠️ Advertencia:\e[0m El JSON no contiene el campo 'amount_clones'."
    fi
fi

#####################################################
# Menú
menu() {
    echo "Gameservers Menu"
    echo "1 - Start"
    echo "2 - Stop"
    echo "3 - Restart"
    echo "4 - Automatic Update"
    echo "5 - Manual Update"
    echo "* - Exit"
}

# Funciones principales
start_servers() {
    local start_range=$1 end_range=$2
    (( end_range == 0 )) && end_range=1

    for (( i = start_range; i <= end_range; i++ )); do
        local executable="$DIR_APP/$GAMESERVER"
        [[ $i -ne 1 ]] && executable="$DIR_APP/$GAMESERVER-$i"

        if [[ -x "$executable" ]]; then
            "$executable" start || echo -e "\e[33m[WARN]\e[0m No se pudo iniciar $executable, continuando..."
        else
            echo -e "\e[31m[ERROR]\e[0m El archivo $executable no existe o no tiene permisos de ejecución."
        fi
    done
}

stop_servers() {
    local start_range=$1 end_range=$2
    (( end_range == 0 )) && end_range=1

    for (( i = start_range; i <= end_range; i++ )); do
        local executable="$DIR_APP/$GAMESERVER"
        [[ $i -ne 1 ]] && executable="$DIR_APP/$GAMESERVER-$i"

        if [[ -x "$executable" ]]; then
            "$executable" stop || echo -e "\e[33m[WARN]\e[0m No se pudo detener $executable, continuando..."
        else
            echo -e "\e[31m[ERROR]\e[0m El archivo $executable no existe o no tiene permisos de ejecución."
        fi
    done
    echo "✔️ Finalizado"
}

restart_servers() {
    local start_range=$1 end_range=$2
    (( end_range == 0 )) && end_range=1

    for (( i = start_range; i <= end_range; i++ )); do
        local executable="$DIR_APP/$GAMESERVER"
        [[ $i -ne 1 ]] && executable="$DIR_APP/$GAMESERVER-$i"

        if [[ -x "$executable" ]]; then
            "$executable" restart || echo -e "\e[33m[WARN]\e[0m No se pudo reiniciar $executable, continuando..."
        else
            echo -e "\e[31m[ERROR]\e[0m El archivo $executable no existe o no tiene permisos de ejecución."
        fi
    done
    echo "✔️ Finalizado"
}

update_servers() {
    local update_type=${1:-manual}
    if [[ $update_type == "automatic" ]]; then
        stop_servers 1 "$TOTAL_SERVERS"
    fi
    "$DIR_SCRIPTING/install_gameserver.sh" 1
    if [[ $update_type == "automatic" ]]; then
        start_servers 1 "$TOTAL_SERVERS"
    fi
}

#####################################################
# Interacción
if [[ $# -eq 0 ]]; then
    menu
    read -rp "Selección: " choice
    case $choice in
        1) start_servers 1 "$TOTAL_SERVERS" ;;
        2) stop_servers 1 "$TOTAL_SERVERS" ;;
        3) restart_servers 1 "$TOTAL_SERVERS" ;;
        4) update_servers automatic ;;
        5) update_servers manual ;;
        *) echo "Saliendo..." ;;
    esac
else
    command=$1
    start_range=${2:-1}
    end_range=${3:-$TOTAL_SERVERS}

    if (( start_range < 1 || end_range > TOTAL_SERVERS || start_range > end_range )); then
        echo -e "\e[31m❌ Rango inválido.\e[0m"
        exit 1
    fi

    case $command in
        st|start)     start_servers "$start_range" "$end_range" ;;
        s|stop)       stop_servers "$start_range" "$end_range" ;;
        r|restart)    restart_servers "$start_range" "$end_range" ;;
        aup|aupdate)  update_servers automatic ;;
        up|update)    update_servers manual ;;
        *) echo -e "\e[31m❌ Comando inválido.\e[0m"; exit 1 ;;
    esac
fi

echo -e "\n🔢 Total de servidores detectados: $TOTAL_SERVERS"
echo -e "📋 Servidor base: $GAMESERVER"
echo -e "📋 Servidores clonados: $(( TOTAL_SERVERS - 1 ))"