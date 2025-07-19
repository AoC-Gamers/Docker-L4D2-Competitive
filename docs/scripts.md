# Documentación de Scripts

## Visión General

El proyecto incluye varios scripts organizados en diferentes categorías para facilitar la gestión del servidor L4D2 competitivo.

## Scripts de Configuración Inicial (`docker-scripts/`)

### `dependencies_check.sh`
Verifica e instala las dependencias requeridas en sistemas Debian.

**Funcionalidades:**
- Verificación de paquetes del sistema
- Instalación automática de dependencias faltantes
- Validación de arquitectura i386

**Uso:**
```bash
./dependencies_check.sh
```

### `rep_branch.sh`
Actualiza el campo "branch" en el archivo `repos.json` según las variables de entorno.

**Funcionalidades:**
- Modifica dinámicamente las ramas de repositorios Git
- Permite usar diferentes ramas por entorno (desarrollo, producción, testing)
- Soporta variables de entorno con prefijo `BRANCH_`

**Convención de Variables:**
- Formato: `BRANCH_{FOLDER_UPPERCASE}`
- Si la variable es "default", no se modifica el repositorio

**Ejemplos:**
```bash
# Para repo con folder "sir" 
export BRANCH_SIR=development

# Para repo con folder "my_plugin"
export BRANCH_MY_PLUGIN=feature/new-update

# Para repo con folder "configs"
export BRANCH_CONFIGS=testing
```

**Proceso:**
1. Lee todos los repositorios de `repos.json`
2. Para cada repo, busca variable `BRANCH_{FOLDER_UPPERCASE}`
3. Si existe y no es "default", actualiza la rama en el JSON
4. Guarda el archivo modificado

**Casos de uso:**
```bash
# Desarrollo: usar ramas development
export BRANCH_SIR=development
export BRANCH_CONFIGS=dev

# Testing: usar ramas específicas de prueba
export BRANCH_SIR=testing
export BRANCH_MY_PLUGIN=feature/beta-test

# Producción: usar ramas estables (por defecto)
# No definir variables = usar ramas definidas en repos.json
```

### `ssh.sh`
Configura el servicio SSH del contenedor.

**Configuraciones aplicadas:**
- Deshabilita login como root
- Habilita autenticación por contraseña
- Configura puerto SSH personalizado
- Establece configuraciones de seguridad

**Variables de entorno:**
- `SSH_PORT`: Puerto SSH (default: 22)

### `symlink.sh`
Crea enlaces simbólicos para organizar scripts y configuraciones.

**Funcionalidades:**
- Enlaces para scripts de gestión
- Enlaces para scripts git-gameserver
- Organización de estructura de directorios

**Estructura creada:**
```
/data/server-scripts/ -> /app/server-scripts/*
/data/server-scripts/git-gameserver/ -> /app/server-scripts/git-gameserver/*
/data/menu_gameserver.sh -> /app/server-scripts/menu_gameserver.sh
```

## Scripts de Gestión del Servidor (`server-scripts/`)

### `menu_gameserver.sh`
Menú interactivo principal para gestión de servidores.

**Opciones del menú:**
1. Iniciar servidores
2. Detener servidores  
3. Reiniciar servidores
4. Actualizar (automático con parada)
5. Actualizar (manual sin parada)

**Uso interactivo:**
```bash
./menu_gameserver.sh
```

**Uso por comandos:**
```bash
# Iniciar servidores del 1 al 3
./menu_gameserver.sh start 1 3

# Detener todos
./menu_gameserver.sh stop

# Reiniciar servidor específico
./menu_gameserver.sh restart 2 2
```

**Funciones principales:**
- `calculate_total_servers()`: Calcula servidores disponibles
- `start_servers(start, end)`: Inicia rango de servidores
- `stop_servers(start, end)`: Detiene rango de servidores
- `restart_servers(start, end)`: Reinicia rango de servidores
- `update_servers(type)`: Actualiza servidores

### `clone_l4d2server.sh`
Clona servidores L4D2 usando LinuxGSM.

**Parámetros:**
- `AMOUNT_CLONES`: Número de clones a crear

**Uso:**
```bash
# Crear 3 servidores adicionales
./clone_l4d2server.sh 3

# Solo configurar primer servidor
./clone_l4d2server.sh 0
```

**Proceso de clonación:**
1. Validación de parámetros
2. Creación del servidor base (si no existe)
3. Creación de servidores clonados
4. Configuración de directorios SourceMod individuales
5. Copia de configuraciones base
6. Creación de enlaces simbólicos según `clone_exclude.json`

**Archivos de configuración:**
- `clone_l4d2server.json`: Configuración de clonación
- `clone_exclude.json`: Define qué archivos copiar vs. enlazar

### `install_gameserver.sh`
**El corazón del sistema**: Instala o actualiza el servidor competitivo, gestionando repositorios Git y ejecutando subscripts personalizados.

**Modos de operación:**
- `install` (0): Instalación limpia
- `update` (1): Actualización preservando configuraciones

