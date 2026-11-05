# Caché opcional de la descarga inicial de Valve

La caché evita descargar cuatro veces el payload de L4D2 de Valve al instalar
Competitive/Vanilla en DEV y PROD sobre el mismo host. Guarda una copia limpia
adicional y la copia a cada instalación privada. No ahorra espacio, no comparte
archivos operativos, no actualiza juegos existentes y no reemplaza el instalador.
Está desactivada por defecto. La implementación pertenece a Competitive; AoC y
Vanilla la heredan por imagen, sin duplicar el gestor.

## Activación

En cada proyecto participante, configura en `.env` el mismo volumen:

```dotenv
L4D2_VALVE_CACHE_VOLUME=l4d2_valve_cache
```

Prepara el volumen una vez desde el host:

```bash
make valve-cache-volume
```

El comando lee ese valor literal desde `.env` o el entorno; no ejecuta el archivo
como shell ni carga `.env.secrets`. Usa una imagen de confianza del proyecto para
consultar el UID/GID de linuxgsm, crear el volumen e inicializar **solo su raíz**.
No arranca juegos. Un volumen existente solo se comprueba como el usuario de
runtime: no se cambian sus propietarios, permisos ni archivos.

La imagen de preparación puede elegirse por etiqueta o digest. Si el runtime usa
UID/GID personalizados, deben coincidir en los cuatro consumidores:

```bash
make valve-cache-volume \
  VALVE_CACHE_INIT_IMAGE=ghcr.io/aoc-gamers/lgsm-l4d2-competitive:develop \
  VALVE_CACHE_UID=1000 VALVE_CACHE_GID=1000
```

El helper también admite UID/GID explícitos en `.env`. Una raíz existente sin
acceso requiere revisión del operador; no se repara recursivamente. No reutilices
un volumen de datos, recursos o BanSystem para esta función.

El Compose principal monta automáticamente el volumen indicado por la variable.
No necesitas indicar un segundo archivo:

```bash
# Imagen publicada
docker compose up -d

# Desarrollo
docker compose -f docker-compose.dev.yml up -d
```

Con la variable configurada, Compose comprueba que el volumen externo exista
antes de crear el contenedor. El gestor comprueba también el montaje físico en
`/var/cache/l4d2-valve`. Si falta durante una instalación nueva, falla con un
diagnóstico; no descarga cuatro copias silenciosamente ni usa el socket Docker.

Con la variable vacía o ausente, el gestor queda desactivado y Compose no exige
ni crea un volumen compartido. Docker reserva un volumen anónimo vacío en ese
destino, con `nocopy`, sin descargas ni archivos del juego. Este pequeño volumen
anónimo permite usar un único archivo Compose sin inventar condiciones YAML.
Compose elimina del modelo la declaración externa que no tiene consumidores.

El archivo anterior `docker-compose.valve-cache.yml` queda como compatibilidad
vacía para comandos existentes; ya no aporta montajes. Puedes retirarlo de tus
comandos o de `COMPOSE_FILE`.

Si el nombre está configurado, Compose exige ese volumen incluso cuando el juego
ya está instalado. El skip del instalador no puede omitir esa comprobación previa
de Docker. Para retirar la dependencia compartida, deja la variable vacía y
recrea el contenedor conservando sus volúmenes de datos y SSH. El volumen externo
mantiene su propio ciclo de vida; Compose no lo elimina con `down -v`.

## Instalación y concurrencia

1. Si el juego ya está instalado, se omite la caché sin comprobar su montaje ni
   esperar por un escritor. `L4D2_INSTALL=skip` tampoco la consulta. `force` sobre
   un juego existente conserva el flujo original de reparación.
2. Para una instalación nueva se exige un destino ausente o vacío; se preserva
   cualquier contenido anterior, incluso si no contiene `srcds_run`.
3. Se adquiere `flock` sobre el archivo `.lock` **dentro del volumen compartido**.
   Cada consumidor espera e informa periódicamente de estado, fase y hora de
   inicio. La mera existencia del archivo `.lock` nunca significa bloqueo activo.
4. Si no hay una generación publicada, SteamCMD descarga en un workspace único,
   mediante login anónimo y el workaround Windows → Linux del instalador actual.
   Sus librerías, credenciales y HOME permanecen privados al contenedor.
