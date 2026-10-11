# Fiabilidad del despliegue

## Referencia de la auditoría (2026-10-11)

Se consultó develop remoto, sin utilizar main. Ramas de trabajo: codex/stack-reliability.

| Repositorio | Commit develop |
|---|---|
| Docker-L4D2-Competitive | 4f4c90f181833baf56d1357fa02c756d37d66466 |
| Docker-L4D2-AoC | ba382210fdde0d9473d8c978c2cb5ab040132f9c |
| Docker-L4D2-AoC-Vanilla | efba8fcc1a2c7b62f007fad1eee49e25ca5ec25c |
| AoC-L4D2-Competitive | 89a79afe06a18bff2252de2e635e61ecd077ea9c |

Hallazgos confirmados en esos commits: registro opcional sin prefijo (ambos aoc.default.sh), exclusiones solo en fuentes Vanilla, carga raíz de source_keyvalues empaquetado en custom, limpieza antes de descargas/hooks (install_stack.sh), huella solo de componentes (deploy_stack.sh), bloqueo por perfil posterior al estado, dependencias móviles y caché sin identidad exacta, hook seleccionado por branch y padres por tag, parches textuales AoC, borrado de errors_*.log.

Ya corregido previamente: autenticación GitHub y diagnósticos por stderr, caché persistente SourceTV. Se conservan y ejecutan sus regresiones. La limpieza previa de plugins ya existía: no se atribuye el problema a acumulación general de SMX. El healthcheck existente supervisa SSH y, en AoC, estado del despliegue; no se amplía a SRCDS.

## Recursos opcionales

La biblioteca base overlay_stack.py es la única implementación para AoC y Vanilla. Registros JSON schema_version=2: rutas relativas a left4dead2 con prefijo sound/, models/ o addons/, subtree explícito y SHA256 por archivo. Se rechazan rutas absolutas, .. y enlaces simbólicos en archivo/ancestros. La retirada elimina solo archivos aún iguales al contenido registrado. Un archivo modificado localmente se conserva.

Los .paths antiguos no se reinterpretan como formato nuevo. La etiqueta determina el subárbol; solo se adopta propiedad si el ZIP disponible y el archivo instalado coinciden en contenido. El resto se conserva y queda en .paths.unresolved; el original pasa a .paths.migrated. Sin ZIP no se presume propiedad. Revisar manualmente esos registros antes de una limpieza adicional.

## Validación

Las pruebas offline usan directorios temporales y fixtures; no equivalen a una prueba en SRCDS. El healthcheck no representa disponibilidad de las instancias SRCDS.

## Preparación, publicación y recuperación

El [flujo de artefactos persistentes](artifact-flow.md) documenta las tres fases actuales, el contrato de caché preparada y la limpieza del payload tras confirmar.

El instalador mantiene la arquitectura de componentes por capas. No duplica Valve: prepara solo archivos aportados por los componentes, configuraciones locales conservadas y recursos opcionales de propiedad comprobada. Los hooks reciben los cuatro argumentos históricos (`source_dir`, `install|update`, `source_download`, `source_type`), en workspaces independientes del cache bruto. Durante la composición todas las variables de destino (`LGSM_SERVERFILES`, `DIR_LEFT4DEAD2`, `DIR_ADDONS`, `DIR_SOURCEMOD`, `DIR_CFG`, `DIR_INSTALLER_STATE`) apuntan al candidato. Las eliminaciones AoC de cuatro bibliotecas `bin/` se declaran como operaciones diferidas, nunca se ejecutan contra el runtime desde el hook.

Fases del diario `/data/serverfiles/.stack-transaction/journal.json`:

| Fase | Significado | Tras interrupción |
|---|---|---|
| Sin diario / preparación | Descargas, snapshots de fuentes, extracción, hooks, políticas, GeoIP, validación | El stack operativo no se ha publicado |
| `prepared` | Plan validado, sin renames de archivos operativos | Conservar árbol anterior y reanudar únicamente la selección registrada si se interrumpió la parada |
| `publishing` | Entradas registradas antes de cada rename | Restaurar entradas pendientes en orden inverso |
| `published` | Archivos aplicados, falta sincronizar/reconciliar y confirmar | Restaurar versión anterior y rehacer enlaces |
| `committed` | Publicación y reconciliación concluidas | No hay rollback automático pendiente |
| `rolled_back` | Archivos anteriores recuperados | Reintentar un despliegue completo validado |