**Uso:**
```bash
# Instalación limpia
./install_gameserver.sh install
./install_gameserver.sh 0

# Actualización
./install_gameserver.sh update  
./install_gameserver.sh 1
```

**Sistema de Repositorios Git:**
1. **Configuración via `repos.json`**: Define repositorios, carpetas locales y ramas
2. **Modificación dinámica**: `rep_branch.sh` permite cambiar ramas por entorno
3. **Caché inteligente**: Solo descarga si hay cambios remotos
4. **Subscripts personalizados**: Ejecuta post-procesamiento específico por repo

**Flujo de repositorios:**
```bash
# Para cada repositorio en repos.json:
1. Verificar cambios remotos vs caché local
2. Clonar/actualizar solo si hay cambios
3. Buscar subscript: git-gameserver/{folder}.{branch}.sh
4. Ejecutar subscript con parámetros: REPO_DIR INSTALL_TYPE GIT_DOWNLOAD
```

**Subscripts de Post-procesamiento:**
- **Ubicación**: `/data/server-scripts/git-gameserver/`
- **Convención**: `{folder}.{branch}.sh`
- **Parámetros recibidos**:
  1. `REPO_DIR`: Directorio del repositorio clonado
  2. `INSTALL_TYPE`: `install` o `update`
  3. `GIT_DOWNLOAD`: `true` si descargó, `false` si usó caché
- **Variables disponibles**: Todas las del archivo `.env`

**Ejemplos de subscripts:**
```bash
# sir.default.sh - Procesa L4D2-Competitive-Rework
#!/bin/bash
REPO_DIR="$1"
INSTALL_TYPE="$2" 
GIT_DOWNLOAD="$3"

if [[ "$GIT_DOWNLOAD" == "true" ]]; then
    # Aplicar configuraciones del repo
    cp -r "$REPO_DIR/addons/"* "$DIR_SOURCEMOD/"
fi

# my_plugin.main.sh - Plugin personalizado
if [[ "${DISCORD_WEBHOOK_URL:-}" ]]; then
    # Configurar webhook desde .env
    echo "webhook_url=$DISCORD_WEBHOOK_URL" > "$DIR_SOURCEMOD/configs/discord.cfg"
fi
```

**Proceso de instalación:**
1. Preparación de bibliotecas Steam 32-bit/64-bit
2. Limpieza de bibliotecas conflictivas
3. Sistema de backup (solo en modo update)
4. Procesamiento de repositorios Git
5. Ejecución de subscripts de post-procesamiento
6. Restauración de configuraciones (solo en modo update)

**Variables de entorno:**
- `GIT_FORCE_DOWNLOAD`: Forzar descarga de repositorios
- `REPOS_JSON`: Archivo de configuración de repositorios
- Variables del `.env`: Disponibles para todos los subscripts

**Archivo .env compartido:**
Este script carga el archivo `.env` ubicado en el mismo directorio, el cual:
1. Configura el workshop downloader
2. Proporciona variables personalizadas para subscripts de post-procesamiento

```bash
# Ejemplo de variables en .env para subscripts
GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxx
COMPETITIVE_MODE=true
DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/xxx/xxx
```

### `l4d2_fix_install.sh`
Realiza la instalación/actualización del servidor mediante steamcmd.

**Funcionalidades:**
- Instalación para plataformas Windows y Linux
- Creación de enlaces simbólicos
- Validación de archivos del servidor

**Uso:**
```bash
./l4d2_fix_install.sh
```

**Proceso:**
1. Actualización para plataforma Windows
2. Actualización para plataforma Linux  
3. Creación de enlace simbólico `/app/serverfiles`

### `workshop_downloader.sh`
Gestiona la descarga de artículos y colecciones del Steam Workshop.

**Características:**
- Procesamiento por lotes (configurable)
- Logging detallado con timestamps
- Expansión de variables de entorno
- Reintentos automáticos
- Configuración flexible via archivo .env

**Opciones de línea de comandos:**
```bash
./workshop_downloader.sh [OPCIONES]

Opciones:
  -e, --env-file FILE     Archivo .env a usar (default: .env)
  -o, --output-dir DIR    Directorio de salida
  -b, --batch-size SIZE   Tamaño del lote (default: 5)
  -d, --delay SECONDS     Delay entre lotes (default: 10)
  -l, --log-file FILE     Archivo de log personalizado
  -h, --help              Mostrar ayuda
```

**Archivo de configuración (.env):**
```bash
WORKSHOP_ITEMS=123456789,987654321
WORKSHOP_COLLECTIONS=3489804150,2222222222
OUTPUT_DIR=$DIR_LEFT4DEAD2/addons/workshop
BATCH_SIZE=5
BATCH_DELAY=10
```

### `workshop.py`
Script Python para interactuar con la API de Steam Workshop.

**Funcionalidades:**
- Descarga de artículos individuales
- Procesamiento de colecciones
- Manejo de reintentos
- Generación de archivo `addons.lst`

**Uso interno:**
```bash
python3 workshop.py [opciones] collection_id1 collection_id2...
```

### `maps_l4d2center.sh`
Automatiza la descarga y actualización de mapas desde L4D2Center.

