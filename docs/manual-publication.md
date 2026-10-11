# Publicación sin respaldos automáticos

El flujo normal conserva tres fases: obtener originales verificados, preparar y
validar el candidato, publicar. Se conserva la caché persistente bajo
`/data/installer/cache`; no se limpia el servidor durante las dos primeras fases.

## Rutas actuales y migración

| Ruta anterior | Comportamiento nuevo |
|---|---|
| `serverfiles/.stack-transaction` | Candidato/plan en `installer/state/publication/<hash-destino>` |
| `serverfiles/.stack-transaction.last` | No se genera; recibos legacy terminados se archivan fuera del juego |
| `addons/.instance-data/sourcemodN` | Datos devueltos por rename a `addons/sourcemodN`; se conservan inodos y contenido |
| `addons/sourcemodN.previous` / `.next` | No se generan; solo se retiran layouts legacy que no contengan archivos físicos |

La migración ocurre bajo el bloqueo del destino. No requiere borrar cachés ni
volúmenes. Los conflictos y archivos no identificados se conservan y detienen la
operación para revisión. Las instancias retiradas conservan configuración y
archivos particulares. `instances_exclude.json` y `preserve-paths.json` mantienen
su autoridad; los logs y datos vivos nunca se respaldan/restauran como estáticos.

Una publicación v1 interrumpida conserva su backup existente. El operador usa
`recover_stack.sh` una vez para restaurar ese legado y después ejecuta un
despliegue completo. Las publicaciones nuevas no crean backups.

## Fallo de publicación nueva

No hay rollback automático. Un error puede dejar una mezcla de versiones,
aunque el reemplazo de cada archivo individual utiliza un temporal y rename.
El estado queda fallido; un nuevo arranque detecta la publicación pendiente y se
detiene. Las instancias afectadas permanecen detenidas hasta la reparación.

Como usuario LinuxGSM, con el entorno del contenedor:

```bash
# Inspeccionar estado y progreso; corregir la causa (espacio, permisos, E/S).
jq '{status,last_error,recovery}' "$DIR_INSTALLER_STATE/current/deploy-state.json"
jq '{phase,resume_pending}' "$DIR_INSTALLER_STATE"/publication/*/journal.json

# Repetir el mismo candidato verificado: sin descargar ni ejecutar hooks.
bash "$DIR_INSTALLER_BIN/recover_stack.sh"

# Si falta material o cambió la lógica, abandonar explícitamente y preparar otra vez.
bash "$DIR_INSTALLER_BIN/recover_stack.sh" rebuild
STACK_REUSE_SOURCES=true bash "$DIR_INSTALLER_BIN/install_stack.sh" update
```

Rebuild restablece únicamente los recibos de procedencia de las fuentes a la
última selección confirmada, si una copia parcial había alcanzado esos recibos.
No restaura archivos operativos. Un reintento completo confirma la publicación,
sincroniza/reconcilia las instancias y respeta su selección de arranque y
`L4D2_AUTOSTART=false`. Tras confirmar se elimina el candidato y queda un recibo
pequeño. No borrar el candidato ni el progreso de una publicación pendiente.

## Caché y permisos

El bootstrap habilita ejecución solo para entrypoints conocidos. No modifica
recursivamente los permisos de `/data`, ZIP, fuentes ni cachés. Los checkouts
históricos alterados solo por chmod se normalizan si contenido/índice están
intactos y el commit coincide con el seleccionado. Una alteración real se rechaza
o provoca obtener de nuevo la fuente, según el modo solicitado.

El snapshot Git completo sigue verificándose. La caché preparada se identifica
por commit y contenido fuera de `.git`, evitando invalidaciones por transporte.
`install` y `update` conservan claves distintas: un hook puede comportarse de
forma diferente en cada modo. Cambios de lógica, recursos, entorno declarado o
capas anteriores también invalidan la preparación deliberadamente.

## Verificación de este cambio

- Base: `bash scripts/test-stack.sh`, 73 pruebas Python y sintaxis Bash.
- AoC: `bash scripts/test-stack.sh ../Docker-L4D2-Competitive`, 9 pruebas y fixtures Bash del reconciliador.
- Vanilla: el mismo comando, 6 pruebas.
- Contenedor desechable sin red, repositorio montado de solo lectura y `/tmp` efímero: 8 pruebas de sincronización, permisos y reutilización de caché.

Se cubren interrupciones por SIGKILL, fallos de copia, reintento sin hooks/red,
rechazo de candidatos modificados, migración legacy, conservación de inodos,
archivos privados y logs, retiro de instancias, exclusiones finales y caché.
No se recreó el contenedor del servidor ni se migraron sus volúmenes reales.
No se ejecutó SRCDS ni se construyeron/publicaron imágenes nuevas. El healthcheck
sigue comprobando SSH y estado administrativo; no mide disponibilidad SRCDS.

Integrar primero todos los commits de la base, luego construir AoC contra su
digest y finalmente Vanilla contra el digest de AoC. Las hijas solo actualizan
fixtures/documentación en este cambio; su comportamiento hereda la base.
