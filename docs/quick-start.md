# Guia de Inicio Rapido

## Requisitos Previos

- Docker y Docker Compose instalados
- Git
- Acceso a internet para descargar L4D2, releases y contenido opcional del Workshop

## Instalacion Basica

### 1. Clonacion del repositorio

```bash
git clone https://github.com/AoC-Gamers/Docker-L4D2-Competitive.git
cd Docker-L4D2-Competitive
```

### 2. Configuracion del entorno

```bash
cp example.env .env
```

Variables minimas recomendadas:

```env
LGSM_PASSWORD=mi_password_seguro
SSH_PORT=2222
L4D2_INSTALL=normal
L4D2_AUTOSTART=true
STACK_PROFILE=default
```

Si vas a resolver releases privadas o a usar la API de GitHub con limites mas altos:

```env
GITHUB_TOKEN=ghp_xxx
```

### 3. Arranque del contenedor

```bash
docker-compose up -d
```

### 4. Verificacion del estado

```bash
docker-compose ps
docker-compose logs -f comp_l4d2
docker-compose exec comp_l4d2 gosu linuxgsm ./l4d2server details
```

## Que ocurre al arrancar

El flujo actual es:

1. `container/entrypoint.sh` prepara el runtime.
2. `container/bootstrap/` valida dependencias, crea symlinks y compila el stack.
3. `container/bootstrap/compile_stack.sh` genera `stack/sources.json`.
4. `container/entrypoint-user.sh` instala L4D2 si hace falta.
5. `installer/bin/install_stack.sh` instala el stack materializado.
6. `installer/bin/menu_stack.sh` opera las instancias.

## Operacion Basica

### Acceso al contenedor

```bash
docker-compose exec comp_l4d2 bash
```

### Acceso SSH

```bash
ssh linuxgsm@localhost -p 2222
```

### Comandos utiles

```bash
/data/installer/bin/menu_stack.sh start
/data/installer/bin/menu_stack.sh stop
/data/installer/bin/menu_stack.sh restart
/data/installer/bin/menu_stack.sh update
```

## Stack y perfiles

El framework ya no parte de un archivo unico de fuentes como modelo canonico. El flujo correcto es:

1. `stack/manifests/components.json`
2. `stack/profiles/{STACK_PROFILE}.json`
3. `stack/sources.json`
4. `install_stack.sh`

### Recompilar el stack manualmente

```bash
docker-compose exec comp_l4d2 bash /app/container/bootstrap/compile_stack.sh
```

### Reinstalar o actualizar el stack

```bash
docker-compose exec comp_l4d2 bash /data/installer/bin/install_stack.sh update
```

## Workshop

Si usas el downloader del Workshop, la configuracion ya debe vivir en el arbol operativo del installer o stack, no en el layout anterior de scripts.

Ejemplo rapido:

```bash
docker-compose exec comp_l4d2 bash
cd /data/installer/bin
./workshop_downloader.sh
```

## Problemas Comunes

### El contenedor no inicia

- revisa `docker-compose logs comp_l4d2`
- confirma que el volumen persistente este creado
- confirma que el puerto SSH no este ocupado

### `compile_stack.sh` falla

- verifica que exista el profile seleccionado por `STACK_PROFILE`
- verifica que `jq` este disponible dentro del contenedor
- revisa `stack/manifests/components.json` y `stack/profiles/*.json`

### La instancia primaria no arranca

- revisa `docker-compose logs -f comp_l4d2`
- revisa el estado de LinuxGSM con `./l4d2server details`
- valida que la instalacion inicial de L4D2 haya terminado

## Siguientes pasos

- leer `configuration.md`
- revisar `scripts.md`
- revisar `api-reference.md`
