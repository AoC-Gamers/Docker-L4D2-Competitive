# Ubuntu 26.04 y artefacto local para AoC

La base es `gameservermanagers/linuxgsm:ubuntu-26.04`, para `linux/amd64`.
L4D2 y SteamCMD requieren tambien bibliotecas i386; el build conserva ambas
arquitecturas. Ubuntu 26.04 usa `7zip` y `7zip-rar`, que mantienen el comando `7z`.

## Dependencias de la imagen

`container/runtime-packages.txt` es el inventario comun del Dockerfile y del
bootstrap. Los paquetes se instalan explicitamente durante el build, sin ejecutar
`apt-get autoremove` despues. Los requisitos adicionales de LinuxGSM se consultan
en `ubuntu-26.04.csv`.

`container/bootstrap/dependencies_check.sh` consulta el estado instalado mediante
`dpkg-query` y comprueba que existan los archivos `.so` y `.so.*` declarados por
esos paquetes. Esto detecta tambien una biblioteca eliminada aunque su paquete
siga registrado como instalado.

- Sin argumentos: informa de los problemas y permite continuar el bootstrap.
- Con `--strict`: devuelve 1 si falta un paquete, un archivo de biblioteca o no
  puede verificarse el inventario. El Dockerfile lo ejecuta en este modo.
- Si todo esta presente: imprime `Libraries verified`.

El chequeo no instala, actualiza ni repara paquetes. No certifica el ABI de
extensiones, sus simbolos dinamicos ni su funcionamiento dentro del motor; esas
comprobaciones requieren las pruebas del servidor con su stack efectivo.

## Construir y exportar el artefacto

Desde Competitive:

```bash
mkdir -p tmp/ubuntu26
docker build --iidfile tmp/ubuntu26/competitive-image-id \
  -t l4d2-competitive:ubuntu-26.04 .
docker image save l4d2-competitive:ubuntu-26.04 \
  | gzip -1 > tmp/ubuntu26/competitive-ubuntu26.tar.gz
(cd tmp/ubuntu26 && sha256sum competitive-ubuntu26.tar.gz > SHA256SUMS)
```

El archivo comprimido permite transportar la imagen sin publicar en un registro.
En otro host, verifica `SHA256SUMS` y usa `docker image load -i` con ese archivo.
El ID de imagen identifica el contenido local; la etiqueta puede cambiar en una
reconstruccion. Para una base reproducible, pasa a `BASE_IMAGE` el digest exacto
resuelto para la etiqueta LinuxGSM 26.04 y registra ese digest con el artefacto.

## Consumir la imagen desde AoC

Los Dockerfiles de AoC ya aceptan `BASE_IMAGE`. Desde Docker-L4D2-AoC, utiliza el
Compose de desarrollo directamente y pasa el artefacto local como padre:

```bash
docker compose -f docker-compose.dev.yml build \
  --build-arg BASE_IMAGE=l4d2-competitive:ubuntu-26.04 l4d2
```

Para instalar desde cero conserva el volumen anterior y selecciona uno nuevo con
`DATA_VOLUME_NAME`. Usa el mismo valor en todas las operaciones posteriores del
entorno. Si tambien se necesita un almacen de artefactos BanSystem independiente,
selecciona `BANSYSTEM_ARTIFACT_VOLUME` nuevo y prepara ese volumen externo con el
GID configurado, siguiendo el contrato de AoC.

```bash
export DATA_VOLUME_NAME=data_aoc_ubuntu26
docker compose -f docker-compose.dev.yml up -d --no-build --pull never l4d2
```

El Compose existente conserva sus puertos, red y configuraciones. No puede
coexistir con otro contenedor que utilice esos mismos nombres o puertos. No uses
`down -v` para preparar esta instalacion ni reutilices el volumen antiguo si se
quiere probar un bootstrap limpio. Las credenciales permanecen en los archivos
locales de entorno de AoC y no forman parte del artefacto Competitive.

## Bibliotecas de Valve y comprobacion del gameserver

El inventario verifica las bibliotecas del sistema. Las copias antiguas de
`libstdc++.so.6` y `libgcc_s.so.1` de Valve pueden imponerse mediante
`LD_LIBRARY_PATH` y provocar errores `GLIBCXX` o `CXXABI` aunque los paquetes del
sistema esten completos. AoC ya declara cuatro retiradas de esas bibliotecas en
su hook transaccional. Verifica el resultado efectivo tras instalar y actualizar
Valve y comprueba `meta list`, `sm exts list` y los logs de arranque.

El Accelerator x86 antiguo distribuido en Rework marca `GNU_STACK` como
ejecutable, lo que glibc 2.43 rechaza al cargarlo. La composicion final normaliza solo
el binario con SHA-256
`e74fdebd0f0eafb721caf4f8fe96e1f5763d73e1cbb2f94a470017bffdc62b76`
mediante `patchelf --clear-execstack` en el candidato, despues de todos los
componentes y politicas finales. Asi se comprueba tambien la copia aportada por
una capa posterior como AoC y se repite la comprobacion al reutilizar caches.
Un binario distinto
que pida pila ejecutable produce un error y requiere revision. Los binarios que
ya usan pila no ejecutable se conservan. No se modifica la cache original ni se
habilitan pilas ejecutables globalmente.

