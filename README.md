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
- **repos.py:**  
  Contiene una lista de repositorios de GitHub con sus respectivas URLs, carpetas de destino y ramas.
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

# Workshop Downloader

Script en bash para descargar artículos y colecciones del Steam Workshop de Left 4 Dead 2 utilizando `workshop.py`.

## Características

- **Procesamiento por lotes**: Descarga artículos en grupos de 5 (configurable) para evitar sobrecarga del servidor
- **Archivo de configuración**: Utiliza un archivo `.env` para configurar artículos y colecciones
- **Logging completo**: Genera archivos de log detallados con timestamp
- **Expansión de variables**: Soporta variables de entorno como `$DIR_LEFT4DEAD2`
- **Reintentos automáticos**: `workshop.py` incluye lógica de reintentos en caso de errores
- **Creación automática de directorios**: Crea el directorio de salida si no existe

## Instalación

1. Asegúrate de que `workshop.py` esté en el mismo directorio que `workshop_downloader.sh`
2. Haz el script ejecutable:
   ```bash
   chmod +x workshop_downloader.sh
   ```

## Configuración

1. Crea un archivo `.env` basado en `.env.example`:
   ```bash
   cp .env.example .env
   ```

2. Edita el archivo `.env` y configura tus artículos y colecciones:
   ```bash
   # Artículos individuales del Workshop (IDs separados por comas)
   WORKSHOP_ITEMS=123456789,987654321,456789123
   
   # Colecciones del Workshop (IDs separados por comas)
   WORKSHOP_COLLECTIONS=3489804150,2222222222
   
   # Directorio de salida (puedes usar variables de entorno)
   OUTPUT_DIR=$DIR_LEFT4DEAD2/addons/workshop
   
   # Configuración opcional
   BATCH_SIZE=5
   BATCH_DELAY=10
   ```

## Uso

### Uso básico
```bash
./workshop_downloader.sh
```

### Opciones disponibles
```bash
./workshop_downloader.sh [OPCIONES]

Opciones:
  -e, --env-file FILE     Archivo .env a usar (default: .env)
  -o, --output-dir DIR    Directorio de salida
  -b, --batch-size SIZE   Tamaño del lote (default: 5)
  -d, --delay SECONDS     Delay entre lotes en segundos (default: 10)
  -l, --log-file FILE     Archivo de log personalizado
  -h, --help              Mostrar ayuda
```

### Ejemplos

1. **Uso con archivo .env personalizado:**
   ```bash
   ./workshop_downloader.sh -e mi_config.env
   ```

2. **Cambiar directorio de salida:**
   ```bash
   ./workshop_downloader.sh -o /path/to/addons/workshop
   ```

3. **Procesamiento más agresivo (lotes más grandes, menos delay):**
   ```bash
   ./workshop_downloader.sh -b 10 -d 5
   ```

4. **Log personalizado:**
   ```bash
   ./workshop_downloader.sh -l workshop_custom.log
   ```

## Variables de entorno soportadas

El script expande automáticamente las variables de entorno. Ejemplos comunes:

- `$DIR_LEFT4DEAD2` - Directorio del servidor Left 4 Dead 2
- `$HOME` - Directorio home del usuario
- `$PWD` - Directorio actual

## Archivos generados

- **Log file**: `workshop_YYYYMMDD_HHMMSS.log` - Contiene toda la actividad del script
- **addons.lst**: Archivo JSON generado por `workshop.py` con el estado de las descargas

## Funcionamiento

1. **Validación**: Verifica que `workshop.py` y `python3` estén disponibles
2. **Configuración**: Carga el archivo `.env` y expande variables de entorno
3. **Procesamiento**: 
   - Divide artículos/colecciones en lotes del tamaño especificado
   - Ejecuta `workshop.py` para cada lote
   - Espera entre lotes para evitar sobrecarga
4. **Logging**: Registra toda la actividad en el archivo de log

## Solución de problemas

### Error: "path doesn't exist"
- Verifica que la variable `$DIR_LEFT4DEAD2` esté definida en tu entorno
- O usa una ruta absoluta en lugar de variables de entorno

### Error: "workshop.py no encontrado"
- Asegúrate de que `workshop.py` esté en el mismo directorio que el script
- Verifica los permisos del archivo

### Error: "python3 no está instalado"
- Instala Python 3: `sudo apt-get install python3`

## Logs

Los logs incluyen:
- Timestamp de cada operación
- Estado de cada lote procesado
- Errores y advertencias
- Información de debug (variables cargadas)

Ejemplo de salida:
```
[INFO] === Iniciando Workshop Downloader ===
[INFO] Archivo de log: /data/server-scripts/workshop_20250529_191033.log
[INFO] Verificando dependencias...
[INFO] Todas las dependencias están disponibles
[INFO] Cargando configuración desde: /data/server-scripts/.env
[DEBUG] Cargada variable: WORKSHOP_COLLECTIONS=3489804150
[DEBUG] OUTPUT_DIR expandido a: /data/serverfiles/left4dead2/addons/workshop
[INFO] Configuración:
[INFO]   - Tamaño de lote: 5
[INFO]   - Delay entre lotes: 10 segundos
[INFO]   - Directorio de salida: /data/serverfiles/left4dead2/addons/workshop
```

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