La sustitución de varios archivos/directorios **no es atómica**. Cada entrada registra si existía antes de moverla a `backup/`; el diario y los renames se sincronizan a disco. El arranque siguiente toma el bloqueo y recupera una publicación interrumpida antes de resolver nuevas fuentes. No depende de un trap para SIGKILL. Si no se puede escribir el diario o restaurar un archivo (por ejemplo, por falta de espacio), se conserva la transacción y el despliegue no llega a `ready`. Liberar espacio y repetir la recuperación; no borrar el diario ni su backup. State y serverfiles deben estar en el mismo filesystem; se comprueba antes de parar instancias/publicar. Montajes independientes requieren mantener estas rutas en un volumen común.

`deploy_stack.sh` conserva el orden del bootstrap del actualizador de Valve y difiere la reanudación de consumidores hasta después de esa fase. No se cambió el actualizador ni sus scripts. Un fallo de arranque posterior al commit deja el despliegue fallido y la publicación confirmada; no deshace archivos que ya pueden haber sido usados por consumidores.

Comandos dentro del contenedor, como el usuario LinuxGSM y con su entorno habitual:

```bash
# Actualización remota solicitada explícitamente; conserva la selección de instancias.
bash "$DIR_INSTALLER_BIN/install_stack.sh" update

# Reaplicar lógica local usando las últimas fuentes confirmadas compatibles.
STACK_REUSE_SOURCES=true bash "$DIR_INSTALLER_BIN/install_stack.sh" update

# Recuperación sin red ni actualización de Valve, bajo el mismo bloqueo.
bash "$DIR_INSTALLER_BIN/recover_stack.sh"

jq '{status,stack,last_error,recovery}' "$DIR_INSTALLER_STATE/current/deploy-state.json"
```

`recover_stack.sh` restaura archivos y repara enlaces/reconciliación antes de reanudar. Mantiene `status=failed` hasta que un despliegue completo valide la definición pretendida: no declara `ready` con metadatos de un candidato fallido. En una fase `committed` no intenta revertir automáticamente una publicación ya consumida. Para volver a una versión confirmada anterior, seleccionar su imagen por digest, su perfil y sus fuentes verificadas, y ejecutar un despliegue completo. La base retiene una transacción `.last` para inspección; no es un sistema de backups del juego.

Los switches `STACK_TEST_FAIL_PUBLISH_AFTER` y `STACK_TEST_KILL_PUBLISH_AFTER` son exclusivamente para fixtures temporales. No configurarlos en un servidor.

## Datos e instancias

`preserve-paths.json` y `instances_exclude.json` siguen siendo autoridad de conservación. Se instalan defaults de rutas preservadas que no existen en una instalación limpia. Los datos existentes de SourceMod, SQLite, dumps, chat, logs y el almacenamiento externo BanSystem no se copian al respaldo ni se restauran como archivos estáticos. Demos, mapas y archivos ajenos fuera de los árboles administrados permanecen fuera del plan.

Las configuraciones locales no registradas o distintas del último template se conservan. managed-files.json almacena hashes de templates, sin adoptar credenciales locales como defaults administrados. En la primera migración se conservan configuraciones existentes por prudencia. Las dos excepciones explícitas son cfg/sharedplugins.cfg y sharedplugins1.cfg: son cargadores administrados del stack y deben seguir el artefacto competitivo o retirarse en Vanilla. La política final elimina solo referencias exactas identificadas, incluso de un CFG local conservado. Los cambios de templates que entren en conflicto con ediciones locales requieren revisión administrativa; no se sobrescriben silenciosamente. Un enlace simbólico en un árbol estático cuya procedencia no pueda comprobarse provoca un fallo previo a publicar, conservando el servidor operativo.

