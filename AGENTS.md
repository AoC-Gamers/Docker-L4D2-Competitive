# Instrucciones para agentes — Docker-L4D2-Competitive

Leer primero [CONTEXT.md](CONTEXT.md), [README.md](README.md) y [bootstrap/privilegios](docs/bootstrap-security.md).

- Imagen padre: https://github.com/GameServerManagers/docker-linuxgsm. La cadena externa incluye https://github.com/GameServerManagers/docker-linuxgsm y https://github.com/GameServerManagers/docker-steamcmd.
- Los volúmenes existentes son autoridad: conservar CFG, SQLite, logs, demos y las identidades SSH. No borrar/recrear datos para superar un fallo.
- El contenedor aloja N gameservers, sin límite fijo de 6/12. Una instalación Valve compartida y `sourcemodN` con rutas privadas; puertos por instancia LinuxGSM, nunca globales en Compose.
- Bootstrap API 2: código privilegiado en `/usr/local/libexec/l4d2`, root-owned; nunca ejecutar como root código de `/app` o `/data`. Instalador, hooks y juegos trabajan como linuxgsm, sin sudo y con no_new_privs.
- Conservar UID/GID, grupos suplementarios BanSystem y modos SGID; no chmod/chown recursivo de volúmenes en arranques normales. SDK/resources son read-only.
- Mantener cambios ajenos. Staging por rutas revisadas; no git clean/reset/stash automático.
- Validar con `bash scripts/test-stack.sh`, Compose y pruebas reales de SSH/SFTP, permisos y varias instancias antes de publicar. Pruebas offline no equivalen a gameplay.
- Publicación: Competitive → AoC → Vanilla por digest. No duplicar el supervisor en las derivadas.
- Las instrucciones explícitas del usuario determinan alcance, publicación y operación de servicios.

- Restricción local actual: máximo DOS gameservers reales en total en el notebook, contando AoC y Vanilla. No repetir pruebas de 6/12 procesos reales; usar fixtures ligeros para coordinación.
