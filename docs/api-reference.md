# API y Referencia de Funciones

## Tabla de Contenidos

1. Variables de Runtime
2. API del Stack
3. API del Installer
4. Hooks
5. Workshop y Mapas
6. Logs

---

## Variables de Runtime

Variables principales exportadas por el bootstrap y consumidas por installer y hooks:

| Variable | Ejemplo | Descripcion |
|----------|---------|-------------|
| `DIR_INSTALLER` | `/data/installer` | Raiz operativa del installer |
| `DIR_INSTALLER_BIN` | `/data/installer/bin` | Comandos del installer |
| `DIR_INSTALLER_LIB` | `/data/installer/lib` | Librerias compartidas |
| `DIR_INSTALLER_CONFIG` | `/data/installer/config` | Configuracion del installer |
| `DIR_INSTALLER_STATE` | `/data/installer/state` | Estado persistente del installer y del despliegue |
| `DIR_STACK` | `/data/stack` | Raiz operativa del stack |
| `DIR_STACK_HOOKS` | `/data/stack/hooks` | Hooks del stack |
| `DIR_LEFT4DEAD2` | `/data/serverfiles/left4dead2` | Directorio del juego |
| `DIR_TMP` | `/app/tmp/install_stack/default/...` | Workspace temporal aislado por corrida del installer |
| `STACK_PROFILE` | `default` | Perfil seleccionado para compilar el stack |
| `L4D2_ADDITIONAL_INSTANCES` | `0` | Topologia objetivo de instancias adicionales |
| `NPM_CONFIG_AUDIT` | `false` | Controla la auditoria automatica de npm invocada por LinuxGSM/GameDig |
| `GIT_FORCE_DOWNLOAD` | `false` | Fuerza redescarga de fuentes |
| `GITHUB_TOKEN` | `ghp_xxx` | Token opcional para API y releases |
| `GITHUB_AUTH_TOKEN` | `ghp_xxx` | Token temporal interno usado por el installer para resolver un componente `github_release` concreto |

## API del Stack

### `stack/manifests/components.json`

Define el catalogo de componentes disponibles.

### `stack/profiles/*.json`

Define que componentes se activan por entorno y que overrides aplicar.

### Variables dinamicas

| Variable | Formato | Uso |
|----------|---------|-----|
| `BRANCH_*` | `BRANCH_{FOLDER}` | Override de rama Git |
| `RELEASE_TAG_*` | `RELEASE_TAG_{FOLDER}` | Override de canal o tag |

### Formato de una fuente

```json
{
  "source_type": "github_release",
  "github_repo": "AoC-Gamers/BanSystem",
  "folder": "bansystem",
  "branch": "default",
  "release_tag": "latest",
  "asset_name_glob": "*modular*.zip",
  "github_token_env": "PRIVATE_RELEASE_TOKEN"
}
```

Campos comunes:

- `source_type`
- `repo_url`
- `folder`
- `branch`

Campos especificos de `github_release`:

- `release_tag`
- `asset_name`
- `asset_name_glob`
- `github_token_env`

`github_token_env` permite declarar el nombre de una variable de entorno que contiene el token a usar para resolver y descargar ese release asset concreto. Si no se declara, el installer usa `GITHUB_TOKEN` cuando exista.

## API del Installer

### `installer/bin/install_stack.sh`

Comandos soportados:

```bash
./install_stack.sh install
./install_stack.sh update
```

Responsabilidades:

1. leer `stack/manifests/components.json`
2. leer `stack/profiles/{STACK_PROFILE}.json`
3. aplicar overrides `BRANCH_*` y `RELEASE_TAG_*`
4. resolver fuentes Git o GitHub Release
5. comparar cache y estado remoto
6. descargar o reutilizar la fuente
7. ejecutar el hook correspondiente
8. preservar rutas declaradas en `stack/preserve-paths.json` durante updates

Detalles operativos:

- el cache de componentes vive en `/data/installer/state/cache/{STACK_PROFILE}.log`
- el workspace temporal persistente por perfil vive en `/app/tmp/install_stack/{STACK_PROFILE}/`
- si una fuente remota no responde pero existe cache compatible con la misma fuente efectiva, el installer puede degradar a reuse local
- si no hay cache compatible, falla

### `installer/bin/deploy_stack.sh`

