#!/bin/bash

# Script para ejecutar workshop.py con procesamiento por lotes
# Autor: GitHub Copilot
# Fecha: $(date)

# Configuración por defecto
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSHOP_SCRIPT="$SCRIPT_DIR/workshop.py"
ENV_FILE="$SCRIPT_DIR/.env"
LOG_FILE="$SCRIPT_DIR/workshop_$(date +%Y%m%d_%H%M%S).log"
BATCH_SIZE=5
BATCH_DELAY=10
OUTPUT_DIR=""

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Función para mostrar ayuda
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Opciones:"
    echo "  -e, --env-file FILE     Archivo .env a usar (default: .env)"
    echo "  -o, --output-dir DIR    Directorio de salida"
    echo "  -b, --batch-size SIZE   Tamaño del lote (default: 5)"
    echo "  -d, --delay SECONDS     Delay entre lotes en segundos (default: 10)"
    echo "  -l, --log-file FILE     Archivo de log personalizado"
    echo "  -h, --help              Mostrar esta ayuda"
    echo ""
    echo "El archivo .env debe contener:"
    echo "  WORKSHOP_ITEMS=123456,789012,345678     # IDs de artículos separados por comas"
    echo "  WORKSHOP_COLLECTIONS=111111,222222      # IDs de colecciones separados por comas"
    echo "  OUTPUT_DIR=/path/to/output               # Directorio de salida (opcional)"
    echo "  BATCH_SIZE=5                             # Tamaño del lote (opcional)"
    echo "  BATCH_DELAY=10                           # Delay entre lotes (opcional)"
}

# Función para logging
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "INFO")
            echo -e "${GREEN}[INFO]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "DEBUG")
            echo -e "${BLUE}[DEBUG]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        *)
            echo "[$timestamp] $level $message" >> "$LOG_FILE"
            ;;
    esac
}

# Función para validar dependencias
check_dependencies() {
    log "INFO" "Verificando dependencias..."
    
    if [[ ! -f "$WORKSHOP_SCRIPT" ]]; then
        log "ERROR" "workshop.py no encontrado en: $WORKSHOP_SCRIPT"
        return 1
    fi
    
    if ! command -v python3 &> /dev/null; then
        log "ERROR" "python3 no está instalado o no está en PATH"
        return 1
    fi
    
    log "INFO" "Todas las dependencias están disponibles"
    return 0
}

