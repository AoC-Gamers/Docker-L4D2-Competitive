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

El [procedimiento operativo vigente](manual-publication.md) describe migración, reintento manual y las pruebas del flujo sin respaldos automáticos.
La [auditoría iterativa del flujo](flow-audit.md) registra nueve issues cerrados
y las 111 pruebas finales de base y derivadas, sin confundirlas con validación SRCDS.

El [flujo de artefactos persistentes](artifact-flow.md) documenta las tres fases actuales, el contrato de caché preparada y la limpieza del payload tras confirmar.

El instalador mantiene la arquitectura de componentes por capas. No duplica Valve: prepara solo archivos aportados por los componentes, configuraciones locales conservadas y recursos opcionales de propiedad comprobada. Los hooks reciben los cuatro argumentos históricos (`source_dir`, `install|update`, `source_download`, `source_type`), en workspaces independientes del cache bruto. Durante la composición todas las variables de destino (`LGSM_SERVERFILES`, `DIR_LEFT4DEAD2`, `DIR_ADDONS`, `DIR_SOURCEMOD`, `DIR_CFG`, `DIR_INSTALLER_STATE`) apuntan al candidato. Las eliminaciones AoC de cuatro bibliotecas `bin/` se declaran como operaciones diferidas, nunca se ejecutan contra el runtime desde el hook.

Fases del diario `state/publication/<hash-destino>/journal.json`:

| Fase | Significado | Tras interrupción |
|---|---|---|
| Sin diario / preparación | Descargas, snapshots, hooks, políticas, GeoIP y validación | El árbol operativo no se ha publicado |
| `prepared` | Plan validado, sin cambios operativos | Preparar nuevamente; conservar la selección de consumidores detenidos |
| `publishing` | Copia y sustitución de archivos | Estado fallido, instancias detenidas, reparación y reintento manual |
| `published` | Archivos aplicados; falta sync/reconciliación y commit | Mismo reintento manual desde el candidato retenido |
| `committed` | Publicación y reconciliación concluidas | Limpiar candidato; retomar solo la selección pendiente |
| `abandoned` | Operador solicitó reconstruir el candidato | Ejecutar install_stack; no arrancar consumidores antes de completar |

La publicación de varios archivos **no es atómica y no se restaura automáticamente**.
No se crean backups. Se conserva el candidato y se copia cada archivo a un
temporal del destino antes del reemplazo individual. El plan se escribe una vez;
el avance se persiste en un registro pequeño separado, evitando reescribir todo
el plan por archivo. Un fallo mantiene evidencia y bloquea el arranque normal.
`recover_stack.sh` es una operación manual que vuelve a publicar el material
verificado, sin ejecutar hooks de componentes ni descargar fuentes. La extensión
`after-sync` sí se repite: debe ser idempotente y puede realizar E/S o acceder a
la red según su implementación. La ruta ya no está dentro
de la instalación del juego. Para archivos temporales y destino se usa el mismo
filesystem; el estado puede estar en otro filesystem.

`deploy_stack.sh` conserva el orden del bootstrap del actualizador de Valve y difiere la reanudación de consumidores hasta después de esa fase. No se cambió el actualizador ni sus scripts. Un fallo de arranque posterior al commit deja el despliegue fallido y la publicación confirmada; no deshace archivos que ya pueden haber sido usados por consumidores.

Comandos dentro del contenedor, como el usuario LinuxGSM y con su entorno habitual:

```bash
# Actualización remota solicitada explícitamente; conserva la selección de instancias.
bash "$DIR_INSTALLER_BIN/install_stack.sh" update

# Reaplicar lógica local usando las últimas fuentes confirmadas compatibles.
STACK_REUSE_SOURCES=true bash "$DIR_INSTALLER_BIN/install_stack.sh" update

# Reintento del candidato, sin descargas de fuentes ni hooks de componentes.
bash "$DIR_INSTALLER_BIN/recover_stack.sh"

jq '{status,stack,last_error,recovery}' "$DIR_INSTALLER_STATE/current/deploy-state.json"
```

