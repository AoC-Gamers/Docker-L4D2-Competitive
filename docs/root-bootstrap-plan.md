# Reducción de privilegios — implementación y aceptación

Estado al 2026-10-30: implementación, aceptación local, publicación en `develop` y recreación de AoC/Vanilla con imágenes publicadas completadas. Los datos actuales se conservaron. Esta aceptación técnica no declara una prueba de partida con jugadores.

## Contrato implementado

1. Bootstrap/supervisor protegido en Competitive; root limitado a identidad, preparación administrativa y OpenSSH. Código mutable de `/app` y `/data` no se ejecuta como root.
2. Runtime, instalador, hooks y juegos como linuxgsm, sin sudo, sin capacidades y con `no_new_privs`. Las sesiones SSH aplican NNP; su bounding set conserva el de la sesión, sin capacidades efectivas.
3. Claves SSH en un volumen protegido separado, con migración de las huellas existentes. Preparación de volúmenes sin chown general en cada inicio; conservación del SDK read-only, SGID y grupo BanSystem.
4. Apagado de todas las instancias y persistencia de la selección activa. AoC y Vanilla heredan el supervisor; AoC declara su grupo suplementario en JSON protegido.
5. Documentación y archivos `AGENTS.md`/`CONTEXT.md` en los tres proyectos, con referencias a los padres y límites del entorno local.

El detalle del contrato está en [bootstrap API 2](bootstrap-security.md).

## Evidencia de aceptación

Evidencia local ignorada: `tmp/root-bootstrap-20261029/`. Competitive: 143 pruebas offline OK. AoC: 17 pruebas OK y un skip existente. Vanilla: 6 pruebas OK. Construcción local de las tres imágenes, SSH por clave/contraseña y SFTP reales, sesiones con UID 1000/NNP1 y ausencia de sudo verificados. Remapeo UID/GID 2000, grupo compartido 10001, archivos 0660 y SDK read-only también verificados.

Antes de que el usuario limitara los recursos del notebook se probaron seis SRCDS reales sobre una única instalación Valve: respuesta UDP en 28101..28106, 134 plugins por instancia y extensiones nativas requeridas sin fallos. Apagado exit0 y reanudación automática de seis con capacidades efectivas/bounding vacías y NNP1. La selección parcial 1/3/4/6 se conservó, con 2/5 detenidas. Seis SQLite canary conservaron hash, inodo y propietarios tras ambos reinicios. Las huellas SSH originales se conservaron y las claves legacy/protegidas quedaron inaccesibles al juego. Los fixtures cubren doce instancias sin lanzar doce juegos.

El máximo local actual es **DOS gameservers reales simultáneos en todo el notebook**, contando AoC y Vanilla. No repetir la prueba de seis. Se retiraron el laboratorio y todos sus volúmenes propios; permanecen los informes, sin copia adicional de Valve.

## CI y publicaciones verificadas

Cada workflow tiene tres jobs: `validate`, `image-test` y `build-and-push`. El último requiere los dos anteriores y recibe su padre exacto; las derivadas prueban también el instalador heredado. El smoke verifica SSH/SFTP sin arrancar SRCDS. Se publica provenance/SBOM y el artefacto `build-identity` con revisión, padre y digest. La cadena de dispatch transmite el digest publicado, sin volver a resolver etiquetas entre padre e hija. El scope `workflow` de GitHub CLI se autorizó para publicar esta estructura.

| Imagen | Revisión construida | CI exitoso | Digest publicado |
|---|---|---|---|
| Competitive | `8489370307ce7a7649549eb9264356af7303172a` | [40993720996](https://github.com/AoC-Gamers/Docker-L4D2-Competitive/actions/runs/40993720996) | `sha256:c590d4df57555cca574cea3b6bd7d24eee2e444e2e5d82baba17585d59e1817e` |
| AoC | `4ae1f8eef071bf47d9464d5c1f77cd6b43aa970b` | [40994313891](https://github.com/AoC-Gamers/Docker-L4D2-AoC/actions/runs/40994313891) | `sha256:3af315fd98f808acf49ec08581008c337e45e7bc7688e74262812402cb08fbb2` |
| Vanilla | `eca4a2491b2b8f8691166bffd54d2f9ac291001f` | [40994838493](https://github.com/AoC-Gamers/Docker-L4D2-AoC-Vanilla/actions/runs/40994838493) | `sha256:bef9f3c0d11fcb92153d15a67aa4c3be7d7bfbd75ac99e12fb48111d8b26826a` |

Competitive usa `gameservermanagers/linuxgsm@sha256:dc42bda96f62345644d07ff30f2d9dba27262a1d80499149185071cef402d1b6`. El padre registrado por AoC coincide con el digest Competitive de la tabla; el de Vanilla coincide con el digest AoC. Los commits posteriores de documentación con `[skip ci]` no requieren reconstruir estas imágenes.

## Servicios locales sobre las imágenes publicadas

Se recrearon secuencialmente con sus respectivos `docker-compose.dev.yml`, seleccionando los digests anteriores en `.env`. `BASE_IMAGE` también quedó fijado al padre correspondiente para futuras construcciones locales. Las credenciales GHCR temporales se retiraron tras la descarga.

| Servicio | Estado | Juego / SourceTV / netconsole / SSH | Plugins / extensiones | Volumen de datos |
|---|---|---|---|---|
| AoC (`competitive_dev`) | healthy, un SRCDS | 27015 / 27115 / 27215 / 4231 | 134 / 26 | `data_aoc_develop` |
| Vanilla (`vanilla_dev`) | healthy, un SRCDS | 27016 / 27116 / 27216 / 4232 | 128 / 26 | `data_aoc_vanilla_develop` |

Los puertos de juego, SourceTV y netconsole son valores de las instancias locales, no variables globales de Compose. Ambos juegos responden por UDP y ejecutan UID 1000, grupo suplementario 10001, NNP1 y capacidades efectivas/bounding vacías. Autocomplete, Custom Fakelag, Journal ELF32, SourceTV Support y SteamWorks cargaron sin errores. Las 35 dependencias obligatorias y sus archivos se verificaron en modo de solo lectura. Toolchain observada: GCC/G++ 15.2.0, Clang 21.1.8, Python 3.14.4 y glibc 2.43, sobre Ubuntu 26.04.

Antes/después se compararon identidades de todos los montajes, hashes de los CFG LinuxGSM locales, huellas SSH y metadatos de los SQLite encontrados, sin diferencias. Se conservaron los volúmenes de artefactos BanSystem y los volúmenes SSH `data_aoc_develop_ssh` / `data_aoc_vanilla_develop_ssh`. SSH por contraseña, NNP de la sesión, grupo compartido, inaccesibilidad de claves y SFTP escribir/leer/borrar pasaron en ambos servicios publicados. La shell operativa documentada también se ejecutó como linuxgsm con NNP1.

## Mejoras independientes pendientes

Coordinar el actualizador Valve compartido, fijar revisiones de módulos LinuxGSM, separar toolchains mediante multi-stage y evaluar SSH en un servicio separado. No forman parte de esta implementación ni se declaran probadas. La imagen conserva root para la administración y OpenSSH; las instancias que comparten UID no constituyen fronteras de seguridad entre sí.

Referencias: [LinuxGSM](https://github.com/GameServerManagers/docker-linuxgsm), [SteamCMD](https://github.com/GameServerManagers/docker-steamcmd), [Ubuntu](https://hub.docker.com/_/ubuntu), [no_new_privs](https://www.kernel.org/doc/html/latest/userspace-api/no_new_privs.html).
