# API y Referencia de Funciones

## 📑 Tabla de Contenidos

1. [Funciones de `tools_gameserver.sh`](#funciones-de-tools_gameserversh)
2. [API de Variables de Rama Dinámicas](#api-de-variables-de-rama-dinámicas)
3. [API del Workshop Downloader](#api-del-workshop-downloader)
4. [API del Maps Downloader](#api-del-maps-downloader)
5. [API del Menu Gameserver](#api-del-menu-gameserver)

---

## Funciones de `tools_gameserver.sh`

### Logging y Gestión de Errores

#### `log(message)`
Registra un mensaje con timestamp.

**Parámetros:**
- `message`: Mensaje a registrar

**Ejemplo:**
```bash
log "Iniciando proceso de instalación"
# Output: [2024-12-19 10:30:45] Iniciando proceso de instalación
```

#### `error_exit(message)`
Registra un error y termina el script con código de salida 1.

**Parámetros:**
- `message`: Mensaje de error

**Ejemplo:**
```bash
error_exit "No se pudo acceder al directorio $DIR_APP"
# Output: [2024-12-19 10:30:45] ERROR: No se pudo acceder al directorio /app
# Script termina con exit 1
```

### Gestión de Archivos y Directorios

#### `verify_and_delete_dir(path)`
Verifica si un directorio existe y lo elimina.

**Parámetros:**
- `path`: Ruta del directorio

**Retorna:**
- `0`: Éxito (directorio eliminado o no existía)

**Ejemplo:**
```bash
verify_and_delete_dir "/tmp/directorio_temporal"
```

#### `verify_and_delete_file(path)`
Verifica si un archivo existe y lo elimina.

**Parámetros:**
- `path`: Ruta del archivo

**Retorna:**
- `0`: Éxito (archivo eliminado o no existía)

**Ejemplo:**
```bash
verify_and_delete_file "/tmp/archivo_temporal.txt"
```

### Control de Usuario

#### `check_user(username)`
Verifica si el script se ejecuta como el usuario especificado.

**Parámetros:**
- `username`: Nombre del usuario requerido

**Comportamiento:**
- Si se ejecuta como root, cambia al usuario especificado
- Si se ejecuta como usuario incorrecto, termina con error

**Ejemplo:**
```bash
check_user "linuxgsm"
```

## Variables de Entorno Globales

### Directorios del Sistema

| Variable | Valor por Defecto | Descripción |
|----------|-------------------|-------------|
| `DIR_APP` | `/app` | Directorio base de la aplicación |
| `DIR_TMP` | `/app/tmp` | Directorio temporal |
| `DIR_SCRIPTING` | `/data/server-scripts` | Directorio de scripts |
| `DIR_LEFT4DEAD2` | `/data/serverfiles/left4dead2` | Directorio del juego |
| `DIR_SOURCEMOD` | `/data/serverfiles/left4dead2/addons/sourcemod` | Directorio SourceMod |
| `DIR_CFG` | `/data/serverfiles/left4dead2/cfg` | Directorio de configuraciones |
| `DIR_ADDONS` | `/data/serverfiles/left4dead2/addons` | Directorio de addons |

### Configuración de LinuxGSM

| Variable | Valor por Defecto | Descripción |
|----------|-------------------|-------------|
| `LGSM_SERVERFILES` | `/data/serverfiles` | Archivos del servidor |
| `LGSM_CONFIG` | `/data/lgsm-config` | Configuraciones LinuxGSM |
| `LGSM_LOGDIR` | `/data/log` | Directorio de logs |
| `LGSM_DATADIR` | `/data/lgsm` | Datos de LinuxGSM |
| `GAMESERVER` | `l4d2server` | Nombre del servidor |

### Control de Comportamiento

| Variable | Valor por Defecto | Descripción |
|----------|-------------------|-------------|
| `L4D2_NO_INSTALL` | `false` | Evitar instalación automática |
| `L4D2_NO_AUTOSTART` | `false` | Evitar inicio automático |
| `L4D2_FRESH_INSTALL` | `false` | Instalación limpia |
| `GIT_FORCE_DOWNLOAD` | `false` | Forzar descarga de repos |

### Variables de Rama Dinámica

| Variable | Formato | Descripción |
|----------|---------|-------------|
| `BRANCH_*` | `BRANCH_{FOLDER_UPPERCASE}` | Modifica rama de repositorio específico |

**Ejemplos con repositorio actual:**
```bash
BRANCH_SIR=development        # Para repo folder "sir" (existente)

# Ejemplos hipotéticos para futuros repositorios:
# BRANCH_CONFIGS=testing      # Si agregar repo con folder "configs"  
# BRANCH_PLUGINS=feature/beta # Si agregar repo con folder "plugins"
```

**Proceso:**
1. `rep_branch.sh` lee variables `BRANCH_*`
2. Modifica `repos.json` dinámicamente
3. `install_gameserver.sh` usa nuevas ramas
4. Ejecuta subscripts correspondientes

## API del Workshop Downloader

### Configuración via Archivo .env

```bash
# Artículos individuales (separados por comas)
WORKSHOP_ITEMS=123456789,987654321

# Colecciones (separadas por comas)  
WORKSHOP_COLLECTIONS=3489804150,2222222222

# Directorio de salida (soporta variables de entorno)
OUTPUT_DIR=$DIR_LEFT4DEAD2/addons/workshop

# Configuración de procesamiento
BATCH_SIZE=5        # Artículos por lote
BATCH_DELAY=10      # Segundos entre lotes
```

### Opciones de Línea de Comandos

| Opción | Descripción | Valor por Defecto |
|--------|-------------|-------------------|
| `-e, --env-file FILE` | Archivo .env a usar | `.env` |
| `-o, --output-dir DIR` | Directorio de salida | Del archivo .env |
| `-b, --batch-size SIZE` | Tamaño del lote | `5` |
| `-d, --delay SECONDS` | Delay entre lotes | `10` |
| `-l, --log-file FILE` | Archivo de log | Auto-generado |
| `-h, --help` | Mostrar ayuda | - |

### Códigos de Salida

| Código | Descripción |
|--------|-------------|
| `0` | Éxito completo |
| `1` | Error en configuración o dependencias |
| `2` | Error durante procesamiento |

## API del Maps Downloader

### Variables de Entorno

| Variable | Tipo | Descripción |
|----------|------|-------------|
| `L4D2_MAPS_FORCE_DOWNLOAD` | `boolean` | Forzar descarga de todos los mapas |
| `L4D2_MAP` | `string` | Descargar solo un mapa específico |
| `L4D2_MAPS_SKIP_MD5` | `boolean` | Omitir verificación MD5 |

### Archivos Generados

| Archivo | Ubicación | Descripción |
|---------|-----------|-------------|
| `cache_maps_l4d2center.json` | `/data/tmp/` | Caché de mapas descargados |
| `maps_l4d2center.log` | `/data/tmp/` | Log de actividad |
| `index.json` | `/data/tmp/maps/` | Índice temporal |

## API del Menu Gameserver

### Comandos Disponibles

#### Modo Interactivo
```bash
./menu_gameserver.sh
```

Opciones del menú:
1. Iniciar servidores
2. Detener servidores
3. Reiniciar servidores
4. Actualizar (automático)
5. Actualizar (manual)

#### Modo Comando

```bash
./menu_gameserver.sh <comando> [inicio] [fin]
```

| Comando | Descripción | Parámetros |
|---------|-------------|------------|
| `start` | Iniciar servidores | `inicio` `fin` (opcional) |
| `stop` | Detener servidores | `inicio` `fin` (opcional) |
| `restart` | Reiniciar servidores | `inicio` `fin` (opcional) |
| `update` | Actualizar servidores | Tipo: `automatic`/`manual` |

**Ejemplos:**
```bash
# Iniciar todos los servidores
./menu_gameserver.sh start

# Iniciar servidores 2 a 4
./menu_gameserver.sh start 2 4

# Detener servidor específico
./menu_gameserver.sh stop 3 3

# Actualización automática (con parada)
./menu_gameserver.sh update automatic
```

## API de Clonación de Servidores

### `clone_l4d2server.sh`

#### Parámetros
- `AMOUNT_CLONES`: Número entero ≥ 0

#### Comportamiento por Valor

| Valor | Comportamiento |
|-------|----------------|
| `0` | Solo configura servidor principal |
| `1-N` | Crea N servidores adicionales |

#### Archivos de Configuración

##### `clone_l4d2server.json`
```json
{
  "amount_clones": 3,
  "server_prefix": "l4d2server", 
  "sourcemod_prefix": "sourcemod"
}
```

##### `clone_exclude.json`
Define qué archivos copiar vs. enlazar:

```json
{
  "bin": [],
  "configs": ["databases.cfg", "core.cfg"],
  "data": ["system2.cfg"],
  "extensions": [],
  "gamedata": [],
  "plugins": ["custom_plugin.smx"],
  "translations": ["es.txt"]
}
```

#### Estructura de Servidores Generada

| Servidor | Ejecutable | Directorio SourceMod |
|----------|------------|---------------------|
| Principal | `l4d2server` | `sourcemod1` |
| Clon 1 | `l4d2server-2` | `sourcemod2` |
| Clon 2 | `l4d2server-3` | `sourcemod3` |
| Clon N | `l4d2server-N+1` | `sourcemodN+1` |

## API de Instalación

### `install_gameserver.sh`

#### Modos de Operación

| Modo | Parámetro | Descripción |
|------|-----------|-------------|
| Instalación | `install` o `0` | Instalación limpia |
| Actualización | `update` o `1` | Preserva configuraciones |

#### Proceso de Backup/Restore

Durante actualizaciones, se usa `backup_gameserver.json`:

```json
{
  "configs": ["databases.cfg", "admins_simple.ini"],
  "data": ["system2.cfg", "basecommands.cfg"],
  "plugins": ["custom_admin.smx"]
}
```

**Secuencia:**
1. Backup de archivos especificados
2. Limpieza de directorios
3. Instalación/actualización
4. Restauración de archivos

#### Variables de Control

| Variable | Tipo | Efecto |
|----------|------|--------|
| `GIT_FORCE_DOWNLOAD` | `boolean` | Fuerza descarga de repos |
| `REPOS_JSON` | `path` | Archivo de configuración repos |

### Configuración Adicional via .env

El archivo `.env` en `/data/server-scripts/` tiene una función dual:

1. **Configuración del Workshop Downloader** (ver sección anterior)
2. **Variables para subscripts de post-procesamiento**

#### Variables para Subscripts

Los subscripts en `git-gameserver/` pueden acceder a variables personalizadas:

```bash
# Tokens de autenticación
GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
STEAM_API_KEY=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

# Configuraciones específicas
COMPETITIVE_MODE=true
TOURNAMENT_MODE=false
CUSTOM_CONFIG_URL=https://github.com/usuario/config.git

# Variables para plugins
DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/xxx/xxx
DATABASE_HOST=localhost
STATS_ENABLED=true
```

#### Acceso desde Subscripts

```bash
#!/bin/bash
# Ejemplo: mi_repo.main.sh
set -euo pipefail

# Las variables del .env están automáticamente disponibles
if [[ "${GITHUB_TOKEN:-}" ]]; then
    log "Usando token de GitHub para acceso autenticado"
    git clone https://$GITHUB_TOKEN@github.com/private/repo.git
fi

if [[ "${COMPETITIVE_MODE:-false}" == "true" ]]; then
    log "Aplicando configuración competitiva"
    # Aplicar configuraciones específicas
fi
```

## API de Repositorios Git

### Formato `repos.json`

```json
[
  {
    "repo_url": "https://github.com/user/repo.git",
    "folder": "nombre_local",
    "branch": "rama_especifica"
  }
]
```

### Scripts de Post-procesamiento

#### Convención de Nombres
`{folder}.{branch}.sh`

#### Parámetros de Entrada
1. `REPO_DIR`: Directorio del repositorio
2. `INSTALL_TYPE`: `install` o `update`
3. `GIT_DOWNLOAD`: `true` si descargado, `false` si caché

#### Ejemplo de Implementación
```bash
#!/bin/bash
set -euo pipefail

REPO_DIR="$1"
INSTALL_TYPE="${2:-install}"
GIT_DOWNLOAD="${3:-false}"

source "$DIR_SCRIPTING/tools_gameserver.sh"

# Función de procesamiento
procesar_repo() {
    if [[ -d "$REPO_DIR/plugins" ]]; then
        cp -r "$REPO_DIR/plugins/"* "$DIR_SOURCEMOD/plugins/"
        log "Plugins copiados desde $REPO_DIR"
    fi
}

# Lógica principal
if [[ "$GIT_DOWNLOAD" == "true" ]]; then
    log "Procesando descarga reciente de $REPO_DIR"
    procesar_repo
else
    log "Usando caché para $REPO_DIR"
    procesar_repo
fi
```

## API de Workshop.py

### Parámetros de Línea de Comandos

```bash
python3 workshop.py [OPCIONES] collection_id1 collection_id2...
```

| Opción | Descripción |
|--------|-------------|
| `-h` | Mostrar ayuda |
| `-o OUTPUT_DIR` | Directorio de salida |
| `-s SAVE_FILE` | Archivo de estado |

### Archivos Generados

#### `addons.lst`
Archivo JSON con estado de descargas:

```json
{
  "collections": ["3489804150"],
  "plugins": {
    "123456789": {
      "name": "Plugin Name",
      "downloaded": true,
      "last_update": "2024-12-19T10:30:45Z"
    }
  }
}
```

### Códigos de Retorno

| Código | Descripción |
|--------|-------------|
| `0` | Éxito |
| `1` | Error de configuración |
| `2` | Error de descarga |
| `None` | Error interno Python |

## Eventos y Hooks del Sistema

### Puntos de Extensión

#### 1. Pre-instalación
Archivos en `/app/docker-scripts/` ejecutados antes de instalación.

#### 2. Post-instalación  
Scripts en `git-gameserver/` ejecutados después de clonar repos.

#### 3. Pre-inicio
Configuraciones aplicadas antes de iniciar servidores.

### Variables de Estado

| Variable | Ubicación | Descripción |
|----------|-----------|-------------|
| `L4D2_FRESH_INSTALL` | Runtime | Indica instalación nueva |
| `GIT_DOWNLOAD` | Scripts git | Indica descarga vs caché |
| `INSTALL_TYPE` | Scripts | Tipo de instalación |

## Debugging y Logs

### Niveles de Log

| Función | Nivel | Uso |
|---------|-------|-----|
| `log()` | INFO | Información general |
| `error_exit()` | ERROR | Errores fatales |
| `echo` | DEBUG | Información detallada |

### Archivos de Log Principales

| Archivo | Ubicación | Contenido |
|---------|-----------|-----------|
| `install_gameserver.log` | `/data/server-scripts/` | Proceso de instalación |
| `workshop_*.log` | `/data/server-scripts/` | Actividad del workshop |
| `maps_l4d2center.log` | `/data/tmp/` | Descarga de mapas |
| `l4d2server-console.log` | `/data/log/` | Consola del servidor |

### Habilitación de Debug

```bash
# En scripts específicos
DEBUG=true ./mi_script.sh

# Globalmente
export DEBUG=true

# Modo bash debug
set -x
```