`recover_stack.sh` verifica el candidato y la identidad de la lógica, repite la
publicación y sincronización/reconciliación y confirma. Solo finaliza `ready` y
reanuda la selección anterior permitida cuando el recibo corresponde al mismo
despliegue y a una instalación directa. Las publicaciones invocadas por deploy,
las anteriores sin dueño explícito y las de otro despliegue requieren completar
`deploy_stack.sh`; no reanudan desde recovery. Un fallo no llega a `ready`.
Si falta material o cambió la
lógica, usar `recover_stack.sh rebuild` y después `install_stack.sh update`
(con `STACK_REUSE_SOURCES=true` para las fuentes fijadas disponibles). El rebuild
es una decisión explícita: conserva la selección anterior confirmada de fuentes
aunque se haya interrumpido la copia de sus recibos; no revierte archivos ya
instalados y mantiene las
instancias detenidas. Si se requiere una versión histórica concreta, seleccionar
su imagen y sus fuentes verificadas. No hay respaldo automático para restaurarla.

Los recibos legacy salen de `serverfiles` durante la migración. Una publicación
v1 pendiente conserva su backup hasta que el operador ejecute su restauración
compatible una sola vez; después debe instalar y validar el stack nuevamente.
No borrar esa evidencia ni interpretar un journal v1 como uno nuevo sin rollback.

Los switches `STACK_TEST_FAIL_PUBLISH_AFTER` y `STACK_TEST_KILL_PUBLISH_AFTER` son exclusivamente para fixtures temporales. No configurarlos en un servidor.

## Datos e instancias

`preserve-paths.json` y `instances_exclude.json` siguen siendo autoridad de conservación. Se instalan defaults de rutas preservadas que no existen en una instalación limpia. Los datos existentes de SourceMod, SQLite, dumps, chat, logs y el almacenamiento externo BanSystem no se copian al respaldo ni se restauran como archivos estáticos. Demos, mapas y archivos ajenos fuera de los árboles administrados permanecen fuera del plan.

Las configuraciones locales no registradas o distintas del último template se conservan. managed-files.json almacena hashes de templates, sin adoptar credenciales locales como defaults administrados. En la primera migración se conservan configuraciones existentes por prudencia. Las dos excepciones explícitas son cfg/sharedplugins.cfg y sharedplugins1.cfg: son cargadores administrados del stack y deben seguir el artefacto competitivo o retirarse en Vanilla. La política final elimina solo referencias exactas identificadas, incluso de un CFG local conservado. Los cambios de templates que entren en conflicto con ediciones locales requieren revisión administrativa; no se sobrescriben silenciosamente. Un enlace simbólico en un árbol estático cuya procedencia no pueda comprobarse provoca un fallo previo a publicar, conservando el servidor operativo.

La sincronización mantiene `sourcemod` como origen compartido y actualiza los enlaces de `sourcemodN` en su lugar. `logs` y el contenedor `data` son físicos dentro de cada instancia; las exclusiones de `instances_exclude.json` definen las rutas particulares. Los datos privados nuevos empiezan vacíos; los recursos compartidos siguen enlazados y las copias iniciales de configuraciones/plugins excluidos conservan el contrato previo. No se duplican ni restauran datos vivos.

La migración devuelve por rename los datos de `.instance-data/sourcemodN` al layout activo, sin copiar sus bytes ni cambiar sus inodos. Solo retira `.previous`/`.next` cuando contienen enlaces y directorios vacíos; ante archivos físicos no identificados o conflictos conserva el contenido y falla para revisión. Las instancias retiradas conservan CFG, logs y datos; únicamente se retira su ejecutable. No se crean nuevos `.instance-data` ni `.previous`. Las copias físicas estáticas no declaradas particulares siguen el origen compartido: se refrescan a enlaces y se retiran archivos obsoletos. Las configuraciones locales y los datos vivos conservan su política de preservación.