La sincronización migra por rename datos/logs/configs físicos particulares y exclusiones particulares a `addons/.instance-data/sourcemodN/`, y enlaza el layout activo a ellos. No copia datos vivos de la primaria a una instancia nueva. Los subárboles privados nuevos empiezan vacíos; los recursos estáticos compartidos siguen enlazados. Al reducir topología, esa ubicación conserva los datos privados de instancias retiradas. Su eliminación requiere una decisión administrativa separada.

La coordinación utiliza los sockets UID de LinuxGSM (`<selfname>-<selfname.uid>`) y compatibilidad con sockets anteriores; consulta sesiones tmux únicamente en las operaciones de despliegue. Detiene y verifica solo las instancias que estaban ejecutándose, y reanuda solo esa selección. `L4D2_AUTOSTART=false` impide reanudar. La sincronización directa rechaza instancias activas. El menú automático delega esa coordinación al instalador; el update manual conserva su comportamiento de dejar las instancias detenidas.

`runtime_intent.sh` registra la selección al usar el menú y antes de apagar el contenedor, para retomarla tras recrearlo sin arrancar instancias detenidas deliberadamente. En la primera migración de un volumen anterior sin ese registro, no se adivina la intención: usar `menu_stack.sh start` (con rango cuando corresponda) para establecerla. Arranques/paradas externos al menú se vuelven a observar al detener el contenedor; SIGKILL del contenedor puede impedir esa captura final.

## Bloqueo

`deploy_stack`, `install_stack`, `sync_instances`, el menú y recuperación usan `flock` asociado al `realpath` del destino, no al perfil. El padre mantiene FD 8; un hijo solo lo reutiliza si el descriptor heredado corresponde al archivo normalizado y puede demostrar la posesión del bloqueo. No hay un booleano para saltárselo. El bloqueo se toma antes de archivar/modificar estado. Un error o muerte del proceso libera el descriptor; no quedan locks `mkdir` huérfanos.

Cachés de fuentes por perfil mantienen su propia exclusión mientras se preparan snapshots. Dos destinos pueden trabajar en paralelo; si comparten la misma caché por perfil, solo la preparación de esa caché se serializa. Cada destino independiente debe tener su propio directorio de estado. En procesos de contenedores distintos que compartan serverfiles, montar también un `STACK_LOCK_ROOT` común con el mismo UID; `/tmp` por contenedor no constituye un bloqueo entre contenedores.

Los nombres del workspace y la caché se generan sin añadir un salto de línea: el perfil `develop` usa `tmp/install_stack/develop`, `state/sources/develop` y `state/cache/develop.log`. El sufijo accidental de versiones anteriores (`develop_`) no era parte del nombre de la rama Git. Los guiones bajos que sí pertenecen al perfil, como `feature_test` o `develop_`, se mantienen.

Las carpetas y registros de caché antiguos se conservan; no se renombran ni fusionan automáticamente con los nuevos. Una reaplicación con `STACK_REUSE_SOURCES=true` reutiliza los snapshots fijados en `state/pinned-sources` mediante `state/source-lock.json`, independientes del nombre de esas carpetas. No requiere consultar fuentes remotas ni borrar la caché anterior. Una actualización remota explícita podrá poblar la nueva caché del perfil.

## Identidades y reaplicación

Se distinguen tres identidades:

- `stack.materialization_sha256`: bytes efectivos de bibliotecas, comandos, hooks, configuración del instalador, políticas y extensiones heredadas/derivadas, y recursos ZIP locales relevantes. Excluye mtimes, logs, cachés y secretos. Los cambios locales provocan reaplicación aun con autoupdate desactivado.
- `stack.resolved_components_sha256`: definición efectiva del perfil y sus overrides, distinta de las versiones descargadas.
- `source-lock.json` y `hook-assets.json`: commits Git efectivos, asset ID, SHA256 de contenido y checksum esperado cuando exista; snapshots verificados de fuentes y assets auxiliares consumidos por hooks.