**Variables de entorno:**
- `L4D2_MAPS_FORCE_DOWNLOAD`: Forzar descarga (default: false)
- `L4D2_MAP`: Descargar solo un mapa específico
- `L4D2_MAPS_SKIP_MD5`: Omitir verificación MD5

**Uso:**
```bash
# Actualización normal (solo mapas modificados)
./maps_l4d2center.sh

# Forzar descarga de todos los mapas
L4D2_MAPS_FORCE_DOWNLOAD=true ./maps_l4d2center.sh

# Descargar solo un mapa específico
L4D2_MAP=c1m1_hotel ./maps_l4d2center.sh
```

**Proceso:**
1. Descarga del índice de L4D2Center
2. Comparación de MD5 con caché local
3. Descarga de mapas modificados/nuevos
4. Verificación de integridad
5. Actualización de caché

### `tools_gameserver.sh`
Biblioteca de funciones comunes para otros scripts.

**Funciones principales:**

#### Logging y errores:
- `log(message)`: Log con timestamp
- `error_exit(message)`: Log de error y salida

#### Gestión de archivos:
- `verify_and_delete_dir(path)`: Verificar y eliminar directorio
- `verify_and_delete_file(path)`: Verificar y eliminar archivo

#### Control de usuarios:
- `check_user(username)`: Verificar usuario actual

**Uso:**
```bash
source "$DIR_SCRIPTING/tools_gameserver.sh"

log "Iniciando proceso..."
verify_and_delete_dir "/ruta/temporal"
check_user "linuxgsm"
```

## Scripts de Post-Procesamiento (`git-gameserver/`)

### `sir.default.sh`
Script específico para aplicar modificaciones al repositorio L4D2-Competitive-Rework.

**Parámetros:**
1. `REPO_DIR`: Directorio del repositorio
2. `INSTALL_TYPE`: Tipo de instalación (install/update)
3. `GIT_DOWNLOAD`: Si se descargó desde repositorio remoto

**Proceso:**
1. Configuración de variables de entorno
2. Aplicación de modificaciones específicas
3. Copia de archivos de configuración
4. Aplicación de parches o configuraciones personalizadas

### `example.default.sh`
Plantilla para crear scripts de post-procesamiento personalizados.

**Estructura básica:**
```bash
#!/bin/bash
set -euo pipefail

REPO_DIR="$1"
INSTALL_TYPE="${2:-install}"
GIT_DOWNLOAD="${3:-false}"

# Función para copiar archivos
CopyFiles() {
    # Implementar lógica de copia
}

# Lógica principal
if [ "$GIT_DOWNLOAD" = "true" ]; then
    CopyFiles
    echo "Instalación desde repositorio completada."
else
    CopyFiles
    echo "Copia desde caché completada."
fi
```

## Archivos de Configuración JSON

### `repos.json`
Define repositorios git a procesar durante la instalación.

```json
[
  {
    "repo_url": "https://github.com/SirPlease/L4D2-Competitive-Rework.git",
    "folder": "sir",
    "branch": "default"
  }
]
```

### `backup_gameserver.json`
Define archivos a respaldar durante actualizaciones.

```json
{
  "configs": ["databases.cfg", "admins_simple.ini"],
  "data": ["system2.cfg"],
  "plugins": ["custom_plugin.smx"]
}
```

### `clone_exclude.json`
Define qué archivos copiar vs. enlazar simbólicamente durante clonación.

```json
{
  "configs": ["databases.cfg", "core.cfg"],
  "data": ["system2.cfg"],
  "plugins": ["custom_plugin.smx"],
  "translations": ["es.txt"]
}
```

## Variables de Entorno Globales

### Directorios principales:
- `DIR_SCRIPTING`: `/data/server-scripts`
- `DIR_LEFT4DEAD2`: `/data/serverfiles/left4dead2`
- `DIR_SOURCEMOD`: `/data/serverfiles/left4dead2/addons/sourcemod`
- `DIR_CFG`: `/data/serverfiles/left4dead2/cfg`
- `DIR_ADDONS`: `/data/serverfiles/left4dead2/addons`

### Configuración de usuario:
- `USER`: Usuario del contenedor (linuxgsm)
- `GAMESERVER`: Nombre del servidor principal (l4d2server)

### Archivos de configuración:
- `REPOS_JSON`: Archivo de repositorios
- `CACHE_FILE`: Archivo de caché de git
- `LOG_FILE`: Archivo de logs principal

## Flujo de Ejecución Típico

1. **Inicio del contenedor**: `entrypoint.sh`
2. **Configuración SSH**: `ssh.sh`
3. **Verificación de dependencias**: `dependencies_check.sh`
4. **Creación de enlaces**: `symlink.sh`
5. **Cambio a usuario**: `entrypoint-user.sh`
6. **Instalación L4D2**: `l4d2_fix_install.sh`
7. **Instalación de gameserver**: `install_gameserver.sh`
8. **Configuración de servidores**: `clone_l4d2server.sh`
9. **Inicio de servidores**: `menu_gameserver.sh`
