# Guía de Desarrollo

## Contribuir al Proyecto

### Requisitos de Desarrollo

- Docker y Docker Compose
- Git
- Editor de código (VS Code recomendado)
- Conocimiento básico de:
  - Bash scripting
  - Docker/Containerización
  - LinuxGSM
  - SourceMod/SourcePawn

### Configuración del Entorno de Desarrollo

#### 1. Fork y Clonación
```bash
# Fork del repositorio en GitHub
# Luego clonar tu fork
git clone https://github.com/tu-usuario/Docker-L4D2-Competitive.git
cd Docker-L4D2-Competitive

# Configurar repositorio upstream
git remote add upstream https://github.com/AoC-Gamers/Docker-L4D2-Competitive.git
```

#### 2. Configuración de Desarrollo
```bash
# Usar docker-compose de desarrollo
cp example.env .env

# Editar variables para desarrollo
nano .env
```

Variables recomendadas para desarrollo:
```bash
LGSM_PASSWORD=desarrollo123
SSH_PORT=2222
L4D2_NO_AUTOSTART=true  # Para control manual
LGSM_DEV=true          # Habilitar modo desarrollador
```

#### 3. Construcción Local
```bash
# Construir imagen local para testing
docker build -t l4d2-competitive-dev .

# Usar en docker-compose.dev.yml
docker-compose -f docker-compose.dev.yml up -d
```

### Estructura del Proyecto

```
├── Dockerfile                 # Imagen principal
├── docker-compose.yml        # Producción
├── docker-compose.dev.yml    # Desarrollo
├── entrypoint*.sh            # Scripts de entrada
├── docker-scripts/           # Scripts de configuración Docker
│   ├── dependencies_check.sh
│   ├── rep_branch.sh
│   ├── ssh.sh
│   └── symlink.sh
├── server-scripts/           # Scripts de gestión del servidor
│   ├── menu_gameserver.sh    # Menú principal
│   ├── install_gameserver.sh # Instalador
│   ├── clone_l4d2server.sh   # Clonación de servidores
│   ├── workshop_downloader.sh # Workshop de Steam
│   ├── maps_l4d2center.sh    # Mapas de L4D2Center
│   ├── tools_gameserver.sh   # Funciones comunes
│   └── git-gameserver/       # Scripts post-procesamiento
├── config-lgsm/             # Configuraciones LinuxGSM
└── docs/                    # Documentación
```

### Estándares de Código

#### Scripts Bash
1. **Shebang y configuración:**
```bash
#!/bin/bash
set -euo pipefail  # Strict mode
```

2. **Validación de variables:**
```bash
: "${VARIABLE_REQUERIDA:?Error: Variable no definida.}"
```

3. **Funciones documentadas:**
```bash
#######################################
# Descripción de la función
# Globals:
#   VARIABLE_GLOBAL
# Arguments:
#   $1: Primer parámetro
#   $2: Segundo parámetro
# Outputs:
#   Escribe resultado a stdout
# Returns:
#   0 si éxito, código de error si falla
#######################################
mi_funcion() {
    local param1="$1"
    local param2="$2"
    
    # Lógica de la función
}
```

4. **Manejo de errores:**
```bash
# Usar funciones de tools_gameserver.sh
source "$DIR_SCRIPTING/tools_gameserver.sh"

# Logging con timestamp
log "Mensaje informativo"

# Salir con error
error_exit "Mensaje de error detallado"
```

#### Convenciones de Variables

1. **Variables de entorno (MAYÚSCULAS):**
```bash
LGSM_PASSWORD=""
SSH_PORT=22
DIR_SCRIPTING="/data/server-scripts"
```

2. **Variables locales (minúsculas):**
```bash
local archivo_temporal="/tmp/mi_archivo"
local contador=0
```

3. **Variables constantes (MAYÚSCULAS con readonly):**
```bash
readonly SCRIPT_NAME=$(basename "$0")
readonly LOG_FILE="$DIR_TMP/${SCRIPT_NAME%.sh}.log"
```

### Desarrollo de Nuevos Scripts