La preparación obtiene las fuentes una vez y compone desde snapshots propios de esa corrida. Una reaplicación con autoupdate desactivado reutiliza la última publicación confirmada compatible, no una descarga más reciente de un intento fallido. Un cache legacy de release sin identidad comprobable no se convierte en una actualización implícita: requiere restaurar fuentes verificadas o ejecutar una actualización remota explícita para establecer el lock inicial. Si falta o está corrupto un snapshot fijado, falla con una instrucción de restaurar caché o pedir una actualización explícita; no avanza canales silenciosamente. Un componente nuevo o una fuente deliberadamente distinta sí necesita su primera resolución.

GitHub: se comprueba `sha256` del componente o el digest SHA256 del asset anunciado por la API cuando está disponible, antes de extraer/publicar. Sin checksum esperado, el hash calculado solo registra identidad de contenido; no acredita autenticidad. Las fuentes hook-only registran sus assets descargados y conservan la caché persistente. La compilación experimental de SourceTV conserva sus mecanismos previos de caché/build; esta tarea no fija todas las dependencias transitivas de ese toolchain ni convierte su build en reproducible.

## Contrato de hooks y extensiones

`release_tag` identifica el artefacto; `branch` identifica la referencia Git y mantiene su fallback histórico para seleccionar hooks. El campo opcional `hook_variant` y `HOOK_VARIANT_<FOLDER>` seleccionan explícitamente otra variante sin cambiar el canal. `BRANCH_*` y `RELEASE_TAG_*` mantienen compatibilidad cuando no se declara una variante independiente. Un `release_tag=channel/develop` por sí solo no selecciona un hook develop. Se rechazan nombres, fuentes y checksums inválidos, carpetas duplicadas y componentes desconocidos.

Los hooks de componentes son obligatorios por defecto (`hook_required=true`, explícito en catálogos). `hook_required=false` declara una ausencia opcional. Se valida existencia y sintaxis antes de preparar/publicar. Un fallo de descarga, extracción o hook termina la preparación sin limpiar el árbol operativo. Los hooks deben limitar escrituras al candidato y a sus cachés declaradas; este contrato no es un sandbox contra un script malicioso con rutas absolutas codificadas.

Solo hay dos puntos de extensión síncronos: `container/extensions/after-sync.sh` y `idle.sh`, en ese orden del ciclo cuando corresponde. Reciben la fase como primer argumento y el entorno runtime. `after-sync` corre como LinuxGSM, después de sincronizar y antes de arrancar; un fallo impide confirmar la publicación. `idle` corre en el entrypoint después de la fase de usuario, antes del `tail`. Si existe, su error es fatal para esa fase. `extension-policy.json` declara qué slots son obligatorios; ausentes y no declarados son opcionales. AoC declara ambos obligatorios y conserva los comandos del reconciliador/estado de espera. No se insertan líneas mediante grep/sed en scripts heredados.