Comandos soportados:

```bash
./deploy_stack.sh
```

Responsabilidades:

1. inicializar el estado de despliegue del runtime
2. preparar tooling LGSM y modo developer
3. decidir install, no-install o workaround anonimo
4. ejecutar `install_stack.sh` cuando aplica
5. correr bootstrap de parches y preparar perfil de usuario
6. sincronizar instancias segun `L4D2_ADDITIONAL_INSTANCES`
7. arrancar solo si `L4D2_AUTOSTART=true`

### `installer/lib/tools_stack.sh`

Helpers relevantes:

- `github_api_request`
- `download_file`
- `extract_archive`
- helpers de logging y copiado

### `installer/lib/state_stack.sh`

Helpers relevantes:

- inicializacion de rutas de estado
- lectura y escritura de `deploy-state.json`
- lectura y escritura de `instances-state.json`
- archivado de historial de despliegues en `state/history/`
- metadatos de despliegue para install y update
- cierre del estado final del despliegue runtime

### `installer/lib/instance_stack.sh`

Helpers relevantes:

- resolucion de nombres y ejecutables de instancia
- conteo de instancias detectadas
- validacion de rangos para operaciones batch
- iteracion comun sobre instancias

### `installer/config/instances_exclude.json`

Define que rutas del layout `addons/sourcemod` deben copiarse por instancia en vez de compartirse por enlace simbolico.

Reglas:

- las claves validas son `bin`, `configs`, `data`, `extensions`, `gamedata`, `plugins`, `translations`
- cada valor es una lista de rutas relativas dentro de ese arbol
- si una lista queda vacia, el arbol completo se comparte por symlink
- si una ruta aparece en la lista, ese path se copia fisicamente y el resto del arbol sigue enlazado cuando sea posible

Ejemplo:

```json
{
  "data": [
    "dumps",
    "sqlite/local-backups"
  ]
}
```

Esto es util para rutas que generan estado propio por instancia, como `addons/sourcemod/data/dumps`.

### `installer/lib/install_stack_runtime.sh`

Helpers relevantes:

- resolucion de fuentes Git y GitHub Release
- cache persistente por perfil
- degradacion controlada a cache local cuando la fuente remota no responde
- limpieza previa de update
- backup y restore de preserve-paths
- aplicacion de hooks del stack

## Hooks

Ubicacion:

```text
stack/hooks/{folder}.{branch}.sh
```

Firma:

```bash
SOURCE_DIR="$1"
INSTALL_TYPE="${2:-install}"
SOURCE_DOWNLOAD="${3:-false}"
SOURCE_TYPE="${4:-git}"
```

Carga recomendada:

```bash
source "$DIR_INSTALLER_LIB/tools_stack.sh"
```

Responsabilidades habituales:

- mover archivos al `serverfiles`
- instalar o actualizar plugins y configs
- adaptar layouts distintos entre Git y release artifacts
- aplicar postprocesamiento por entorno

Convenciones recomendadas:

- para este stack, preferir `stack_install_*` como politica por defecto
- reservar `stack_replace_*` para casos muy acotados y auditados donde se quiera reemplazo total de un subarbol sin riesgo para contenido del motor o overlays externos

## Workshop y Mapas

### `installer/bin/workshop_downloader.sh`

Descarga y procesa contenido del Workshop.

### `installer/bin/maps_l4d2center.sh`

Descarga mapas desde L4D2Center.

## Logs

| Archivo | Ubicacion | Uso |
|---------|-----------|-----|
| `install_stack.log` | `/data/installer/state/current/` | Log canonico de la instalacion o actualizacion del stack activo |
| `install_stack.log` | `/data/installer/bin/` | Espejo legacy del log activo para compatibilidad operativa |
| `deploy-state.json` | `/data/installer/state/current/` | Estado actual del despliegue |
| `instances-state.json` | `/data/installer/state/current/` | Estado actual de las instancias |
| `cache/*.log` | `/data/installer/state/cache/` | Cache persistente de estado remoto por perfil |
| `history/<deployment_id>/` | `/data/installer/state/history/` | Historial por despliegue |
| `workshop_*.log` | `/data/installer/bin/` | Descargas de Workshop |
| logs LinuxGSM | `/data/log/` | Runtime de las instancias |
