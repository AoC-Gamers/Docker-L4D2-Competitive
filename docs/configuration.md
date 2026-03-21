# Configuracion Avanzada

## Variables principales

```env
LGSM_PASSWORD=mi_password_seguro
SSH_PORT=2222
STEAM_USER=mi_usuario_steam
STEAM_PASSWD=mi_contrasena_steam
L4D2_INSTALL=normal
L4D2_AUTOSTART=true
L4D2_UPDATER=true
STACK_PROFILE=default
GIT_FORCE_DOWNLOAD=false
GITHUB_TOKEN=ghp_xxx
```

## Control de instalacion y arranque

- `L4D2_INSTALL=normal`: instala solo si el servidor base no existe.
- `L4D2_INSTALL=skip`: no instala automaticamente.
- `L4D2_INSTALL=force`: fuerza la ruta de instalacion o reparacion del servidor base.
- `L4D2_AUTOSTART=true|false`: controla si el runtime arranca automaticamente despues del deploy.
- `L4D2_UPDATER=true|false`: controla el bootstrap legacy `l4d2_updater.sh` de la base competitiva.

## GeoIP

- `GEOIPUPDATE_ENABLED=true|false`: habilita la actualizacion del GeoIP de MaxMind durante `install_stack.sh install|update`.
- `GEOIPUPDATE_ACCOUNT_ID`: account ID de MaxMind.
- `GEOIPUPDATE_LICENSE_KEY`: licencia para descargar GeoLite. Se define en `.env` para que el updater siga funcionando en runtime.
- `GEOIPUPDATE_EDITION_ID`: edicion a descargar, por defecto `GeoLite2-City`.

Cuando esta habilitado, el installer deja el `.mmdb` actualizado en:

```text
/data/serverfiles/left4dead2/addons/sourcemod/configs/geoip/
```

## Configuracion del Stack

La configuracion del stack se divide en tres piezas:

1. `stack/manifests/components.json`: catalogo de componentes.
2. `stack/profiles/*.json`: seleccion por entorno.
3. `stack/sources.json`: snapshot materializado consumido por `install_stack.sh`.

### Perfil activo

`STACK_PROFILE` controla el perfil compilado por `container/bootstrap/compile_stack.sh`.

Ejemplo:

```yaml
environment:
  - STACK_PROFILE=default
```

### Overrides dinamicos

Ademas del perfil, se pueden usar overrides puntuales:

```env
BRANCH_SIR=development
RELEASE_TAG_BANSYSTEM=channel/develop
```

Flujo real:

1. se carga el manifest
2. se carga el profile activo
3. se genera `stack/sources.json`
4. se aplican los overrides de entorno
5. `install_stack.sh` consume el snapshot resultante

## Tipos de fuente soportados

### Git

```json
{
  "source_type": "git",
  "repo_url": "https://github.com/SirPlease/L4D2-Competitive-Rework.git",
  "folder": "sir",
  "branch": "master"
}
```

### GitHub Release

```json
{
  "source_type": "github_release",
  "repo_url": "https://github.com/AoC-Gamers/BanSystem",
  "folder": "bansystem",
  "branch": "default",
  "release_tag": "latest",
  "asset_name_glob": "*modular*.zip"
}
```

## Rutas relevantes

```text
/app/container/bootstrap/
/app/installer/bin/
/app/installer/lib/
/app/stack/manifests/
/app/stack/profiles/
/app/stack/hooks/
/data/installer/
/data/stack/
/data/serverfiles/
```

## Operacion manual util

### Recompilar el stack

```bash
docker-compose exec comp_l4d2 bash /app/container/bootstrap/compile_stack.sh
```

### Reinstalar o actualizar el stack

```bash
docker-compose exec comp_l4d2 bash /data/installer/bin/install_stack.sh update
```

### Reinstalar L4D2Updater

```bash
docker-compose exec comp_l4d2 bash /app/container/bootstrap/l4d2_updater.sh
```

## Recomendaciones

- usa `STACK_PROFILE` como mecanismo principal
- reserva `BRANCH_*` y `RELEASE_TAG_*` para testing puntual
- deja `stack/sources.json` como snapshot generado, no como modelo canonico
- documenta nuevos componentes en manifest y profile, no solo en compose
