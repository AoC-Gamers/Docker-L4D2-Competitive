# Docker-L4D2-Competitive

Docker-L4D2-Competitive es un contenedor Docker orientado al despliegue y gestión de servidores competitivos de Left 4 Dead 2. Basado en el proyecto [docker-gameserver](https://github.com/GameServerManagers/docker-gameserver), este proyecto incorpora scripts adicionales para la instalación de dependencias, configuración y clonación de servidores, optimizados para entornos competitivos.

## Funcionalidades del Proyecto

### Scripts de Configuración Inicial (docker-script/)
- **dependencies_check.sh:**  
  Verifica e instala las dependencias requeridas en sistemas Debian.
- **rep_branch.sh:**  
  Actualiza el campo "branch" en el archivo `repos.json` según las variables de entorno.
- **ssh.sh:**  
  Configura el servicio SSH: deshabilita el login como root, habilita autenticación por contraseña, y configura el puerto SSH.
- **symlink.sh:**  
  Crea enlaces simbólicos para organizar scripts y configuraciones.

### Scripts de Gestión del Servidor (server-scripts/)
- **workshop.py:**  
  Gestiona la descarga y actualización de plugins desde la API de Steam.
- **clone_l4d2server.sh:**  
  Clona servidores L4D2 usando LinuxGSM, permitiendo la creación y gestión de múltiples clones.
- **l4d2_fix_install.sh:**  
  Realiza la instalación/actualización del servidor mediante steamcmd.
- **maps_l4d2center.sh:**  
  Automatiza la descarga, verificación y actualización de mapas del servidor.
- **menu_gameserver.sh:**  
  Proporciona un menú interactivo (o comandos directos) para iniciar, detener, reiniciar y actualizar servidores.
- **install_gameserver.sh:**  
  Instala o actualiza el servidor competitivo, gestionando repositorios y archivos.
- **tools_gameserver.sh:**  
  Incluye funciones comunes para registro, manejo de errores y gestión de directorios/archivos.
- **git-gameserver/**  
  - **example.default.sh:** Prototipo para aplicar modificaciones a repositorios específicos.
  - **sir.default.sh:** Aplica cambios a la rama `default` del repositorio `L4D2-Competitive-Rework`.

## Flujo de Trabajo del Contenedor

1. **Inicio:**  
   Se inicia el contenedor mediante `docker-compose.yml` con la imagen `ghcr.io/aoc-gamers/lgsm-l4d2-competitive:latest`, montando volúmenes y configurando variables de entorno.

2. **Ejecución del Entrypoint:**  
   - `entrypoint.sh` configura el entorno, maneja señales de terminación, ajusta permisos y ejecuta scripts personalizados.
   - `entrypoint-user.sh` se encarga de la configuración e instalación del servidor, creación de enlaces simbólicos y ejecución del servidor.
     
3. **Verificación de Salud:**  
   `entrypoint-healthcheck.sh` verifica el estado del contenedor comprobando el puerto SSH.

## Contribución

1. Realiza un fork del repositorio.
2. Crea una rama con tus cambios.
3. Envía un pull request con una descripción detallada de tus mejoras o correcciones.

## Referencias

En este apartado se incluyen los enlaces y recursos utilizados:

- [docker-gameserver - GameServerManagers](https://github.com/GameServerManagers/docker-gameserver)
- [SteamCMD y actualización anónima de juegos](https://github.com/ValveSoftware/steam-for-linux/issues/11522#issuecomment-2512232264)
- [Steam Workshop Content Downloader](https://github.com/Geam/steam_workshop_downloader)
- [Mapas de L4D2Center](https://l4d2center.com/maps/servers/index.json)
- [L4D2-Competitive-Rework](https://github.com/SirPlease/L4D2-Competitive-Rework)

## Licencia

Distribuido bajo la [Licencia MIT](LICENSE).

## Contacto

Para consultas, sugerencias o reportar problemas, abre un issue en el repositorio o contacta con el equipo de desarrollo.