La coordinación utiliza los sockets UID de LinuxGSM (`<selfname>-<selfname.uid>`) y compatibilidad con sockets anteriores; consulta sesiones tmux únicamente en las operaciones de despliegue. Detiene y verifica solo las instancias que estaban ejecutándose, y reanuda solo esa selección. `L4D2_AUTOSTART=false` impide reanudar. La sincronización directa rechaza instancias activas. El menú automático delega esa coordinación al instalador; el update manual conserva su comportamiento de dejar las instancias detenidas.

`runtime_intent.sh` registra la selección al usar el menú y antes de apagar el contenedor, para retomarla tras recrearlo sin arrancar instancias detenidas deliberadamente. En la primera migración de un volumen anterior sin ese registro, no se adivina la intención: usar `menu_stack.sh start` (con rango cuando corresponda) para establecerla. Arranques/paradas externos al menú se vuelven a observar al detener el contenedor; SIGKILL del contenedor puede impedir esa captura final.

## Bloqueo

`deploy_stack`, `install_stack`, `sync_instances`, el menú y recuperación usan `flock` asociado al `realpath` del destino, no al perfil. El padre mantiene FD 8; un hijo solo lo reutiliza si el descriptor heredado corresponde al archivo normalizado y puede demostrar la posesión del bloqueo. No hay un booleano para saltárselo. El bloqueo se toma antes de archivar/modificar estado. Un error o muerte del proceso libera el descriptor; no quedan locks `mkdir` huérfanos.

Cachés de fuentes por perfil mantienen su propia exclusión mientras se preparan snapshots. Dos destinos pueden trabajar en paralelo; si comparten la misma caché por perfil, solo la preparación de esa caché se serializa. Cada destino independiente debe tener su propio directorio de estado. En procesos de contenedores distintos que compartan serverfiles, montar también un `STACK_LOCK_ROOT` común con el mismo UID; `/tmp` por contenedor no constituye un bloqueo entre contenedores.

Los nombres del workspace y la caché se generan sin añadir un salto de línea: el perfil `develop` usa `tmp/install_stack/develop`, `state/sources/develop` y `state/cache/develop.log`. El sufijo accidental de versiones anteriores (`develop_`) no era parte del nombre de la rama Git. Los guiones bajos que sí pertenecen al perfil, como `feature_test` o `develop_`, se mantienen.

Las carpetas y registros de caché antiguos se conservan; no se renombran ni fusionan automáticamente con los nuevos. Una reaplicación con `STACK_REUSE_SOURCES=true` reutiliza los snapshots fijados en `state/pinned-sources` mediante `state/source-lock.json`, independientes del nombre de esas carpetas. No requiere consultar fuentes remotas ni borrar la caché anterior. Una actualización remota explícita podrá poblar la nueva caché del perfil.

## Identidades y reaplicación

Se distinguen tres identidades:

- `stack.materialization_sha256`: bytes efectivos de bibliotecas, comandos, hooks, configuración del instalador, políticas y extensiones heredadas/derivadas, y recursos ZIP locales relevantes. Excluye mtimes, logs, cachés y secretos. Los cambios locales provocan reaplicación automática solo con autoupdate activado; con `false` quedan pendientes.
- `stack.resolved_components_sha256`: definición efectiva del perfil y sus overrides, distinta de las versiones descargadas.
- `source-lock.json` y `hook-assets.json`: commits Git efectivos, asset ID, SHA256 de contenido y checksum esperado cuando exista; snapshots verificados de fuentes y assets auxiliares consumidos por hooks.

La preparación obtiene las fuentes una vez y compone desde snapshots propios de esa corrida. Una reaplicación manual con `STACK_REUSE_SOURCES=true` reutiliza la última publicación confirmada compatible, no una descarga más reciente de un intento fallido. Un cache legacy de release sin identidad comprobable no se convierte en una actualización implícita: requiere restaurar fuentes verificadas o ejecutar una actualización remota explícita para establecer el lock inicial. Si falta o está corrupto un snapshot fijado, falla con una instrucción de restaurar caché o pedir una actualización explícita; no avanza canales silenciosamente. Un componente nuevo o una fuente deliberadamente distinta sí necesita su primera resolución.

