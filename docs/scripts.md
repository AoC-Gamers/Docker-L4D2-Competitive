# Documentación de Scripts

## 📑 Tabla de Contenidos

1. [Visión General](#visión-general)
2. [Scripts de Configuración Inicial (`docker-scripts/`)](#scripts-de-configuración-inicial-docker-scripts)
3. [Scripts de Gestión del Servidor (`server-scripts/`)](#scripts-de-gestión-del-servidor-server-scripts)
4. [Flujo de Ejecución](#flujo-de-ejecución)

---

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

**Ejemplos con repositorio actual:**
```bash
# Para el repositorio existente "sir" 
export BRANCH_SIR=development

# Ejemplos hipotéticos para repositorios adicionales:
# export BRANCH_CONFIGS=testing        # Si agregar repo con folder "configs"
# export BRANCH_PLUGINS=feature/beta   # Si agregar repo con folder "plugins"
```

**Proceso:**
1. Lee todos los repositorios de `repos.json`
2. Para cada repo, busca variable `BRANCH_{FOLDER_UPPERCASE}`
3. Si existe y no es "default", actualiza la rama en el JSON
4. Guarda el archivo modificado

**Casos de uso:**
```bash
# Desarrollo: usar rama development para SIR
export BRANCH_SIR=development

# Testing: usar rama específica de prueba
export BRANCH_SIR=testing

# Producción: usar rama estable (por defecto)
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
Crea enlaces simbólicos críticos para mantener coherencia entre `/app` (no persistente) y `/data` (persistente).

**Importancia Crítica:**
- **Persistencia**: Permite que scripts estén disponibles en `/data` después de actualizaciones
- **Coherencia**: Mantiene sincronización automática entre directorios
- **Compatibilidad**: LinuxGSM puede trabajar desde `/data` sin problemas
- **Actualizaciones**: Scripts se actualizan automáticamente con nuevas versiones

**Funcionalidades:**
- Crea enlaces simbólicos para todos los scripts de `/app/server-scripts/`
- Organiza estructura de directorios en `/data`
- Excluye `menu_gameserver.sh` del directorio general (enlace especial en `/data`)
- Maneja subcarpeta `git-gameserver/` por separado

**Estructura de Enlaces Creada:**
```bash
# Enlace especial en raíz de /data
/data/menu_gameserver.sh → /app/server-scripts/menu_gameserver.sh

# Scripts principales en /data/lgsm/lgsm/server-scripts/
/data/lgsm/lgsm/server-scripts/install_gameserver.sh → /app/server-scripts/install_gameserver.sh
/data/lgsm/lgsm/server-scripts/workshop_downloader.sh → /app/server-scripts/workshop_downloader.sh
/data/lgsm/lgsm/server-scripts/clone_l4d2server.sh → /app/server-scripts/clone_l4d2server.sh
# ... (todos los scripts excepto menu_gameserver.sh)

# Subscripts en subcarpeta
/data/lgsm/lgsm/server-scripts/git-gameserver/ → /app/server-scripts/git-gameserver/*
```

**Variables de entorno:**
- `DIR_SCRIPTING`: Directorio destino para enlaces (definido por LinuxGSM)

**Uso:**
```bash
./symlink.sh
# No requiere parámetros, usa variables de entorno predefinidas
```

### `l4d2_updater.sh`
Configura el sistema de actualizaciones automáticas L4D2Updater usando el mecanismo nativo de Valve.

**Funcionalidades:**
- ✅ **Clona `srcds_run`**: Crea `srcds_l4d2` personalizado con `AUTO_UPDATE="yes"`
- ✅ **Genera script SteamCMD**: Crea `update_l4d2.txt` con comandos de actualización
- ✅ **Configura LGSM**: Modifica LinuxGSM para usar el ejecutable personalizado
- ✅ **Login anónimo**: Evita solicitudes SteamGuard en cada inicio

**Variables de entorno:**
- `L4D2_NO_UPDATER`: Si es `true`, omite instalación del sistema

**Requisitos:**
- Servidor L4D2 completamente instalado
- Archivo `srcds_run` presente en `/data/serverfiles/`
- LinuxGSM configurado

**Archivos generados:**
```bash
/data/serverfiles/srcds_l4d2        # Ejecutable personalizado
/data/serverfiles/update_l4d2.txt   # Script SteamCMD
# Modifica: /data/config-lgsm/l4d2server/common.cfg
```

**Uso:**
```bash
# Instalación automática (después de instalación L4D2)
# O instalación manual:
./l4d2_updater.sh
```

**Verificación:**
```bash
# Verificar instalación
ls -la /data/serverfiles/srcds_l4d2
cat /data/serverfiles/update_l4d2.txt
grep "executable=" /data/config-lgsm/l4d2server/common.cfg
```

Ver [Documentación Completa L4D2Updater](l4d2-updater.md) para información detallada.

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
**Script crítico para instalación del servidor L4D2** que resuelve las limitaciones de autenticación de Steam para servidores Linux.

#### 🔒 Contexto del Problema de Steam

**Problema**: Steam dejó de permitir la descarga anónima de servidores de L4D2 para Linux, requiriendo ahora autenticación con cuenta Steam.

**Impacto**: Los servidores Linux no pueden instalarse de forma automática sin proporcionar credenciales Steam.

#### 🛠️ Solución Implementada

Este script utiliza una **solución no oficial** basada en [este comentario de GitHub](https://github.com/ValveSoftware/steam-for-linux/issues/11522#issuecomment-2512232264):

**Método de instalación dual:**
1. **Descarga para Windows**: Instala el servidor completo especificando plataforma Windows
2. **Validación para Linux**: Ejecuta validación para Linux, descargando solo archivos faltantes
3. **Resultado**: Servidor completo funcional en Linux sin autenticación

#### ⚙️ Funcionamiento Técnico

```bash
# 1. Instalación completa para Windows (sin limitación de autenticación)
steamcmd +login anonymous +@sSteamCmdForcePlatformType "windows" +app_update 222860 validate

# 2. Validación para Linux (descarga solo archivos faltantes específicos de Linux)
steamcmd +login anonymous +@sSteamCmdForcePlatformType "linux" +app_update 222860 validate
```

**Ventajas de este método:**
- ✅ **Sin autenticación**: No requiere cuenta Steam
- ✅ **Automático**: Instalación completamente desatendida
- ✅ **Eficiente**: Solo descarga archivos necesarios para Linux
- ✅ **Confiable**: Método validado por la comunidad

#### 🎛️ Opciones de Usuario

##### Opción 1: Instalación Automática (Predeterminada)
```bash
# En .env o docker-compose.yml
L4D2_NO_INSTALL=false  # (o sin definir)
```
- **Comportamiento**: Ejecuta `l4d2_fix_install.sh` automáticamente
- **Para quién**: Mayoría de usuarios que quieren instalación sin complicaciones

##### Opción 2: Instalación Manual con Cuenta Steam
```bash
# En .env o docker-compose.yml
L4D2_NO_INSTALL=true
```
**Proceso manual:**
```bash
# 1. Acceder al contenedor
docker-compose exec comp_l4d2 bash

# 2. Agregar cuenta Steam manualmente
./l4d2server install

# 3. Proporcionar credenciales cuando se solicite
# Steam Username: tu_usuario
# Steam Password: tu_contraseña
```
- **Para quién**: Usuarios que prefieren usar cuenta Steam oficial
- **Ventaja**: Método oficialmente soportado por Steam
- **Desventaja**: Requiere credenciales y proceso manual

#### 🔧 Proceso de Instalación

**Funcionalidades:**
- Instalación dual de plataformas (Windows + Linux)
- Creación de enlace simbólico `/app/serverfiles`
- Validación de archivos del servidor
- Verificación de usuario correcto

**Uso automático:**
```bash
# Ejecutado automáticamente si L4D2_NO_INSTALL != true
./l4d2_fix_install.sh
```

**Variables verificadas:**
- `LGSM_SERVERFILES`: Directorio de archivos del servidor
- `USER`: Usuario actual (debe ser linuxgsm)

#### 📊 Comparación de Métodos

| Aspecto | Instalación Automática | Cuenta Steam Manual |
|---------|----------------------|-------------------|
| **Autenticación** | No requerida | Cuenta Steam necesaria |
| **Automatización** | 100% automática | Requiere intervención manual |
| **Tiempo** | ~15-30 minutos | ~15-30 minutos + tiempo manual |
| **Seguridad** | No expone credenciales | Requiere credenciales Steam |
| **Soporte** | Método comunitario | Método oficial Steam |
| **Confiabilidad** | Alta (validado) | Alta (oficial) |

#### 🚨 Notas Importantes

- **Método predeterminado**: Instalación automática sin autenticación
- **Compatibilidad**: Funciona con todas las versiones actuales de L4D2
- **Actualización**: Las actualizaciones del servidor funcionan normalmente después de la instalación inicial
- **Referencia**: [Discusión técnica en GitHub](https://github.com/ValveSoftware/steam-for-linux/issues/11522#issuecomment-2512232264)

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
