# Auditoría iterativa de los flujos — 2026-10-11

Tres subagentes GPT-6 Luna con razonamiento alto implementaron las correcciones
y evaluaron después flujos distintos de los que habían corregido. El coordinador
contrastó reproducciones, adjudicó los hallazgos y ejecutó las suites completas.
Se repitieron corrección y evaluación hasta cerrar los casos reproducibles de los
flujos soportados. La última revisión cruzada no detectó issues adicionales.

Se resolvieron **9 issues: 8 defectos funcionales y 1 de contrato/documentación**.
Las variantes descubiertas de un mismo defecto, como el modo de la raíz del
archivo expandido, no se cuentan nuevamente.

| ID | Hallazgo confirmado | Corrección y regresión |
|---|---|---|
| 01 | `FALSE`, `NO` y `OFF` podían permitir reanudar instancias | Interpretación booleana sin distinguir mayúsculas en publicación e intención runtime; pruebas de variantes aceptadas |
| 02 | Un corte después del commit podía dejar `failed` pese a recuperar correctamente | Journal asociado al deployment y a su propietario; cubre cortes antes/después del reconocimiento de reanudación, fallos al arrancar, dueño padre y recibos antiguos |
| 03 | Crear una ruta privada anidada podía atravesar un padre simbólico externo | Validar padres antes de crear o aceptar la ruta; conservar enlaces externos, sus bytes y las excepciones canónicas verificadas |
| 04 | La caché de expansiones ignoraba permisos y directorios vacíos | Identidad filesystem versionada, incluida su raíz; reparación desde el original persistido, sin romper hashes históricos de pins ni depender de timestamps |
| 05 | Migrar legacy podía renombrar archivos externos a través de padres del origen o de una raíz destino simbólica | Rechazo antes del rename; pruebas repetidas de conservación de bytes e inodos |
| 06 | `--migrate-all` movía datos antes de validar un origen SourceMod simbólico | Preflight del origen físico antes de cualquier migración; regresión del CLI real repetida |
| 07 | Recovery podía sustituir el perfil registrado con el del entorno del comando | Actualizar solo estado, error y fecha del deployment confirmado; preservar metadatos originales tanto en éxito como en error |
| 08 | Un rechazo podía marcar fallido un deployment ajeno; un candidato antiguo podía sobrescribir su árbol | Ownership antes de retry/rebuild y trap solo para operaciones reales de su deployment; comparar árbol, estado, journal y candidato sin cambios ante rechazo |
| 09 | «Sin hooks/red» ocultaba la repetición de la extensión `after-sync` | Contrato explícito de repetición e idempotencia; prueba de fallo de extensión, retry exitoso sin remoto Git y contador de hooks de componentes sin aumentar |

La implementación está en `source_identity.py`, `artifact_cache.sh`,
`instance_layout.py`, `deployment_transaction.sh`, `transaction_stack.py`,
`runtime_intent.sh` y `recover_stack.sh`. Las regresiones están en
`test_archive_identity.py`, `test_instance_sync.py`, `test_runtime_coordination.py`,
`test_installer_flow.py` y `test_recovery_extensions.py`.

## Validación final

Desde cada repositorio en develop:

```bash
# Docker-L4D2-Competitive: 96 pruebas, OK; también sintaxis Bash.
bash scripts/test-stack.sh

# Docker-L4D2-AoC: 9 pruebas, OK; fixtures Bash del reconciliador, PASS.
bash scripts/test-stack.sh ../Docker-L4D2-Competitive

# Docker-L4D2-AoC-Vanilla: 6 pruebas, OK.
bash scripts/test-stack.sh ../Docker-L4D2-Competitive

git diff --check
```

Total: **111 pruebas**, sin contar nuevamente las pruebas focalizadas ejecutadas
por los revisores. Los fixtures usan directorios temporales, fuentes locales y
mocks; no requieren credenciales privadas ni descargar el servidor.

Se contrastaron caché/pins offline, composición y exclusiones heredadas,
preservación de configuraciones/datos, repetición, errores de preparación y
publicación, SIGKILL, locks por destino y operaciones anidadas, selección de
arranque, migración legacy y ejecución de extensiones.

## Adjudicaciones y límites

Un ancestro simbólico elegido explícitamente por el caller no constituye por sí
solo un escape de una ruta privada: no se prohibieron indiscriminadamente los
alias superiores de `/app`, `/data` o el destino. Sí se validan los enlaces
internos que podrían desviar una ruta particular o un rename legacy.

Un fixture colocó manualmente un journal schema 2 ajeno en `.stack-transaction`.
El historial muestra que el writer de esa ruta emitía schema 1 sin deployment ID,
mientras schema 2 se escribe en `state/publication`. No se encontró un flujo
soportado que produzca ese estado artificial y no se añadió una migración para
esa manipulación. No mover ni editar journals para forzar un reintento; revisar
el historial ante un estado incompatible y conservar candidato/evidencia.

No se ejecutaron SRCDS, builds de imágenes ni workflows remotos; tampoco se
recrearon contenedores ni se modificaron volúmenes reales. El healthcheck y el
actualizador de Valve no cambian. La ausencia de hallazgos en esta revisión no
equivale a validación de gameplay ni a una garantía ante cualquier corrupción
manual del estado.

Integrar y construir primero la base, luego AoC con su digest y finalmente
Vanilla con el digest de AoC. Las derivadas solo requieren las aclaraciones de
documentación de esta auditoría; heredan la implementación y mantienen sus
políticas y hooks. La [guía operativa](manual-publication.md) describe actualización,
reintento, rebuild y finalización de publicaciones invocadas por deploy.