Referencias del contrato: [sockets LinuxGSM](https://github.com/GameServerManagers/LinuxGSM/blob/master/linuxgsm.sh), [inspección de digest Docker](https://docs.docker.com/reference/cli/docker/buildx/imagetools/inspect/).

## Logs

### Exclusiones de artefactos

Los hooks deben usar `stack_remove_files_if_present <rutas...>` para exclusiones de archivos y `stack_remove_paths_if_present <rutas...>` cuando se permite retirar también directorios. Ambas funciones usan `stack_log_exclusion` y registran **cada ruta en cada invocación**, incluso si no existe o se reutiliza la caché:

```text
Excluded path from deployment: addons/sourcemod/plugins/example.smx (removed)
Excluded path from deployment: addons/sourcemod/plugins/example.smx (absent)
Excluded path from deployment: serverfiles/bin/libgcc_s.so.1 (deferred)
```

`removed` confirma el borrado en el árbol que recibe el hook; durante preparación es el candidato o workspace, no una confirmación de publicación en el servidor activo. `absent` significa que la política se aplicó y la ruta ya estaba ausente. `deferred` declara una retirada que el publicador transaccional ejecutará después; no prueba que haya ocurrido. `failed` se escribe por stderr con salida no cero si el helper no puede retirar el artefacto. El helper de archivos rechaza directorios reales y archivos especiales; ambos helpers retiran enlaces simbólicos sin recorrer su destino. Las rutas dentro de `DIR_LEFT4DEAD2` se muestran relativas a esa raíz; las del workspace conservan su ruta para distinguir el origen.

`final_policy.py` usa el mismo formato para todas sus rutas y añade `Excluded command from deployment: <comando> (<estado>; occurrences=<cantidad>)` para cada `exec` o `sm plugins load` excluido. Las políticas se ejecutan después de las capas y de conservar los CFG locales: una segunda línea `absent` es esperable. Los scripts autónomos, como el reconciliador BanSystem, respetan el mismo formato e identifican cada instancia mediante su ruta completa.

Los helpers `verify_and_delete_file/dir` se reservan para limpieza temporal o sustitución de archivos durante una copia; esas operaciones no son exclusiones de política. Las listas de exclusión y las políticas de conservación no cambian por este contrato de logs. Integrar primero la biblioteca base actualizada, después los hooks AoC y finalmente Vanilla.

El update no elimina `errors_*.log`. El historial conserva los logs del instalador y los locks de fuentes por despliegue. Se proporciona `installer/lib/retain_error_logs.py` como política **opcional** para nombres diarios SourceMod: compresión tras dos días sin escritura y retención de 90 días, exigiendo antigüedad tanto de la fecha del nombre como del último write. Solo acepta errors_YYYYMMDD.log y su versión .gz, sin seguir symlinks. Por defecto muestra el plan; `--apply` lo ejecuta. Nunca la invoca install/update. Ajustar retención a la capacidad y exportación de evidencia del nodo antes de programarla. Un logrotate convencional por nombre diario no garantiza expiración si ese nombre no vuelve a escribirse; por eso se usa antigüedad explícita. Ejemplo de revisión: `python3 "$DIR_INSTALLER_LIB/retain_error_logs.py" "$DIR_SOURCEMOD/logs" --days 90`; repetir por cada directorio privado de logs que se desee incluir. Si una compresión se interrumpe, el .pending se conserva y el original permanece: revisar ese archivo antes de reintentar. La carpeta de snapshots de fuentes crece con identidades nuevas; no se recolectan automáticamente snapshots que puedan ser necesarios para recuperación.

## CI e integración propuesta

Los tres workflows Docker ejecutan sintaxis/fixtures antes de publicar. Los derivados ejecutan además sus fixtures contra el instalador de la imagen padre exacta. `latest` y `develop` siguen disponibles como conveniencia; cada construcción publica un tag `build-<run_id>-<attempt>`, digest, etiqueta del padre, procedencia y `build-identity.json`. El dispatch al hijo pasa `parent_image=repository@sha256:...`; un build manual sin argumento resuelve una vez el canal y fija su digest. El mismo SHA hijo puede producir imágenes distintas contra padres distintos, con identidades de ejecución distintas.

Orden de integración, sin ejecutar merges/publicaciones como parte de esta tarea:

Antes de la primera adopción, configurar la variable de repositorio GitHub `AOC_PAUSE_CHILD_DISPATCH=true` en la base y Docker AoC. Solo pausa la cascada; no cambia la construcción/publicación del padre. Los workflows anteriores de los hijos aún no aceptan parent_image ni la API nueva. Después de integrar los tres workflows y validar builds manuales ordenados con sus digests, retirar la variable para restablecer la cascada habitual. Esta tarea no modifica variables remotas.

1. Integrar y validar la rama completa de la base, y construir una imagen develop con la API nueva. Preparar también el artefacto AoC corregido (paths y cargas excluidas); el nuevo validador final rechazará un artefacto antiguo incoherente.
2. Integrar AoC-L4D2-Competitive y disponer de su artefacto develop corregido antes de probar la nueva imagen AoC sobre un volumen anterior.
3. Integrar Docker-L4D2-AoC y construir contra el digest exacto de la base nueva.
4. Integrar Vanilla y construir contra el digest exacto de AoC del paso anterior. No reconstruir hijos contra una API base antigua.
5. Validar las imágenes en volúmenes desechables. Solo después planificar la adopción en servidores; esta tarea no publica producción ni modifica sus volúmenes.

Para actualizar un volumen existente: conservar sus backups operativos habituales, seleccionar la nueva imagen por digest, conservar perfil/overrides y montajes de recursos/BanSystem, y recrear el contenedor. El deploy detecta la lógica nueva y recompone con fuentes confirmadas cuando autoupdate está desactivado. Revisar `current/deploy-state.json`, `source-lock.json`, `.stack-transaction/journal.json` y registros `.paths.unresolved`. Establecer la selección de arranque durante la primera migración si no hay `runtime-intent.json`. No usar `rsync --delete` sobre `/data` ni sobre Valve.

## Informe de entrega y evidencia

Todos los cambios se prepararon en ramas nuevas `codex/stack-reliability`, desde los commits develop indicados arriba. No se hicieron pushes, merges, publicaciones ni operaciones sobre volúmenes de servidores.

| Hallazgo solicitado | Comprobación contra develop y resultado |
|---|---|
| 3. Recursos opcionales | Ambos `aoc.default.sh` registraban rutas internas mediante `record_overlay_state`, mientras `cleanup_tracked_overlay` anteponía left4dead2. Confirmado; sustituido por biblioteca base con registro versionado, propiedad por contenido y migración conservadora. |
| 4. Vanilla | `sir.default.sh` excluía plugins en su workspace; `competitive_fix` posterior podía reintroducirlos. Confirmado; política final de destino, retirada de ambos CFG y comprobación de rutas efectivas tras sync. |
| 5. Carga/empaquetado | `plugin-package-map.json` ubicaba source_keyvalues en custom y sharedplugins lo cargaba desde raíz. Confirmado; ruta corregida y test negativo que reproduce el CFG anterior. También se confirmaron cargas activas de kicklimit/chatlog que AoC excluía; se comentaron con motivo de sustitución por BanSystem. |
| 6. Actualización parcial | `install_stack.sh` invocaba `prepare_update_cleanup` antes de `apply_stack_sources`. Confirmado; preparación independiente y publicación con diario recuperable, probado incluso matando el instalador. |
| 7. Reaplicación | `stack_requires_reapply` comparaba perfil/definición, sin bytes de hooks y políticas. Confirmado; huellas separadas de lógica, definición y fuentes; snapshots de última publicación confirmada. |
| 8. Bloqueo | Lock por perfil y operaciones de estado previas a adquirirlo. Confirmado; lock por realpath antes de cambios, heredado y verificado en llamadas anidadas. |
| 9. Dependencias e identidad | Fetchers usaban resolución móvil y caché no vinculada a un lock exacto. Confirmado; commits/hashes oficiales comprobados, clave CI dependiente del lock, identidad de artefacto y fuentes runtime. |
| 10. Canales/herencia | Hook derivado de branch y Dockerfiles con padres por tag. Confirmado; selección explícita independiente compatible y padre resuelto por digest en CI. vip_core Vanilla develop ya era una excepción estable; se conserva. |
| 11. Extensiones | Dockerfiles AoC insertaban comandos en scripts base mediante grep/sed. Confirmado; slots after-sync/idle declarados, obligatorios según política. |
| 12. Evidencia/logs | `prepare_update_cleanup` borraba errors_*.log. Confirmado; se elimina esa limpieza y se ofrece rotación opcional. Se incorpora CI offline y documentación. |
| Premisa de binarios acumulados | Descartada como explicación general: develop ya eliminaba subárboles SourceMod antes de aplicar componentes. Las correcciones abordan composición y publicación. |
| Correcciones previas | Diagnósticos/autenticación GitHub y caché SourceTV ya tenían solución y regresiones. Se conservaron; no se reemplazaron por cambios redundantes. |

Archivos principales por repositorio:

- **Base:** `installer/bin/{install_stack,deploy_stack,sync_instances,recover_stack,runtime_intent,menu_stack}.sh`, bibliotecas de transacción/locks/fuentes/políticas/validación, retención opcional de logs, entrypoints, Dockerfile, workflow, `installer/tests`, `scripts/test-stack.sh` y documentación. Los scripts del actualizador Valve y healthchecks no cambian.
- **Docker AoC:** `stack/hooks/aoc.default.sh`, catálogo con obligatoriedad de hooks, `container/extensions/{after-sync,idle}.sh`, `stack/extension-policy.json`, Dockerfiles, workflow, fixtures y `docs/reliability.md`. No se modifica mediante parches textuales el código heredado.
- **Vanilla:** hook AoC compartido, `stack/final-policy.json`, Dockerfiles, workflow, fixtures y `docs/reliability.md`. La lista exacta y motivos de exclusión están en ese documento.
- **Artefacto AoC:** `plugin-package-map.json`, `left4dead2/cfg/sharedplugins.cfg`, `dependencies.lock.json`, fetchers, staging/validador de artefacto, workflow, pruebas y `docs/build-system.md`.

Validación ejecutada en el host, con exit code 0:

| Directorio | Comando | Resultado |
|---|---|---|
| Docker-L4D2-Competitive | `bash scripts/test-stack.sh` | Sintaxis Bash y 31 pruebas offline |
| Docker-L4D2-AoC | `bash scripts/test-stack.sh ../Docker-L4D2-Competitive` | Sintaxis/JSON, 2 pruebas de composición y fixtures del reconciliador |
| Docker-L4D2-AoC-Vanilla | `bash scripts/test-stack.sh ../Docker-L4D2-Competitive` | Sintaxis/JSON y 2 pruebas de composición |
| AoC-L4D2-Competitive | `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts/tests -v` | 6 pruebas de dependencias, cargas y pipeline estructural |
| Los cuatro workflows modificados | `actionlint -shellcheck='' <workflows>` (1.7.12) | Sin diagnósticos; shellcheck no instalado |
| Los cuatro repositorios | `git diff --check` | Sin errores de whitespace |

Las 41 pruebas Python más los fixtures Bash cubren composición, migración/retirada repetida, rutas/symlinks inválidos, capas que reintroducen exclusiones, configuraciones/datos privados, preparación fallida por descarga/extracción/hook, rollback e interrupción SIGKILL, locks y llamadas anidadas, fuentes confirmadas/caché corrupta, huella independiente de timestamps/logs y hooks obligatorios. La equivalencia limpio/update compara árboles administrados, no datos mutables. El pipeline de empaquetado usa SMX ficticios para validar estructura; no demuestra ejecución ni compilación SourcePawn.

Además se descargaron los archivos oficiales SourceMod Linux y Windows para comprobar hashes reales frente a los digests de GitHub, y se resolvió el commit upstream real. Los tests normales usan mocks sin credenciales. El reconciliador de develop y sus propios fixtures también se ejecutaron aislados en un directorio temporal: PASS.

**No ejecutado:** build/pull/run de imágenes Docker, workflows en GitHub Actions, compilación completa SourcePawn/SourceTV, arranque SRCDS, ni migración real de volúmenes. Docker cliente/daemon 29.8.2 están disponibles: la limitación es que esta entrega no construyó la nueva cadena de imágenes ni preparó un servidor de juego desechable. Queda validar permisos/montajes reales, tamaño de staging/backups y smoke del juego en ese entorno antes de adoptar las imágenes. Tampoco se simula un corte eléctrico físico: se prueba la recuperación por SIGKILL y se usan fsync/renames; la durabilidad final depende del filesystem y almacenamiento.

**Límites operativos pendientes:** no se fijaron todas las dependencias transitivas experimentales de SourceTV; no hay GC automático de snapshots; symlinks estáticos no verificables y estado en filesystem independiente se rechazan; instancias gestionadas fuera de LinuxGSM/tmux no se coordinan automáticamente. Los hooks confiables siguen siendo Bash con permisos del usuario, sin sandbox de seguridad. La primera adopción con caché legacy sin identidad exige una actualización explícita o restaurar fuentes verificadas, y la primera selección de arranque debe establecerse con el menú si falta el registro de intención. La integración/publicación sigue pendiente de autorización y CI remoto.

Durante el trabajo aparecieron ediciones concurrentes ajenas a esta implementación: reconciliador BanSystem, su test y documentación de configuración/despliegue en Docker AoC, y README Vanilla. Se conservaron sin incluirlas en los commits propios. Los fixtures actuales también pasan; esa evidencia no atribuye esas ediciones a esta tarea.