En instalaciones existentes, `L4D2_STACK_AUTOUPDATE=false` omite toda adquisición, preparación y publicación automática del stack. No vuelve a instalar los paquetes cacheados ni aplica hooks o políticas de una imagen nueva. Este comportamiento sustituye la reaplicación automática con fuentes fijadas de versiones anteriores. La primera instalación sigue componiendo el stack, y una actualización manual sigue disponible:

```bash
# Consultar fuentes remotas y aplicar sus versiones actuales.
bash "$DIR_INSTALLER_BIN/install_stack.sh" update
# O reaplicar deliberadamente las fuentes confirmadas sin avanzar canales.
STACK_REUSE_SOURCES=true bash "$DIR_INSTALLER_BIN/install_stack.sh" update
```

Al omitir el instalador, `stack.profile`, `stack.materialization_sha256`, la definición resuelta y las identidades de componentes conservan lo instalado. `stack.automatic_apply_skipped=true` registra la omisión y `stack.pending` contiene perfil y hashes deseados cuando difieren. Reiniciar no adopta esos hashes pendientes. El estado previo debe ser `ready` y su definición archivada debe coincidir con su hash; si falta ese recibo o hubo un fallo sin publicación confirmada, ejecutar instalación/actualización manual. Tras una recuperación, también se acepta un diario v2 `committed` cuyo despliegue y huella coincidan con el estado anterior: deploy completa las fases de runtime pendientes antes de declarar `ready`, sin reinstalar componentes. Un diario incompleto, ajeno o con otra huella no habilita esa continuación. Una publicación incompleta mantiene su bloqueo y procedimiento de recuperación. El arranque conserva la sincronización de instancias, las extensiones de runtime, `L4D2_AUTOSTART` y el actualizador de Valve con sus controles propios.

GitHub: se comprueba `sha256` del componente o el digest SHA256 del asset anunciado por la API cuando está disponible, antes de extraer/publicar. Sin checksum esperado, el hash calculado solo registra identidad de contenido; no acredita autenticidad. Las fuentes hook-only registran sus assets descargados y conservan la caché persistente. La compilación experimental de SourceTV conserva sus mecanismos previos de caché/build; esta tarea no fija todas las dependencias transitivas de ese toolchain ni convierte su build en reproducible.

## Contrato de hooks y extensiones

`release_tag` identifica el artefacto; `branch` identifica la referencia Git y mantiene su fallback histórico para seleccionar hooks. El campo opcional `hook_variant` y `HOOK_VARIANT_<FOLDER>` seleccionan explícitamente otra variante sin cambiar el canal. `BRANCH_*` y `RELEASE_TAG_*` mantienen compatibilidad cuando no se declara una variante independiente. Un `release_tag=channel/develop` por sí solo no selecciona un hook develop. Se rechazan nombres, fuentes y checksums inválidos, carpetas duplicadas y componentes desconocidos.

Los hooks de componentes son obligatorios por defecto (`hook_required=true`, explícito en catálogos). `hook_required=false` declara una ausencia opcional. Se valida existencia y sintaxis antes de preparar/publicar. Un fallo de descarga, extracción o hook termina la preparación sin limpiar el árbol operativo. Los hooks deben limitar escrituras al candidato y a sus cachés declaradas; este contrato no es un sandbox contra un script malicioso con rutas absolutas codificadas.

Solo hay dos puntos de extensión síncronos: `container/extensions/after-sync.sh` y `idle.sh`, en ese orden del ciclo cuando corresponde. Reciben la fase como primer argumento y el entorno runtime. `after-sync` corre como LinuxGSM, después de sincronizar y antes de arrancar; un fallo impide confirmar la publicación. Puede repetirse durante recovery y debe tolerar repetición y ejecución parcial; no se garantiza exactamente una ejecución ni ausencia de E/S/red. `idle` corre en el entrypoint después de la fase de usuario, antes del `tail`. Si existe, su error es fatal para esa fase. `extension-policy.json` declara qué slots son obligatorios; ausentes y no declarados son opcionales. AoC declara ambos obligatorios y conserva los comandos del reconciliador/estado de espera. No se insertan líneas mediante grep/sed en scripts heredados.