#### 1. Plantilla Base
```bash
#!/bin/bash
set -euo pipefail

#####################################################
# Descripción del script
# Autor: Tu Nombre
# Fecha: $(date +%Y-%m-%d)
#####################################################

#####################################################
# Validación de variables de entorno
: "${DIR_SCRIPTING:?La variable DIR_SCRIPTING no está definida.}"

#####################################################
# Librería de funciones
source "$DIR_SCRIPTING/tools_gameserver.sh"

#####################################################
# Verificar usuario correcto
check_user "${USER}"

#####################################################
# Variables y constantes
readonly SCRIPT_NAME=$(basename "$0")
readonly LOG_FILE="$DIR_TMP/${SCRIPT_NAME%.sh}.log"

#####################################################
# Funciones del script

mi_funcion_principal() {
    log "Iniciando proceso..."
    
    # Lógica principal aquí
    
    log "Proceso completado exitosamente"
}

#####################################################
# Función de ayuda
show_help() {
    cat << EOF
Uso: $0 [OPCIONES]

Descripción del script.

OPCIONES:
    -h, --help     Mostrar esta ayuda
    -v, --verbose  Modo verboso

EJEMPLOS:
    $0
    $0 --verbose

EOF
}

#####################################################
# Procesamiento de argumentos
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -v|--verbose)
            set -x  # Habilitar modo debug
            shift
            ;;
        *)
            log "Opción desconocida: $1"
            show_help
            exit 1
            ;;
    esac
done

#####################################################
# Función principal
main() {
    log "=== Iniciando $SCRIPT_NAME ==="
    
    mi_funcion_principal
    
    log "=== $SCRIPT_NAME completado ==="
}

# Ejecutar función principal
main "$@"
```

#### 2. Scripts de Post-procesamiento Git

Crear scripts en `server-scripts/git-gameserver/` siguiendo la convención:
`{folder}.{branch}.sh`

```bash
#!/bin/bash
# mi_repo.main.sh
set -euo pipefail

if [ -z "$1" ]; then
    echo "Usage: $0 <REPO_DIR> <INSTALL_TYPE> <GIT_DOWNLOAD>"
    exit 1
fi

source "$DIR_SCRIPTING/tools_gameserver.sh"

REPO_DIR="$1"
INSTALL_TYPE="${2:-install}"
GIT_DOWNLOAD="${3:-false}"

#####################################################
# Funciones específicas del repositorio
aplicar_configuraciones() {
    local src_dir="$REPO_DIR"
    local dest_dir="$DIR_SOURCEMOD"
    
    # Copiar archivos específicos
    if [[ -d "$src_dir/plugins" ]]; then
        cp -r "$src_dir/plugins/"* "$dest_dir/plugins/"
        log "Plugins copiados desde $src_dir"
    fi
}

#####################################################
# Lógica principal
if [[ "$GIT_DOWNLOAD" == "true" ]]; then
    log "Aplicando configuraciones desde descarga reciente..."
    aplicar_configuraciones
else
    log "Usando versión en caché..."
    aplicar_configuraciones
fi

log "Post-procesamiento de mi_repo completado"
```

### Testing y Validación

#### 1. Testing Local
```bash
# Construir imagen de desarrollo
docker build -t l4d2-dev .

# Ejecutar con montaje de código local
docker run -it --rm \
  -v $(pwd)/server-scripts:/app/server-scripts \
  -v $(pwd)/docker-scripts:/app/docker-scripts \
  l4d2-dev bash

# Dentro del contenedor, probar scripts
./mi_nuevo_script.sh --test
```

#### 2. Validación de Scripts
```bash
# Verificar sintaxis
bash -n mi_script.sh

# Verificar con shellcheck (si está disponible)
shellcheck mi_script.sh

# Ejecutar en modo debug
bash -x mi_script.sh
```

#### 3. Testing de Configuraciones JSON
```bash
# Validar JSON
jq empty mi_config.json

# Probar queries específicos
jq '.[] | select(.folder == "mi_repo")' repos.json
```

### Integración Continua