# Función para cargar archivo .env
load_env() {
    if [[ ! -f "$ENV_FILE" ]]; then
        log "ERROR" "Archivo .env no encontrado: $ENV_FILE"
        log "INFO" "Crea un archivo .env basado en .env.example"
        return 1
    fi
    
    log "INFO" "Cargando configuración desde: $ENV_FILE"
    
    # Cargar variables del archivo .env
    while IFS= read -r line; do
        # Ignorar comentarios y líneas vacías
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$line" ]] && continue
        
        # Exportar variable
        if [[ "$line" =~ ^[[:space:]]*([^=]+)=(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
            # Remover comillas si existen
            value="${value%\"}"
            value="${value#\"}"
            # Expandir variables de entorno en el valor
            value=$(eval echo "$value")
            export "$key"="$value"
            log "DEBUG" "Cargada variable: $key=$value"
        fi
    done < "$ENV_FILE"
    
    # Usar variables del .env si están definidas y expandir variables
    if [[ -n "$OUTPUT_DIR" ]]; then
        OUTPUT_DIR=$(eval echo "$OUTPUT_DIR")
        log "DEBUG" "OUTPUT_DIR expandido a: $OUTPUT_DIR"
    fi
    if [[ -n "$BATCH_SIZE" ]]; then
        BATCH_SIZE=$(eval echo "$BATCH_SIZE")
    fi
    if [[ -n "$BATCH_DELAY" ]]; then
        BATCH_DELAY=$(eval echo "$BATCH_DELAY")
    fi
    
    return 0
}

# Función para dividir string en array
split_string() {
    local input="$1"
    local delimiter="$2"
    echo "$input" | tr "$delimiter" '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^$'
}

# Función para procesar items en lotes
process_items_in_batches() {
    local items_string="$1"
    local item_type="$2"  # "items" o "collections"
    
    if [[ -z "$items_string" ]]; then
        log "WARN" "No se encontraron $item_type para procesar"
        return 0
    fi
    
    log "INFO" "Procesando $item_type: $items_string"
    
    # Convertir string a array
    local items_array=()
    while IFS= read -r item; do
        [[ -n "$item" ]] && items_array+=("$item")
    done < <(split_string "$items_string" ",")
    
    local total_items=${#items_array[@]}
    log "INFO" "Total de $item_type a procesar: $total_items"
    
    # Procesar en lotes
    local processed=0
    local batch_num=1
    
    while [[ $processed -lt $total_items ]]; do
        local batch_items=()
        local batch_end=$((processed + BATCH_SIZE))
        [[ $batch_end -gt $total_items ]] && batch_end=$total_items
        
        log "INFO" "Procesando lote $batch_num ($((processed + 1))-$batch_end de $total_items)"
        
        # Crear lote actual
        for ((i=processed; i<batch_end; i++)); do
            batch_items+=("${items_array[i]}")
        done
        
        # Ejecutar workshop.py con el lote actual
        local cmd_args=()
        if [[ -n "$OUTPUT_DIR" ]]; then
            # Verificar que el directorio de salida exista
            if [[ ! -d "$OUTPUT_DIR" ]]; then
                log "WARN" "El directorio de salida no existe: $OUTPUT_DIR"
                log "INFO" "Creando directorio: $OUTPUT_DIR"
                if ! mkdir -p "$OUTPUT_DIR"; then
                    log "ERROR" "No se pudo crear el directorio: $OUTPUT_DIR"
                    return 1
                fi
            fi
            cmd_args+=("-o" "$OUTPUT_DIR")
        fi
        cmd_args+=("${batch_items[@]}")
        
        log "INFO" "Ejecutando: python3 $WORKSHOP_SCRIPT ${cmd_args[*]}"
        
        if python3 "$WORKSHOP_SCRIPT" "${cmd_args[@]}" 2>&1 | tee -a "$LOG_FILE"; then
            log "INFO" "Lote $batch_num completado exitosamente"
        else
            log "ERROR" "Error en lote $batch_num"
            return 1
        fi
        
        processed=$batch_end
        batch_num=$((batch_num + 1))
        
        # Esperar entre lotes (excepto en el último)
        if [[ $processed -lt $total_items ]]; then
            log "INFO" "Esperando $BATCH_DELAY segundos antes del siguiente lote..."
            sleep "$BATCH_DELAY"
        fi
    done
    
    log "INFO" "Procesamiento de $item_type completado"
    return 0
}

# Función principal
main() {
    log "INFO" "=== Iniciando Workshop Downloader ==="
    log "INFO" "Archivo de log: $LOG_FILE"
    
    # Verificar dependencias
    if ! check_dependencies; then
        log "ERROR" "Falló la verificación de dependencias"
        exit 1
    fi
    
    # Cargar configuración
    if ! load_env; then
        log "ERROR" "Falló la carga de configuración"
        exit 1
    fi
    
    log "INFO" "Configuración:"
    log "INFO" "  - Tamaño de lote: $BATCH_SIZE"
    log "INFO" "  - Delay entre lotes: $BATCH_DELAY segundos"
    log "INFO" "  - Directorio de salida: ${OUTPUT_DIR:-"directorio actual"}"
    
    local success=true
    
    # Procesar artículos individuales
    if [[ -n "$WORKSHOP_ITEMS" ]]; then
        log "INFO" "--- Procesando artículos individuales ---"
        if ! process_items_in_batches "$WORKSHOP_ITEMS" "artículos"; then
            success=false
        fi
    fi
    
    # Procesar colecciones
    if [[ -n "$WORKSHOP_COLLECTIONS" ]]; then
        log "INFO" "--- Procesando colecciones ---"
        if ! process_items_in_batches "$WORKSHOP_COLLECTIONS" "colecciones"; then
            success=false
        fi
    fi
    
    # Verificar si no se especificaron items
    if [[ -z "$WORKSHOP_ITEMS" && -z "$WORKSHOP_COLLECTIONS" ]]; then
        log "WARN" "No se especificaron WORKSHOP_ITEMS ni WORKSHOP_COLLECTIONS en el archivo .env"
        log "INFO" "Revisa el archivo .env.example para ver el formato correcto"
        exit 1
    fi
    
    if $success; then
        log "INFO" "=== Proceso completado exitosamente ==="
        exit 0
    else
        log "ERROR" "=== Proceso completado con errores ==="
        exit 1
    fi
}

# Parsear argumentos de línea de comandos
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--env-file)
            ENV_FILE="$2"
            shift 2
            ;;
        -o|--output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -b|--batch-size)
            BATCH_SIZE="$2"
            shift 2
            ;;
        -d|--delay)
            BATCH_DELAY="$2"
            shift 2
            ;;
        -l|--log-file)
            LOG_FILE="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Opción desconocida: $1"
            show_help
            exit 1
            ;;
    esac
done

# Ejecutar función principal
main