El [enlace actual de Accelerator](https://github.com/asherkin/accelerator/blob/a4dbe6f97580f856ed7a2f8aace4da735ae6b9dd/AMBuildScript#L113)
ya utiliza `-z noexecstack`. La comprobacion de carga no sustituye una prueba de
generacion y procesamiento de crash dumps.

## Auditoria de extensiones del 29 de octubre de 2026

En el stack AoC de desarrollo instalado sobre Ubuntu 26.04 se revisaron 41
archivos ELF `.so`: ninguno presento dependencias dinamicas sin resolver en el
entorno del juego ni `GNU_STACK` ejecutable. La consulta del servidor registro
26 extensiones cargadas y ninguna en estado `FAILED`. Estas comprobaciones no
sustituyen pruebas funcionales con jugadores.

SourceTV Support y SourceTV Manager se descargan como fuentes Git y se compilan
en el instalador de AoC; sus binarios instalados coinciden con los paquetes de
su cache de compilacion. SteamWorks, Custom-Fakelag, Autocomplete y Journal
proceden de releases; sus binarios instalados coinciden con los ZIP consumidos.

Se probaron las fuentes locales en contenedores desechables de la misma imagen
Ubuntu 26.04, sin modificar los repositorios originales ni reemplazar binarios
del servidor:

| Proyecto | Fuente probada | Resultado de compilacion |
| --- | --- | --- |
| SteamWorks | develop `46e3ee0` | Compila sin cambios con Clang 21. |
| Custom-Fakelag | develop `55920c3` | GCC 15 falla por `template-id-cdtor` en `threadtools.h` del HL2SDK; compila manteniendo `-Werror` y degradando solo esa advertencia. |
| srcds-autocomplete | develop `3065658` | Mismo fallo del SDK y mismo ajuste comprobado con GCC 15. |
| BanSystem Journal | fuentes nativas de develop `af9bb6a` | GCC 15 rechaza las especificaciones de excepciones de `operator delete` en `smsdk_ext.cpp`; el adaptador debe compilarse con `-fno-exceptions`, conservando excepciones en el codigo propio de Journal. |

Los dos primeros proyectos con fallo no incorporan automaticamente `CXXFLAGS`
del entorno en su AMBuildScript: el ajuste debe integrarse explicitamente en la
configuracion de compilacion y condicionarse a GCC compatible. Sus opciones de
ayuda funcionan con Python 3.14 sin la adaptacion argparse de SourceTV.

Con ese ajuste aislado, Journal compilo en 32 y 64 bits. En cada arquitectura
pasaron 23 grupos de pruebas de almacenamiento/worker y 32 ciclos de
`dlopen`/metadatos/`dlclose`. El ensayo de modulo no ejecuta callbacks SourceMod
ni valida integracion en partida.

Las referencias remotas consultadas de SteamWorks, Custom-Fakelag y Autocomplete
coincidian con sus respectivos `channel/develop`. Custom-Fakelag mantiene
`channel/latest` en otro commit; no se debe promover ese canal como efecto
secundario de esta migracion.

No se detecto una necesidad de reemplazar estos releases por incompatibilidad
de carga con Ubuntu 26.04. Para producir futuros artefactos en esa distribucion
hay que adaptar los tres builds indicados y validar los candidatos dentro del
servidor antes de publicarlos. Las extensiones restantes suministradas por
SourceMod, Rework o AoC se comprobaron como binarios; esta auditoria no supone
haber recompilado sus fuentes ni comprobado que cada upstream este al dia.

La evidencia local y los candidatos quedan en
`tmp/extension-audit-20261029/`: inventario `runtime-libraries.json`, procedencia
`artifact-provenance.json`, logs de compilacion, parches experimentales y hashes
`candidate-binaries.json`. Este directorio esta ignorado por Git; los parches
son pruebas aisladas, no cambios publicados en los proyectos de extensiones.

## Candidatos de extensiones comprobados en AoC

Se aplicaron los ajustes de GCC a Custom-Fakelag y Autocomplete, condicionados
a GCC 14 o posterior. Journal compila solo para 32 bits: Makefile, manifiesto,
validacion del paquete y CI rechazan o dejan de generar la variante ELF64.
El adaptador SourceMod se compila sin excepciones; Journal las conserva.
AoC exige ahora el paquete Journal de una sola arquitectura.

Los tres binarios candidatos se instalaron con respaldo y reinicio del proceso
local, sin humanos conectados. Sus hashes coinciden con los archivos mapeados
por SRCDS. El listado muestra 26 entradas, ninguna `FAILED`; System2 sigue
ausente como dependencia opcional. La consola responde a las ConVars de ambas
extensiones y Tab muestra sugerencias de Autocomplete. Core reconoce Journal
con interfaz 5; SAN carece de contexto de servidor valido en esta instancia,
por lo que no se acredita una operacion real de sanciones. Los 40 ELF restantes
no tienen dependencias sin resolver ni pila ejecutable.

Pasaron 74 tests de contratos BanSystem, 23 grupos nativos Journal y 32 ciclos
de carga/descarga de modulo, los tests de Custom-Fakelag y 17 tests AoC, incluido
el ZIP compilado real y su reinstalacion desde cache. Los ZIP candidatos y
`SHA256SUMS` quedan en `tmp/extension-audit-20261029/artifacts-final/`. Los plugins
SMX existentes no se sustituyeron durante el ensayo de las tres extensiones.