#### 1. Pre-commit Hooks
Crear `.git/hooks/pre-commit`:
```bash
#!/bin/bash

# Verificar sintaxis de scripts bash
for file in $(git diff --cached --name-only --diff-filter=ACM | grep '\.sh$'); do
    if [[ -f "$file" ]]; then
        bash -n "$file" || {
            echo "Error de sintaxis en $file"
            exit 1
        }
    fi
done

# Verificar JSON válido
for file in $(git diff --cached --name-only --diff-filter=ACM | grep '\.json$'); do
    if [[ -f "$file" ]]; then
        jq empty "$file" || {
            echo "JSON inválido en $file"
            exit 1
        }
    fi
done

echo "Pre-commit checks passed"
```

#### 2. GitHub Actions (ejemplo)
`.github/workflows/test.yml`:
```yaml
name: Test Scripts

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      
      - name: Test Bash Scripts
        run: |
          for script in $(find . -name "*.sh"); do
            echo "Testing $script"
            bash -n "$script"
          done
      
      - name: Test JSON Files
        run: |
          sudo apt-get install -y jq
          for json in $(find . -name "*.json"); do
            echo "Testing $json"
            jq empty "$json"
          done
      
      - name: Build Docker Image
        run: docker build -t test-image .
```

### Documentación de Nuevas Características

#### 1. Actualizar README.md
- Añadir nuevas funcionalidades en la sección correspondiente
- Incluir ejemplos de uso
- Actualizar referencias y enlaces

#### 2. Crear documentación específica
- Añadir archivo en `docs/` si es una característica compleja
- Documentar APIs o interfaces nuevas
- Incluir ejemplos prácticos

#### 3. Actualizar archivos de configuración
- Modificar `example.env` si se añaden nuevas variables
- Actualizar archivos JSON de ejemplo
- Documentar nuevos archivos de configuración

### Submitting Changes

#### 1. Preparación del Pull Request
```bash
# Actualizar rama principal
git checkout main
git pull upstream main

# Crear rama para nueva característica
git checkout -b feature/mi-nueva-funcionalidad

# Realizar cambios y commits
git add .
git commit -m "feat: añadir nueva funcionalidad X"

# Push a tu fork
git push origin feature/mi-nueva-funcionalidad
```

#### 2. Convenciones de Commits
Usar formato [Conventional Commits](https://www.conventionalcommits.org/):

```
feat: añadir soporte para múltiples configuraciones
fix: corregir error en workshop_downloader.sh
docs: actualizar guía de configuración
refactor: mejorar estructura de clone_l4d2server.sh
test: añadir tests para install_gameserver.sh
```

#### 3. Descripción del Pull Request
Incluir:
- Descripción detallada de los cambios
- Motivación y contexto
- Cómo probar los cambios
- Screenshots si aplica
- Referencias a issues relacionados

### Debug y Profiling

#### 1. Debug de Scripts
```bash
# Habilitar modo debug
set -x

# Debug selectivo
if [[ "${DEBUG:-false}" == "true" ]]; then
    set -x
fi

# Logging detallado
log "DEBUG: Variable X = $X"
```

#### 2. Profiling de Rendimiento
```bash
# Medir tiempo de ejecución
start_time=$(date +%s)
# ... código a medir ...
end_time=$(date +%s)
log "Tiempo de ejecución: $((end_time - start_time)) segundos"

# Usar time para comandos específicos
time ./install_gameserver.sh
```

#### 3. Monitoring de Recursos
```bash
# Monitorear uso de memoria
watch -n 1 'docker stats comp_l4d2 --no-stream'

# Profiling de procesos
docker-compose exec comp_l4d2 htop

# Logs en tiempo real
docker-compose logs -f comp_l4d2
```

### Mejores Prácticas

1. **Siempre probar en entorno de desarrollo antes de producción**
2. **Mantener retrocompatibilidad cuando sea posible**
3. **Documentar cambios breaking en el changelog**
4. **Usar logging consistente en todos los scripts**
5. **Validar entradas de usuario antes de procesar**
6. **Manejar casos edge y errores graciosamente**
7. **Mantener scripts idempotentes cuando sea posible**
8. **Seguir principio de responsabilidad única en funciones**
9. **Usar variables de entorno para configuración**
10. **Implementar rollback cuando sea crítico**
