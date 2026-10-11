# Artefactos persistentes y despliegue en tres fases

El instalador separa originales, preparación editable y publicación recuperable.
`docker compose down` seguido de `up` conserva la caché si se conserva el volumen
montado en `/data`. `down -v` elimina ese volumen y también sus datos y cachés.

## 1. Obtener las fuentes exactas

Se valida el manifiesto y la presencia de los hooks obligatorios antes de obtener
fuentes. Se resuelve cada rama/canal una vez y se registra la selección en
`prepared-sources.json`. La preparación consume esa selección, sin volver a
resolver canales móviles.

| Fuente | Selección e identidad | Acceso privado |
|---|---|---|
| `git` | Repositorio, rama y commit efectivo; snapshot con hash del árbol | Credential helper Git o agente SSH; sin credenciales en URL |
| `github_release` | Repositorio, tag, nombre/ID de asset, SHA-256 descargado y checksum esperado cuando existe | `github_token_env` o fallback GitHub existente |
| `archive` | URL directa y `sha256` obligatorio; `archive_name` opcional | Para releases privados GitHub, usar `github_release` |
| `hook_only` | Descargas declaradas en `prepare_downloads`, fijadas por nombre y hash | Mantiene el contrato de autenticación del helper correspondiente |

Los ZIP/tar descargados se conservan sin editar en
`/data/installer/cache/artifacts/<sha256>/<nombre>`. Los repositorios y los
snapshots previamente existentes siguen en `state/sources/<perfil>` y
`state/pinned-sources/<identidad>`. Los snapshots Git conservan `.git` porque
algunos hooks necesitan el commit o submódulos. La transacción referencia los
snapshots; ya no hace otra copia de ellos en `serverfiles`.

La identidad de un snapshot se calcula y verifica sobre su copia terminada,
antes de registrarlo. Los metadatos Git pueden cambiar durante mantenimiento
del original; un hash anterior a la copia no describe necesariamente los bytes
conservados. Un snapshot existente que no coincida sigue rechazándose: esta
verificación no acepta ni repara silenciosamente contenido corrupto.

Con `STACK_REUSE_SOURCES=true` se verifican y utilizan las últimas fuentes
**confirmadas**, sin consultar canales remotos. Así se mantiene
`L4D2_STACK_AUTOUPDATE=false`: una corrección local del instalador no actualiza
indiscriminadamente los componentes. Un snapshot o archivo original corrupto
produce un error, nunca una sustitución silenciosa por otra versión.

Una actualización explícita consulta el commit Git o los metadatos del release.
Cuando el checksum esperado coincide con los bytes conservados, no descarga de
nuevo el asset. Si el proveedor no publica un checksum y se solicita actualizar,
se descarga para determinar su contenido: ni una fecha ni un ID prueban por sí
solos igualdad de bytes. El hash calculado localmente registra identidad; no
prueba autenticidad. Las fuentes directas requieren actualizar deliberadamente
su checksum en el manifiesto para seleccionar otro contenido.

Ejemplo de archivo directo:

```json
{
  "folder": "mi_componente",
  "source_type": "archive",
  "url": "https://example.org/mi_componente.zip",
  "archive_name": "mi_componente.zip",
  "sha256": "REEMPLAZAR_POR_SHA256_REAL_DE_64_HEXADECIMALES",
  "hook_variant": "default",
  "hook_required": true,
  "prepare_cache": true,
  "prepare_env": ["MI_OPCION_NO_SECRETA"]
}
```

El ejemplo requiere sustituir URL y checksum por una fuente real verificada.
Los tokens permanecen en el entorno; no se ponen en URLs, claves de caché ni
recibos. Para una rama Git con `/` en el nombre, declarar `hook_variant`
explícitamente, independientemente de la referencia de descarga.

## 2. Preparar y validar

El archivo original se valida antes de extraerse. Su expansión sin modificaciones
se conserva bajo `cache/artifacts/expanded/`, identificada por hash del archivo y
del extractor. Se verifica su contenido antes de reutilizarla. Cada hook recibe
una copia editable en `cache/work/install_stack/<perfil>/<hash-destino>/`.
Dos destinos diferentes no comparten el workspace mutable.

Los hooks siguen recibiendo los cuatro argumentos históricos. Todos los alias de
destino apuntan al candidato, fuera del árbol operativo. No editar manualmente
los originales ni la caché preparada: los cambios persistentes se expresan en
hooks, recursos o configuración local conservada.

`prepare_cache: true` declara que el hook es determinista y solo materializa
archivos del candidato a partir de sus entradas declaradas. El valor por defecto
es **false** para mantener compatibles los hooks desconocidos. `prepare_env`
declara variables adicionales no secretas que influyen en su salida; se rechazan
nombres de credenciales. Un hook que usa estado externo, herramientas no
identificadas o rutas operativas debe dejar esta caché desactivada.

La clave incluye fuente exacta, componente resuelto, perfil, modo install/update,
huella de lógica efectiva (incluidos hooks heredados, bibliotecas, políticas y
recursos opcionales), variables declaradas y contenido/permisos del candidato
producido por las capas anteriores. Los timestamps no forman parte de la clave.
Cambiar una capa anterior puede invalidar capas posteriores: es necesario cuando
sus modificaciones dependen de lo previamente instalado.

