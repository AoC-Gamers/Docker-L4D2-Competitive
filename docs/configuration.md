# Configuración Avanzada

## 📑 Tabla de Contenidos

1. [Variables de Entorno Completas](#variables-de-entorno-completas)
2. [Configuración L4D2Updater](#configuración-l4d2updater)
3. [Arquitectura de Persistencia y Enlaces Simbólicos](#arquitectura-de-persistencia-y-enlaces-simbólicos)
4. [Configuración de Servidores Múltiples](#configuración-de-servidores-múltiples)
5. [Configuración del Workshop](#configuración-del-workshop)
6. [Configuración de Mapas L4D2Center](#configuración-de-mapas-l4d2center)
7. [Configuración de Fuentes de Instalación](#configuración-de-fuentes-de-instalación)
8. [Configuración de Red y Puertos](#configuración-de-red-y-puertos)
9. [Backup y Restauración](#backup-y-restauración)
10. [Optimización de Rendimiento](#optimización-de-rendimiento)
11. [Monitoreo y Logs](#monitoreo-y-logs)

---

## Variables de Entorno Completas

### Variables del Contenedor Principal

```bash
# Autenticación y Acceso
LGSM_PASSWORD=contraseña_segura    # Contraseña del usuario linuxgsm
SSH_PORT=2222                      # Puerto SSH personalizado
SSH_KEY=ssh-rsa AAAAB...          # Claves SSH públicas (separadas por comas)

# Credenciales Steam (Opcional - se limpian automáticamente)
STEAM_USER=tu_usuario_steam        # Usuario Steam para instalación oficial
STEAM_PASSWD=tu_contraseña_steam   # Contraseña Steam (se elimina tras uso)

# Control de Instalación del Servidor L4D2
L4D2_NO_INSTALL=false             # Controla método de instalación del servidor
L4D2_NO_AUTOSTART=false           # Evitar inicio automático del servidor
L4D2_FRESH_INSTALL=false          # Forzar instalación limpia

# Sistema L4D2Updater
L4D2_NO_UPDATER=false             # Control del sistema de actualizaciones automáticas

# Configuraciones de Desarrollo
LGSM_DEV=false                    # Habilitar modo desarrollador
GIT_FORCE_DOWNLOAD=false          # Forzar descarga de repositorios
GITHUB_TOKEN=ghp_xxx              # Opcional: consultar y descargar releases GitHub
```

### 🔧 Control de Instalación del Servidor L4D2

#### Sistema de Instalación Inteligente

El contenedor ahora incluye **3 métodos de instalación** que se seleccionan automáticamente:

1. **🏆 Steam Oficial** - Si `STEAM_USER` y `STEAM_PASSWD` están disponibles
2. **🔧 Workaround Automático** - Usando `l4d2_fix_install.sh` (método comunitario)
3. **📝 Instalación Manual** - Si `L4D2_NO_INSTALL=true`

#### Variables de Control

```bash
# Credenciales Steam (Opcional)
STEAM_USER=tu_usuario_steam        # Si está presente, usa instalación oficial
STEAM_PASSWD=tu_contraseña_steam   # Se elimina automáticamente tras uso

# Control manual de instalación
L4D2_NO_INSTALL=false             # true = deshabilita instalación automática
```

#### Flujo de Instalación

```
Inicio → ¿STEAM_USER presente?
  ├─ Sí → Instalación Steam Oficial → Limpiar credenciales
  └─ No → ¿L4D2_NO_INSTALL=true?
      ├─ Sí → Instalación Manual
      └─ No → Workaround Automático
```

#### **Método 1: Steam Oficial** (Recomendado si tienes cuenta)

**Ventajas:**
- ✅ **Método oficial**: Soportado por Valve
- ✅ **Más rápido**: Descarga directa sin conversiones
- ✅ **Automático**: Se limpia después del uso
- ✅ **Seguro**: Credenciales se eliminan tras instalación

**Configuración:**
```bash
STEAM_USER=tu_usuario_steam
STEAM_PASSWD=tu_contraseña_steam
# Nota: Si Steam falla, automáticamente usa workaround
```

#### **Método 2: Workaround Automático** (Predeterminado)

**Ventajas:**
- ✅ **Sin credenciales**: No requiere cuenta Steam
- ✅ **Totalmente automático**: Sin intervención manual
- ✅ **Método validado**: Basado en [solución comunitaria](https://github.com/ValveSoftware/steam-for-linux/issues/11522#issuecomment-2512232264)
- ⚙️ **Técnica**: Instala para Windows + valida para Linux

**Configuración:**
```bash
# No requiere configuración adicional - es el predeterminado
# O explícitamente:
L4D2_NO_INSTALL=false
```

#### **Método 3: Instalación Manual**

**Cuándo usar:**
- 🔧 Tienes proceso de instalación personalizado
- � Quieres usar tu propia imagen L4D2 pre-instalada
- ⚙️ Necesitas control total del proceso

**Configuración:**
```bash
L4D2_NO_INSTALL=true              # Deshabilita instalación automática
```

**Proceso manual:**
```bash
# Ejecutar dentro del contenedor
docker-compose exec comp_l4d2 bash
./l4d2server install  # Instalación manual oficial
```
```bash
# Para la mayoría de usuarios (predeterminado)
L4D2_NO_INSTALL=false

# Para usuarios con cuenta Steam específica
L4D2_NO_INSTALL=true
```

#### `L4D2_NO_AUTOSTART` - Control de Inicio Automático

| Valor | Comportamiento |
|-------|----------------|
| `false` o sin definir | **Inicio automático** del servidor después de instalación |
| `true` | **Sin inicio automático** - permite configuración manual |

**Casos de uso para `L4D2_NO_AUTOSTART=true`:**
- Configuración manual de servidores antes del primer inicio
- Desarrollo y testing de configuraciones
- Instalación en múltiples etapas

#### `L4D2_FRESH_INSTALL` - Instalación Limpia

| Valor | Comportamiento |
|-------|----------------|
| `false` o sin definir | **Preservar configuraciones** existentes |
| `true` | **Instalación desde cero** - elimina configuraciones previas |

**⚠️ Precaución**: `L4D2_FRESH_INSTALL=true` eliminará todas las configuraciones personalizadas.
```

### Variables de LinuxGSM

```bash
# Configuración del Repositorio
LGSM_GITHUBUSER=GameServerManagers
LGSM_GITHUBREPO=LinuxGSM
LGSM_GITHUBBRANCH=master

# Directorios del Sistema
LGSM_LOGDIR=/data/log
LGSM_SERVERFILES=/data/serverfiles
LGSM_DATADIR=/data/lgsm
LGSM_CONFIG=/data/lgsm-config
```

## Configuración L4D2Updater

### 🔄 Sistema de Actualizaciones Automáticas

L4D2Updater configura el servidor para usar el **mecanismo nativo de actualizaciones de Valve**, permitiendo actualizaciones automáticas sin intervención manual.

#### Variable de Control

```bash
L4D2_NO_UPDATER=false             # Instalar L4D2Updater (predeterminado)
L4D2_NO_UPDATER=true              # Deshabilitar sistema de actualizaciones
```

#### ⚙️ Funcionamiento del Sistema

**Instalación Automática:**
- ✅ **Después de cada instalación** del servidor L4D2
- ✅ **Verifica requisitos**: `srcds_run` existe y `L4D2_NO_UPDATER` no está habilitado
- ✅ **Completamente automático**: No requiere configuración adicional

**Archivos Generados:**
```
/data/serverfiles/
├── srcds_run              # Original de Valve
├── srcds_l4d2            # ← Clon personalizado con AUTO_UPDATE="yes"
└── update_l4d2.txt       # ← Script SteamCMD para actualizaciones

/data/config-lgsm/l4d2server/
└── common.cfg            # ← Modificado: executable="./srcds_l4d2"
```

**Variables Configuradas Automáticamente:**
```bash
# En srcds_l4d2
AUTO_UPDATE="yes"                                    # Habilita actualizaciones
STEAM_DIR="$HOME/.steam/steam/steamcmd"             # Directorio SteamCMD
STEAMCMD_SCRIPT="$HOME/serverfiles/update_l4d2.txt" # Script de actualización
```

**Contenido del Script de Actualización:**
```bash
# update_l4d2.txt
@ShutdownOnFailedCommand 1
@NoPromptForPassword 1
force_install_dir /data/serverfiles/
login anonymous          # ← Evita solicitudes SteamGuard
app_update 222860
quit
```

#### 🛡️ Consideraciones de Seguridad

**Login Anónimo:**
- ✅ **Siempre usa `login anonymous`** para actualizaciones
- ✅ **Evita SteamGuard**: No solicita autenticación móvil en cada inicio
- ✅ **Sin credenciales**: No almacena información de usuario para actualizaciones

**Separación de Responsabilidades:**
- 🔐 **Credenciales Steam**: Solo para instalación inicial (se limpian automáticamente)
- 🔄 **Actualizaciones**: Usa login anónimo con infraestructura oficial de Valve

#### 🔧 Casos de Uso

**Deshabilitar L4D2Updater:**
```bash
# En .env
L4D2_NO_UPDATER=true

# Útil para:
# - Servidores con versiones específicas
# - Entornos de desarrollo/testing
# - Control manual de actualizaciones
```

**Verificar Instalación:**
```bash
# Verificar que el sistema está funcionando
docker-compose exec comp_l4d2 ls -la /data/serverfiles/srcds_l4d2
docker-compose exec comp_l4d2 cat /data/serverfiles/update_l4d2.txt
docker-compose exec comp_l4d2 grep "executable=" /data/config-lgsm/l4d2server/common.cfg
```

**Reinstalar Sistema:**
```bash
# Si necesitas reinstalar L4D2Updater
docker-compose exec comp_l4d2 bash /app/docker-scripts/l4d2_updater.sh
```

Ver [Documentación Completa L4D2Updater](l4d2-updater.md) para información técnica detallada.

## Arquitectura de Persistencia y Enlaces Simbólicos

### 🔍 Separación de Directorios: /app vs /data

El proyecto utiliza una arquitectura de **separación de responsabilidades** entre directorios:

#### 📁 Directorio `/app` (No Persistente)
- **Contenido**: Scripts de instalación, subscripts, y caché de fuentes Git o artefactos
- **Propósito**: Código actualizable con nuevas versiones del contenedor
- **Comportamiento**: Se sobrescribe en cada actualización de imagen
- **Incluye**:
  - `/app/server-scripts/` - Scripts principales
  - `/app/server-scripts/git-gameserver/` - Subscripts de post-procesamiento
  - Cache de checkouts Git y artefactos extraídos

#### 💾 Directorio `/data` (Persistente)
- **Contenido**: Gameserver, configuraciones, logs, y datos de usuario
- **Propósito**: Información que debe sobrevivir actualizaciones
- **Comportamiento**: Persistente via volumen Docker
- **Incluye**:
  - `/data/serverfiles/` - Archivos del servidor L4D2
  - `/data/lgsm/` - Configuraciones LinuxGSM
  - `/data/log/` - Logs del sistema
  - **Enlaces simbólicos** hacia scripts en `/app/`

### ⚙️ Configuración Obligatoria del Volumen

**En `docker-compose.yml` es OBLIGATORIO:**
```yaml
services:
  comp_l4d2:
    volumes:
      - comp_data:/data  # ← CRÍTICO: Persistencia de datos
    
volumes:
  comp_data:
    name: comp_data      # ← OBLIGATORIO: Volumen nombrado
```

**❌ Sin este volumen**: 
- Se pierden configuraciones del servidor
- Se pierden mapas y contenido workshop descargado
- Se pierden logs y datos de juego
- Cada reinicio = instalación desde cero

### 🔗 Rol Crítico de `symlink.sh`

El script `symlink.sh` es **fundamental** para mantener coherencia entre `/app` y `/data`:

#### Proceso de Enlaces Simbólicos

```bash
# Enlaces desde /app hacia /data para acceso persistente
/data/menu_gameserver.sh → /app/server-scripts/menu_gameserver.sh
/data/lgsm/lgsm/server-scripts/install_gameserver.sh → /app/server-scripts/install_gameserver.sh
/data/lgsm/lgsm/server-scripts/workshop_downloader.sh → /app/server-scripts/workshop_downloader.sh
# ... todos los scripts de /app/server-scripts/
```

#### Ventajas del Sistema de Enlaces

1. **Acceso Consistente**: Scripts disponibles en `/data` (persistente)
2. **Actualizaciones Automáticas**: Scripts se actualizan con nuevas versiones
3. **Trabajo en `/data`**: Usuarios pueden ejecutar desde directorio persistente
4. **Coherencia**: Modificaciones en `/app` se reflejan automáticamente
5. **Compatibilidad**: LinuxGSM funciona desde `/data` sin problemas

#### Flujo de Actualización

```mermaid
graph TD
    A[🔄 Actualización Contenedor] --> B[📦 Nueva Imagen]
    B --> C[🗂️ /app Sobrescrito]
    C --> D[🔗 symlink.sh Ejecutado]
    D --> E[📁 Enlaces Recreados]
    E --> F[✅ Scripts Actualizados en /data]
    F --> G[🎮 Gameserver Mantiene Datos]
    
    style C fill:#ff6b6b,stroke:#333,stroke-width:2px
    style F fill:#4ecdc4,stroke:#333,stroke-width:2px
    style G fill:#45b7d1,stroke:#333,stroke-width:2px
```

### 🎯 Ejemplo Práctico de Actualización

**Situación**: Se lanza nueva versión con mejoras en `install_gameserver.sh`

**Sin volumen persistente** ❌:
```bash
docker-compose pull  # Nueva imagen
docker-compose up -d  # ¡Se pierde TODO!
# Resultado: Reinstalación completa desde cero
```

**Con volumen persistente** ✅:
```bash
docker-compose pull  # Nueva imagen
docker-compose up -d  # Solo se actualiza /app
# Resultado: 
# - Scripts mejorados disponibles automáticamente
# - Gameserver mantiene configuraciones
# - Mapas y workshop preserved
# - Logs históricos intactos
```

[🔝 Volver arriba](#configuración-avanzada)

## Configuración de Servidores Múltiples

### Clonación de Servidores

El proyecto soporta múltiples instancias del servidor L4D2:

```bash
# Crear 3 servidores adicionales (total: 4 servidores)
./clone_l4d2server.sh 3

# Configuración automática:
# - l4d2server (servidor principal)
# - l4d2server-2 (clon 1)
# - l4d2server-3 (clon 2) 
# - l4d2server-4 (clon 3)
```

### Configuración de Archivos JSON

#### `clone_l4d2server.json`
```json
{
  "amount_clones": 3,
  "server_prefix": "l4d2server",
  "sourcemod_dir_prefix": "sourcemod"
}
```

#### `clone_exclude.json`
Define qué archivos copiar vs. enlazar simbólicamente:

```json
{
  "configs": ["databases.cfg", "core.cfg"],
  "data": ["system2.cfg"],
  "plugins": ["custom_plugin.smx"]
}
```

### Gestión de Múltiples Servidores

```bash
# Iniciar servidores del 1 al 3
./menu_gameserver.sh start 1 3

# Detener todos los servidores
./menu_gameserver.sh stop

# Reiniciar servidor específico
./menu_gameserver.sh restart 2 2

# Actualizar todos (con parada automática)
./menu_gameserver.sh update
```

## Configuración del Workshop

### Archivo de Configuración `.env`

El archivo `.env` en `/data/server-scripts/` cumple una **doble función**:

1. **Configuración del Workshop Downloader**
2. **Variables para subscripts de instalación**

Crear en `/data/server-scripts/.env`:

```bash
# =============================================================================
# CONFIGURACIÓN DEL WORKSHOP
# =============================================================================
# Artículos individuales del Workshop (IDs separados por comas)
WORKSHOP_ITEMS=123456789,987654321,456789123

# Colecciones del Workshop (IDs separados por comas) 
WORKSHOP_COLLECTIONS=3489804150,2222222222

# Directorio de salida
OUTPUT_DIR=$DIR_LEFT4DEAD2/addons/workshop

# Configuración de descarga
BATCH_SIZE=5          # Artículos por lote
BATCH_DELAY=10        # Segundos entre lotes

# =============================================================================
# CONFIGURACIÓN PARA SUBSCRIPTS DE INSTALACIÓN
# =============================================================================
# Tokens de autenticación para repositorios privados
GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
STEAM_API_KEY=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

# Configuraciones específicas de modos de juego
COMPETITIVE_MODE=true
TOURNAMENT_MODE=false
CUSTOM_CONFIG_URL=https://github.com/usuario/configuraciones.git

# Variables para plugins específicos
DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/xxx/xxx
DATABASE_HOST=localhost
STATS_ENABLED=true
```

**Nota importante**: Los subscripts de post-procesamiento en `git-gameserver/` pueden acceder automáticamente a estas variables ya que `install_gameserver.sh` carga el archivo `.env`.

### Uso del Workshop Downloader

```bash
# Descarga básica
./workshop_downloader.sh

# Con configuración personalizada
./workshop_downloader.sh -e mi_config.env -b 10 -d 5

# Con directorio específico
./workshop_downloader.sh -o /ruta/personalizada
```

[🔝 Volver arriba](#configuración-avanzada)

## Configuración de Mapas L4D2Center

### Variables de Entorno

```bash
# Forzar descarga de todos los mapas
L4D2_MAPS_FORCE_DOWNLOAD=true

# Descargar solo un mapa específico
L4D2_MAP=c1m1_hotel

# Omitir verificación MD5 (más rápido, menos seguro)
L4D2_MAPS_SKIP_MD5=false
```

### Ejecución Manual

```bash
# Descargar/actualizar mapas
./maps_l4d2center.sh

# Solo verificar cambios (sin descargar)
L4D2_MAPS_FORCE_DOWNLOAD=false ./maps_l4d2center.sh
```

## Configuración de Fuentes de Instalación

### Archivo `repos.json`

Competitive puede instalar contenido desde dos tipos de fuente:

1. `git`: clona un repositorio y ejecuta el hook correspondiente.
2. `github_release`: descarga un ZIP o TAR publicado en GitHub Releases, lo extrae en caché y ejecuta el mismo hook.

**Configuración actual (repositorio real):**
```json
[
  {
    "source_type": "git",
    "repo_url": "https://github.com/SirPlease/L4D2-Competitive-Rework.git",
    "folder": "sir",
    "branch": "default"
  }
]
```

**Ejemplos de configuración expandida (hipotética):**
```json
[
  {
    "source_type": "git",
    "repo_url": "https://github.com/SirPlease/L4D2-Competitive-Rework.git",
    "folder": "sir",
    "branch": "default"
  },
  {
    "source_type": "git",
    "repo_url": "https://github.com/usuario/mi-repo.git", 
    "folder": "mi_proyecto",
    "branch": "main"
  },
  {
    "source_type": "git",
    "repo_url": "https://${GITHUB_TOKEN}@github.com/private/repo.git",
    "folder": "private_config",
    "branch": "production"
  },
  {
    "source_type": "github_release",
    "github_repo": "AoC-Gamers/BanSystem",
    "release_tag": "channel/latest",
    "asset_name_glob": "bansystem-*.zip",
    "folder": "bansystem",
    "branch": "default"
  },
  {
    "source_type": "github_release",
    "github_repo": "AoC-Gamers/L4D2-CommSuite",
    "release_tag": "channel/develop",
    "asset_name_glob": "l4d2-commsuite-*.zip",
    "folder": "l4d2_commsuite",
    "branch": "default"
  }
]
```

### Configuración Dinámica de Ramas y Releases

El sistema de ramas dinámicas permite modificar automáticamente las ramas de los repositorios según las variables de entorno definidas. Esto es especialmente útil para diferentes entornos (desarrollo, testing, producción).

#### 🔧 Configuración desde Docker Compose

**Método 1: Variables en `docker-compose.yml`**
```yaml
services:
  comp_l4d2:
    image: ghcr.io/aoc-gamers/lgsm-l4d2-competitive:latest
    environment:
      - LGSM_PASSWORD=${LGSM_PASSWORD}
      - SSH_PORT=${SSH_PORT}
      - SSH_KEY=${SSH_KEY}
      # Variables dinámicas por fuente
      - BRANCH_SIR=development
      - RELEASE_TAG_BANSYSTEM=channel/develop
      # Variables para subscripts (disponibles en install_gameserver.sh)
      - COMPETITIVE_MODE=true
      - DEBUG_ENABLED=false
```

**Método 2: Variables en archivo `.env` principal**
```bash
# Archivo: .env (en la raíz del proyecto)
LGSM_PASSWORD=mi_password_seguro
SSH_PORT=2222
SSH_KEY=ssh-rsa AAAAB...

# Variables dinámicas para modificar repos.json
BRANCH_SIR=development
RELEASE_TAG_BANSYSTEM=channel/develop

# Variables adicionales para subscripts de instalación
GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
COMPETITIVE_MODE=true
TOURNAMENT_MODE=false
```

#### 🎯 Sistema de Variables Dinámicas para `repos.json`

El script `rep_branch.sh` está diseñado para **modificar dinámicamente el archivo `repos.json`** usando:

- `BRANCH_*` para ramas Git
- `RELEASE_TAG_*` para tags o canales de `github_release`

**Funcionamiento:**
1. **Lee el archivo `repos.json`** actual
2. **Para cada fuente**, busca `BRANCH_{FOLDER_UPPERCASE}` y `RELEASE_TAG_{FOLDER_UPPERCASE}`
3. **Si la variable existe** y no es "default", actualiza el campo correspondiente
4. **Guarda el archivo modificado** `repos.json`
5. **`install_gameserver.sh`** usa la nueva rama o el nuevo tag

**Archivo `repos.json` con fuente Git y artefacto:**
```json
[
  {
    "source_type": "git",
    "repo_url": "https://github.com/SirPlease/L4D2-Competitive-Rework.git",
    "folder": "sir",
    "branch": "default"
  },
  {
    "source_type": "github_release",
    "github_repo": "AoC-Gamers/BanSystem",
    "release_tag": "channel/latest",
    "asset_name_glob": "bansystem-*.zip",
    "folder": "bansystem",
    "branch": "default"
  }
]
```

**Variables para modificar la fuente:**
```bash
# Para folder: "sir" → Variable: BRANCH_SIR
BRANCH_SIR=development

# Para folder: "bansystem" → Variable: RELEASE_TAG_BANSYSTEM
RELEASE_TAG_BANSYSTEM=channel/develop
```

**Resultado después de `rep_branch.sh`:**
```json
[
  {
    "source_type": "git",
    "repo_url": "https://github.com/SirPlease/L4D2-Competitive-Rework.git",
    "folder": "sir",
    "branch": "development"  # ← Modificado dinámicamente
  },
  {
    "source_type": "github_release",
    "github_repo": "AoC-Gamers/BanSystem",
    "release_tag": "channel/develop",  # ← Modificado dinámicamente
    "asset_name_glob": "bansystem-*.zip",
    "folder": "bansystem",
    "branch": "default"
  }
]
```

**⚠️ Importante**: Las variables `BRANCH_*` solo funcionan si existe un repositorio con el `folder` correspondiente en `repos.json`.

#### 🔄 Casos de Uso por Entorno

**Docker Compose para Desarrollo:**
```yaml
# docker-compose.dev.yml
services:
  comp_l4d2:
    environment:
      # Solo repositorios existentes en repos.json
      - BRANCH_SIR=development
      - DEBUG_MODE=true
      - GIT_FORCE_DOWNLOAD=true
      
      # Ejemplos hipotéticos si agregases más repos:
      # - BRANCH_CONFIGS=dev           # Para repo con folder "configs"
      # - BRANCH_PLUGINS=experimental  # Para repo con folder "plugins"
```

**Docker Compose para Testing:**
```yaml
# docker-compose.test.yml
services:
  comp_l4d2:
    environment:
      - BRANCH_SIR=testing
      - L4D2_NO_AUTOSTART=true
      - LOG_LEVEL=debug
```

**Docker Compose para Producción:**
```yaml
# docker-compose.prod.yml
services:
  comp_l4d2:
    environment:
      # Sin variables BRANCH_* = usa rama "default" de repos.json
      - LGSM_PASSWORD=${LGSM_PASSWORD}
      - SSH_KEY=${SSH_KEY}
      - LOG_LEVEL=warning
```

#### ⚙️ Flujo de Modificación de repos.json

```mermaid
graph LR
    A[Variables BRANCH_*] --> B[rep_branch.sh]
    B --> C[Lee repos.json]
    C --> D[Modifica campo 'branch']
    D --> E[Guarda repos.json]
    E --> F[install_gameserver.sh]
    F --> G[Clona con nuevas ramas]
```

**Proceso detallado:**
1. **Variables definidas**: Docker Compose o archivo `.env` definen `BRANCH_*`
2. **Lectura**: `rep_branch.sh` lee el archivo `repos.json` actual
3. **Transformación**: Convierte `folder` a `BRANCH_{FOLDER_UPPERCASE}`
4. **Modificación**: Actualiza solo los repositorios con variables definidas
5. **Persistencia**: Guarda el archivo `repos.json` modificado
6. **Instalación**: `install_gameserver.sh` usa las nuevas ramas para clonar
5. **Post-procesamiento**: Ejecuta subscripts: `{folder}.{rama}.sh`

#### 🛠️ Comandos para Testing

```bash
# Ver variables de rama detectadas
docker-compose exec comp_l4d2 env | grep BRANCH_

# Forzar actualización con nuevas ramas
docker-compose exec comp_l4d2 bash -c "
  cd /app/docker-scripts && ./rep_branch.sh && 
  cd /app/server-scripts && GIT_FORCE_DOWNLOAD=true ./install_gameserver.sh update
"

# Ver repos.json modificado
docker-compose exec comp_l4d2 cat /app/server-scripts/repos.json
```

### Scripts de Post-Procesamiento

Crear scripts personalizados en `git-gameserver/`:

#### `mi_proyecto.main.sh`
```bash
#!/bin/bash
set -euo pipefail

REPO_DIR="$1"
INSTALL_TYPE="${2:-install}"
GIT_DOWNLOAD="${3:-false}"

# Aplicar modificaciones específicas al repositorio
if [ "$GIT_DOWNLOAD" = "true" ]; then
    echo "Aplicando configuraciones personalizadas..."
    # Copiar archivos específicos
    # Modificar configuraciones
    # etc.
fi
```

## Configuración de Red y Puertos

### Docker Compose Personalizado

```yaml
services:
  comp_l4d2:
    image: ghcr.io/aoc-gamers/lgsm-l4d2-competitive:latest
    restart: unless-stopped
    container_name: comp_l4d2
    ports:
      - "27015:27015/udp"  # Servidor L4D2
      - "27020:27020/udp"  # SourceTV
      - "2222:22"          # SSH
    volumes:
      - comp_data:/data
      - ./custom-configs:/data/custom-configs:ro
    environment:
      - LGSM_PASSWORD=${LGSM_PASSWORD}
      - SSH_PORT=22
      - SSH_KEY=${SSH_KEY}
```

## Backup y Restauración

### Configuración de Backup

```json
{
  "configs": ["databases.cfg", "admins_simple.ini"],
  "data": ["system2.cfg", "basecommands.cfg"],
  "plugins": ["custom_admin.smx"]
}
```

### Scripts de Backup Manual

```bash
# Backup antes de actualización
tar -czf backup_$(date +%Y%m%d_%H%M%S).tar.gz /data/serverfiles/left4dead2/addons/sourcemod/configs

# Restaurar desde backup
tar -xzf backup_20231201_120000.tar.gz -C /
```

## Optimización de Rendimiento

### Configuración del Sistema

```bash
# En el host Docker
echo 'net.core.rmem_max = 16777216' >> /etc/sysctl.conf
echo 'net.core.wmem_max = 16777216' >> /etc/sysctl.conf
sysctl -p
```

### Límites del Contenedor

```yaml
services:
  comp_l4d2:
    # ... otras configuraciones
    deploy:
      resources:
        limits:
          memory: 4G
          cpus: '2.0'
        reservations:
          memory: 2G
          cpus: '1.0'
```

## Monitoreo y Logs

### Configuración de Logs

```bash
# Ver logs en tiempo real
tail -f /data/log/l4d2server.log

# Logs del workshop
tail -f /data/server-scripts/workshop_*.log

# Logs de instalación
tail -f /data/server-scripts/install_gameserver.log
```

### Healthcheck Personalizado

```bash
# Script personalizado de verificación
#!/bin/bash
# Verificar múltiples servicios
nc -zv localhost 22 && \
nc -zv localhost 27015 && \
pgrep -f "srcds_run" > /dev/null
```
