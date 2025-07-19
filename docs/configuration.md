# Configuración Avanzada

## Variables de Entorno Completas

### Variables del Contenedor Principal

```bash
# Autenticación y Acceso
LGSM_PASSWORD=contraseña_segura    # Contraseña del usuario linuxgsm
SSH_PORT=2222                      # Puerto SSH personalizado
SSH_KEY=ssh-rsa AAAAB...          # Claves SSH públicas (separadas por comas)

# Control de Instalación
L4D2_NO_INSTALL=false             # Evitar instalación automática del servidor
L4D2_NO_AUTOSTART=false           # Evitar inicio automático del servidor
L4D2_FRESH_INSTALL=false          # Forzar instalación limpia

# Configuraciones de Desarrollo
LGSM_DEV=false                    # Habilitar modo desarrollador
GIT_FORCE_DOWNLOAD=false          # Forzar descarga de repositorios
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

## Configuración de Repositorios Git

### Archivo `repos.json`

```json
[
  {
    "repo_url": "https://github.com/SirPlease/L4D2-Competitive-Rework.git",
    "folder": "sir",
    "branch": "default"
  },
  {
    "repo_url": "https://github.com/usuario/mi-repo.git", 
    "folder": "mi_proyecto",
    "branch": "main"
  },
  {
    "repo_url": "https://${GITHUB_TOKEN}@github.com/private/repo.git",
    "folder": "private_config",
    "branch": "production"
  }
]
```

### Configuración Dinámica de Ramas

El sistema permite modificar las ramas de los repositorios usando variables de entorno:

#### Variables de Rama
```bash
# Formato: BRANCH_{FOLDER_UPPERCASE}
export BRANCH_SIR=development
export BRANCH_MI_PROYECTO=feature/new-update
export BRANCH_PRIVATE_CONFIG=testing
```

#### Casos de Uso por Entorno

**Desarrollo:**
```bash
export BRANCH_SIR=development
export BRANCH_CONFIGS=dev
export DEBUG_MODE=true
```

**Testing:**
```bash
export BRANCH_SIR=testing
export BRANCH_CONFIGS=staging
export COMPETITIVE_MODE=false
```

**Producción:**
```bash
# Sin variables BRANCH_* = usa ramas por defecto
export COMPETITIVE_MODE=true
export DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/prod/xxx
```

#### Flujo de Modificación
1. `rep_branch.sh` lee las variables `BRANCH_*`
2. Modifica dinámicamente `repos.json`
3. `install_gameserver.sh` usa las nuevas ramas
4. Ejecuta subscripts específicos: `{folder}.{branch}.sh`

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