La salida preparada vive en `cache/prepared/<componente>/<clave>/`: contiene
**solo archivos cambiados y borrados declarados por el resultado del hook**, con
hashes, permisos y recibos de exclusión. No duplica todo el candidato por cada
componente. Un acierto reproduce esos efectos en orden y omite copia del
workspace, extracción y ejecución del hook. Las exclusiones se imprimen también
al reutilizar la salida, identificadas con `[prepared cache]`.

Una caché incompleta o corrupta se reconstruye; se verifican todos sus archivos
antes de aplicar el primer efecto. Un error de E/S durante su reproducción
aborta la preparación, sin continuar desde una reproducción parcial. Un hook
fallido nunca confirma una entrada preparada. Se usan locks por entrada para
construir/reutilizarla, además del bloqueo del destino.

MetaMod y SourceMod declaran sus descargas mediante `prepare_downloads` (lista de
`{name,url}` en componentes `hook_only`). La primera fase obtiene los archivos;
la segunda los consume fijados. Los hooks antiguos no declarados siguen siendo
compatibles, pero sus descargas internas no se adelantan automáticamente.
SourceTV y SourceTV Manager mantienen sus comprobaciones y cachés específicas
de compilador, sistema, SDK y dependencias; no se omite el hook entero mediante
esta caché de composición.

Las políticas finales, conservación/mezcla de configuraciones, validación del
candidato y GeoIP se ejecutan después de componerlo, incluso si hubo aciertos de
caché. Las bases de datos y logs activos no se archivan como salida preparada.

## 3. Publicar, confirmar o recuperar

El candidato y el backup de publicación permanecen en
`/data/serverfiles/.stack-transaction`, en el mismo filesystem que el destino.
Esta carpeta no es la caché de descargas. Se conserva el mecanismo de diario,
parada de consumidores afectados, renames registrados, sincronización de
instancias y reconciliación BanSystem. La sustitución de varios archivos **no es
atómica**.

Un fallo de publicación restaura los archivos anteriores; un SIGKILL deja un
diario recuperable para la siguiente invocación. La comprobación de recuperación
al entrar es una condición de seguridad de la publicación, no un cuarto proceso
que deba ejecutar el operador. También sigue disponible `recover_stack.sh`.

Después de `committed` se eliminan `candidate/`, `sources/` y `backup/`; sobreviven
el diario/recibo y la selección de instancias. Si se interrumpe esa limpieza, la
siguiente entrada la completa. Nunca se elimina payload de una publicación
pendiente. La reanudación tiene su propia confirmación en el recibo
(`resume_pending`), de modo que una interrupción después del commit conserva la
selección pendiente. Una vez reanudada, esa selección no se vuelve a usar para
arrancar instancias detenidas posteriormente. Se respeta `L4D2_AUTOSTART=false`.

## Migración y operación

Integrar primero la base, después AoC con sus declaraciones de caché/descargas,
y construir Vanilla contra el digest de AoC actualizado. Vanilla hereda este
flujo; sus exclusiones finales siguen ejecutándose tras la composición.

Las fuentes fijadas y cachés antiguas se leen sin moverlas ni reinterpretarlas.
La primera preparación con la lógica nueva construye su caché. Los antiguos
releases extraídos siguen utilizándose con `STACK_REUSE_SOURCES=true`; su ZIP
original no puede recuperarse sin descargarlo. Una actualización remota explícita
establece el formato de original persistente. Los temporales viejos de `/app`
no se migran automáticamente ni se consideran confiables por su nombre.

Rutas configurables: `STACK_WORK_ROOT`, `STACK_ARTIFACT_CACHE` y
`STACK_PREPARED_CACHE`. Sus valores por defecto están bajo `/data/installer/cache`;
si se cambian, deben seguir en un montaje persistente para conservar el beneficio.
La carpeta transaccional sigue junto a `serverfiles`, independientemente de esos
overrides. No hay recolección automática de originales/snapshots/preparados:
conservar los referenciados por locks actuales/históricos; no borrar cachés ni
transacciones durante una ejecución. La retención automática queda fuera de este
cambio para evitar eliminar fuentes necesarias sin una política operativa acordada.

```bash
# Reaplicar con fuentes confirmadas y sin consulta remota de componentes.
STACK_REUSE_SOURCES=true bash "$DIR_INSTALLER_BIN/install_stack.sh" update

# Actualizar deliberadamente las fuentes remotas.
bash "$DIR_INSTALLER_BIN/install_stack.sh" update

# Recuperar publicación interrumpida, sin actualización de Valve.
bash "$DIR_INSTALLER_BIN/recover_stack.sh"
```

No cambia el actualizador de Valve ni el alcance del healthcheck: comprueba el
entorno de administración y el estado de despliegue previsto, **no** disponibilidad
SRCDS. Las pruebas offline usan fixtures temporales; no equivalen a ejecución
real de Docker, red privada o partidas.

Los fixtures usan el usuario efectivo que creó su directorio temporal. Esto
permite ejecutarlos también dentro de una imagen con UID root y `USER=linuxgsm`,
como hace CI, sin cambiar al propietario de los archivos ni alterar la política
de usuario del instalador real. Las pruebas de hooks heredados se comprobaron
además en contenedores desechables con esa combinación de UID y entorno; no se
montaron volúmenes de servidores ni se ejecutó SRCDS.