5. Se comprueban archivos esenciales, appmanifest completo y hashes SHA256. Solo
   entonces se publica `current.json` mediante reemplazo atómico. El archivo
   `metadata.json` informa fases y errores; no sustituye al bloqueo del kernel.
6. La generación se verifica y copia, sin hardlinks, a un directorio temporal
   junto al destino privado. Se verifican sus bytes y se renombra al destino
   completo. El instalador sigue aplicando su stack y configurando el runtime.

Las copias y los comandos manuales usan el mismo bloqueo exclusivo; tampoco se
reconstruye una generación mientras se está copiando. Cada contenedor inicializa
su SteamCMD privado para las bibliotecas runtime, aunque no descargue el juego.
Esto puede consultar Steam; el ahorro se refiere al payload completo de L4D2.

## Ciclo de vida sin reiniciar el contenedor

Ejecuta estos comandos **como linuxgsm**, desde su sesión SSH con el entorno
habitual. Están disponibles también en AoC y Vanilla una vez propagada la imagen:

```bash
bash "$DIR_INSTALLER_BIN/valve_cache.sh" status
bash "$DIR_INSTALLER_BIN/valve_cache.sh" download
bash "$DIR_INSTALLER_BIN/valve_cache.sh" validate
bash "$DIR_INSTALLER_BIN/valve_cache.sh" download --force
```

| Comando | Comportamiento |
|---|---|
| `status` | JSON con fase, timestamps, error, bloqueo activo y operación interrumpida; no espera |
| `download` | Prepara si falta; si ya existe, verifica integridad y omite la descarga |
| `validate` | Verificación local de hashes, archivos y permisos ejecutables; no consulta Steam |
| `download --force` | Descarga y publica explícitamente una generación nueva |

`seed` es la integración interna del instalador y no debe utilizarse para
sobrescribir un juego existente. No hay TTL, cron ni comprobación automática de
versiones nuevas. `ready` significa copia íntegra publicada, no necesariamente
la última versión de Valve. Actualizar la caché solo afecta instalaciones futuras.

## Fallos y conservación

Al morir un escritor, el kernel libera el lock. Sus archivos parciales permanecen
en su workspace único y nunca se interpretan como una generación válida. El
siguiente intento puede preparar otra generación sin reutilizar esos archivos.
Una copia privada interrumpida no publica `srcds_run` en el destino final antes
de completar la copia y su verificación.

Una caché dañada falla con un diagnóstico: usa `validate` y después
`download --force`. No se intenta reparar ni copiar datos de ningún gameserver.
Si una reconstrucción falla, conserva la generación anteriormente publicada.
Las generaciones anteriores y los workspaces interrumpidos no se recolectan
automáticamente; ocupan espacio adicional. No borres workspaces mientras un
SteamCMD superviviente pueda seguir escribiéndolos.

Todos los participantes necesitan un UID/GID compatible y escritura en el
volumen para poder convertirse en el primer descargador. El lock es cooperativo:
los consumidores que comparten UID/escritura no están aislados entre sí. No se
guardan CFG locales, SQLite, logs de juego, demos, SSH ni artefactos BanSystem.
Los enlaces externos o archivos especiales en el payload se rechazan.

Para desactivar, deja `L4D2_VALVE_CACHE_VOLUME=` y recrea con el mismo Compose.
No es necesario eliminar el volumen ni cambiar una instalación ya preparada.

## Validación

`bash scripts/test-stack.sh` incluye fixtures de payload mínimo, concurrencia de
cuatro procesos sin juegos reales, SIGKILL, descarga fallida, copia interrumpida,
integridad, preservación de destinos y selección de la ruta del instalador.
Los tests de Compose verifican la activación opcional y la configuración heredada.
Estas pruebas no sustituyen una descarga real de Valve ni aceptación de gameplay.

El smoke opcional usa un volumen desechable y dos contenedores sin red, con
SteamCMD simulado y la lógica candidata montada en solo lectura. Comprueba Make,
permisos reales de linuxgsm, montaje, concurrencia entre namespaces y validación:

```bash
python3 scripts/test_valve_cache_docker.py \
  --image ghcr.io/aoc-gamers/lgsm-l4d2-aoc:develop
```

Exige una imagen local existente, no descarga imágenes ni arranca juegos. Elimina
solo sus contenedores y su volumen de fixture, identificados por un UUID único.
No equivale a construir o aceptar la cadena de imágenes nueva.