Referencias del contrato: [sockets LinuxGSM](https://github.com/GameServerManagers/LinuxGSM/blob/master/linuxgsm.sh), [inspección de digest Docker](https://docs.docker.com/reference/cli/docker/buildx/imagetools/inspect/).

## Logs

### Bloques de tareas y diagnóstico de cargas

`section` identifica la fase y el componente; `subsection` imprime `--- <tarea> ---` para adquisición de fuentes, descarga/validación, extracción o reutilización, workspace editable, procesamiento por hook, copia, conservación de configuración, políticas finales, publicación y sincronización. Los originales y las expansiones reutilizados se identifican como tales; un acierto de caché preparada omite el bloque de procesamiento del hook. Los helpers que devuelven una ruta por stdout escriben estos subtítulos por stderr para no contaminar su resultado.

La conservación de configuración no se presenta como un backup: el flujo no crea respaldos automáticos de addons ni de bases de datos activas. Las dos aplicaciones de la política final tienen bloques distintos: después de componer componentes y después de conservar CFG locales. Son dos verificaciones del candidato, no dos ejecuciones del hook de un componente.

Después de componer todas las capas, conservar configuraciones y aplicar políticas, `validate_candidate.py` analiza las cargas explícitas `sm plugins load` de `cfg/sharedplugins.cfg` y `cfg/sharedplugins1.cfg`. Para cada binario ausente informa `WARN`, archivo, línea y ruta esperada en `addons/sourcemod/plugins`. No modifica CFG ni decide si la ausencia es intencional; el aviso no impide publicar. Admite comillas dobles, extensión `.smx` opcional, comentarios `//` y comandos separados por `;`. Una sintaxis de carga no reconocida pide revisión manual. No sigue cadenas `exec`, no descubre procesos ni comprueba carga efectiva en SourceMod. Las rutas absolutas, con `..`, con barras invertidas o enlaces simbólicos siguen fallando por seguridad del candidato.

El repositorio que publica el CFG debe corregir sus cargas y mantiene sus validaciones estrictas de empaquetado, dependencias externas, opcionales y exclusiones. Este diagnóstico runtime evalúa el candidato compuesto y no exige que todos los plugins pertenezcan al paquete AoC individual. No representa una prueba de disponibilidad de SRCDS.

### Exclusiones de artefactos

Los hooks deben usar `stack_remove_files_if_present <rutas...>` para exclusiones de archivos y `stack_remove_paths_if_present <rutas...>` cuando se permite retirar también directorios. Ambas funciones usan `stack_log_exclusion` y registran **cada ruta en cada invocación**, incluso si no existe o se reutiliza la caché:

```text
Excluded path from deployment: addons/sourcemod/plugins/example.smx (removed)
Excluded path from deployment: addons/sourcemod/plugins/example.smx (absent)
Excluded path from deployment: serverfiles/bin/libgcc_s.so.1 (deferred)
```

`removed` confirma el borrado en el árbol que recibe el hook; durante preparación es el candidato o workspace, no una confirmación de publicación en el servidor activo. `absent` significa que la política se aplicó y la ruta ya estaba ausente. `deferred` declara una retirada que el publicador transaccional ejecutará después; no prueba que haya ocurrido. `failed` se escribe por stderr con salida no cero si el helper no puede retirar el artefacto. El helper de archivos rechaza directorios reales y archivos especiales; ambos helpers retiran enlaces simbólicos sin recorrer su destino. Las rutas dentro de `DIR_LEFT4DEAD2` se muestran relativas a esa raíz; las del workspace conservan su ruta para distinguir el origen.

`final_policy.py` usa el mismo formato para todas sus rutas y añade `Excluded command from deployment: <comando> (<estado>; occurrences=<cantidad>)` para cada `exec` o `sm plugins load` excluido. Las políticas se ejecutan después de las capas y de conservar los CFG locales: una segunda línea `absent` es esperable. Los scripts autónomos, como el reconciliador BanSystem, respetan el mismo formato e identifican cada instancia mediante su ruta completa.

Los helpers `verify_and_delete_file/dir` se reservan para limpiezas explícitas. `stack_sync_file` reemplaza el archivo mediante la propia copia, sin eliminación previa separada ni mensajes de archivo ausente. Reemplaza el enlace de destino si existe, sin escribir en su objetivo; rechaza un directorio como destino de archivo. Las listas de exclusión y las políticas de conservación no cambian por este contrato de logs. Integrar primero la biblioteca base actualizada, después los hooks AoC y finalmente Vanilla.

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

Para actualizar un volumen existente: conservar sus backups operativos habituales, seleccionar la nueva imagen por digest, conservar perfil/overrides y montajes de recursos/BanSystem, y recrear el contenedor. Con autoupdate desactivado, el deploy conserva el stack instalado y deja la lógica nueva pendiente: ejecutar uno de los comandos manuales anteriores para aplicarla. Revisar `current/deploy-state.json`, `source-lock.json`, `state/publication/<hash-destino>/journal.json` y registros `.paths.unresolved`. Establecer la selección de arranque durante la primera migración si no hay `runtime-intent.json`. No usar `rsync --delete` sobre `/data` ni sobre Valve.

## Registro histórico de la entrega inicial

Este apartado conserva la evidencia de la revisión inicial. El ciclo vigente de publicación sin rollback y la migración posterior están descritos arriba y en `artifact-flow.md`; los conteos y limitaciones siguientes corresponden a aquella entrega.

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

Las 41 pruebas Python más los fixtures Bash cubren composición, migración/retirada repetida, rutas/symlinks inválidos, capas que reintroducen exclusiones, configuraciones/datos privados, preparación fallida por descarga/extracción/hook, fallos de publicación con reintento manual e interrupción SIGKILL, locks y llamadas anidadas, fuentes confirmadas/caché corrupta, huella independiente de timestamps/logs y hooks obligatorios. La equivalencia limpio/update compara árboles administrados, no datos mutables. El pipeline de empaquetado usa SMX ficticios para validar estructura; no demuestra ejecución ni compilación SourcePawn.

Además se descargaron los archivos oficiales SourceMod Linux y Windows para comprobar hashes reales frente a los digests de GitHub, y se resolvió el commit upstream real. Los tests normales usan mocks sin credenciales. El reconciliador de develop y sus propios fixtures también se ejecutaron aislados en un directorio temporal: PASS.

**No ejecutado:** build/pull/run de imágenes Docker, workflows en GitHub Actions, compilación completa SourcePawn/SourceTV, arranque SRCDS, ni migración real de volúmenes. Docker cliente/daemon 29.8.2 están disponibles: la limitación es que esta entrega no construyó la nueva cadena de imágenes ni preparó un servidor de juego desechable. Queda validar permisos/montajes reales, tamaño de staging/backups y smoke del juego en ese entorno antes de adoptar las imágenes. Tampoco se simula un corte eléctrico físico: se prueba la recuperación por SIGKILL y se usan fsync/renames; la durabilidad final depende del filesystem y almacenamiento.

**Límites operativos pendientes:** no se fijaron todas las dependencias transitivas experimentales de SourceTV; no hay GC automático de snapshots; symlinks estáticos no verificables y estado en filesystem independiente se rechazan; instancias gestionadas fuera de LinuxGSM/tmux no se coordinan automáticamente. Los hooks confiables siguen siendo Bash con permisos del usuario, sin sandbox de seguridad. La primera adopción con caché legacy sin identidad exige una actualización explícita o restaurar fuentes verificadas, y la primera selección de arranque debe establecerse con el menú si falta el registro de intención. La integración/publicación sigue pendiente de autorización y CI remoto.

Durante el trabajo aparecieron ediciones concurrentes ajenas a esta implementación: reconciliador BanSystem, su test y documentación de configuración/despliegue en Docker AoC, y README Vanilla. Se conservaron sin incluirlas en los commits propios. Los fixtures actuales también pasan; esa evidencia no atribuye esas ediciones a esta tarea.
