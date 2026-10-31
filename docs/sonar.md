# Sonar manual y ShellCheck

## Interfaz del host

El esquema sigue a [BanSystem-Backend](https://github.com/AoC-Gamers/BanSystem-Backend) y [Connect-Core](https://github.com/AoC-Gamers/Connect-Core): `Makefile`, `scripts/make_sonar.py`, helpers de evidencia y `sonar-project.properties` por repositorio. Las fuentes de esos proyectos no se modifican. Los helpers adaptados conservan recibos de tarea/analysisId, verificación de identidad de fuentes, paginación completa y protección de credenciales.

Sonar se ejecuta **manualmente**, sin job Sonar en GitHub Actions. Requiere Python 3.10+, Make, Git, SonarScanner CLI (verificado 8.1.0) y ShellCheck (verificado 0.11.0) en el host. Ejecutar `make quality-setup` antes de `make test`, `make sonar-tooling-test` o `make sonar`; las dependencias se instalan en la venv local. No requiere Docker para analizar ni inicia juegos, contenedores, SteamCMD o compilaciones.

```bash
cp .env.sonar.example .env.sonar
chmod 600 .env.sonar
# Completar SONAR_TOKEN localmente, sin pegarlo en el chat ni en Git.
make quality-setup
make python-coverage
make sonar-tooling-test
make shellcheck
make sonar
make sonar-issues
make sonar-hotspots
make sonar-coverage
make sonar-duplications
```

`SONAR_HOST_URL=https://sonar.aoc-gamers.com` y `SONAR_TOKEN` se leen únicamente del entorno o `.env.sonar`, con prioridad del entorno y sin ejecutar dotenv como shell. `.env.sonar` está ignorado por Git y Docker. No colocar estas credenciales en `.env.secrets`, porque Compose lo inyecta al gameserver. Los comandos no crean proyectos, tokens ni modifican hotspots; esa preparación administrativa es independiente. El flujo completo usa un token de usuario con Browse y Execute Analysis en los proyectos (igual que BanSystem/Connect). Un PROJECT_ANALYSIS_TOKEN puede enviar el análisis, pero no consultar project_analyses/search: no sirve por sí solo para verificar recibos y exportar reportes. En esta instalación se reutilizó la credencial local existente de BanSystem; no se crearon usuarios ni se ampliaron permisos y se revocaron los tokens de análisis provisionales.

## Community Build y develop

Servidor verificado: Community Build 26.3.0.120487. Los tres proyectos se crearon privados. Cada repositorio tiene un proyecto independiente con su mismo nombre y `develop` como rama principal en Sonar. El comando rechaza analizar otro checkout. No enviar `sonar.branch.name` ni parámetros de PR: Community admite una sola rama. No mezclar análisis de main y develop en un mismo proyecto.

Docker (también `Dockerfile.dev`), Python y detección de secretos tienen analizadores disponibles. Bash, YAML/Compose y JSON no tienen análisis nativo de lenguaje en esta instalación. El scanner analiza el checkout actual: las capas heredadas se revisan en el proyecto padre; no se descarga ni escanea su filesystem. Se excluyen recursos, temporales, reportes y documentación del análisis; tests se clasifican por separado.

`make sonar` ejecuta ShellCheck y las pruebas offline existentes con cobertura de líneas y ramas, después envía el XML y espera Compute Engine/Quality Gate. Las pruebas se ejecutan una sola vez por análisis. `make python-coverage` mide sin acceder a Sonar ni requerir credenciales. Un gate rojo devuelve error conservando diagnósticos, sin ocultar hallazgos ni desactivar reglas. Revisar el hotspot de root con [bootstrap API 2](bootstrap-security.md): root sigue siendo necesario para preparación administrativa/OpenSSH; los juegos trabajan sin privilegios. No marcarlo seguro automáticamente.

## Evidencia y cobertura

Los resultados están en `reports/`, ignorado por Git/Docker: `sonar-run.json`, `sonar-quality-gate.json`, `sonar-issues.json`, `sonar-hotspots.json`, `sonar-coverage.json` y `sonar-duplications.json`; cada ejecución conserva tarea/log en `reports/sonar-runs/<id>/`. Las exportaciones rechazan recibos ajenos, fuentes cambiadas o un análisis posterior y no publican páginas parciales.

`make quality-setup` prepara una venv ignorada en `tmp/quality-venv` con coverage.py 7.17.0; no instala dependencias en las imágenes. `make sonar` genera cobertura real con las suites offline y la importa mediante `sonar.python.coverage.reportPaths`. `.coveragerc` incluye todo el Python propio, incluso archivos nunca ejecutados, y solo omite los tests y directorios generados que ya estaban fuera del scope de fuentes de Sonar. No se agregan pragmas ni exclusiones de producto, ni se cambian umbrales del gate.

Los procesos Python lanzados por Bash reciben un `sitecustomize` temporal que inicia coverage.py; cada proceso escribe datos separados y se combinan al terminar. La instrumentación solo existe en el entorno de las pruebas, sin modificar la instalación Python global. Las copias de código en fixtures temporales no se atribuyen artificialmente al original: las rutas originales no ejecutadas permanecen sin cubrir. La prueba de subprocess del colector comprueba que las líneas ejecutadas por un hijo real aparecen en el XML.

Cada medición vive en `reports/python-coverage/<id>/` con datos, XML Cobertura, JSON de líneas/ramas y log; `reports/python-coverage.json` vincula hash de fuentes y XML. `reports/coverage.xml` es la copia visible para el scanner; el flujo manual usa explícitamente el XML único de esa ejecución y verifica su hash antes/después del análisis y al exportar. El inventario XML debe coincidir con todos los archivos Python propios del scope actual. Un fallo de tests, cambio de fuentes, XML incompleto/ajeno o modificado impide publicar el recibo. `sonar-coverage` consulta las medidas aceptadas por Sonar. Distinguir siempre cobertura total y nueva del gate. Las pruebas offline no sustituyen carga de extensiones ni gameplay.

## Verificación de esta implementación

La medición completa local alcanzó 85,9 % en Competitive (21 archivos Python propios) y aproximadamente 97,7 % en AoC y Vanilla, contando líneas y ramas y con cero líneas excluidas por coverage.py. Son medidas de las pruebas offline, no de un gameserver ejecutándose. Los gates deben contrastarse con el análisis vigente en el servidor: `reports/sonar-quality-gate.json` conserva las condiciones reales.

## ShellCheck en CI

La publicación mantiene `validate → image-test → build-and-push`. `validate` instala ShellCheck y ejecuta `scripts/shellcheck.sh`: scripts propios versionados y nuevos no ignorados, Bash, severidad warning (incluye errores). Fallos bloquean la construcción/publicación. No se analiza código descargado de Valve, LinuxGSM ni plugins externos. Las excepciones se documentan en líneas concretas: parámetros/variables del contrato compartido (SC2034), glob intencional (SC2053), dotenv dinámico (source=/dev/null) y listas intencionales de un archivo (SC2066); no hay exclusiones globales de reglas.

Referencias: [Community y ramas](https://docs.sonarsource.com/sonarqube-community-build/feature-comparison-table), [lenguajes](https://docs.sonarsource.com/sonarqube-community-build/analyzing-source-code/languages/overview), [ShellCheck](https://github.com/koalaman/shellcheck).

CI instala coverage.py solo en el runner de validación para probar el colector. Las pruebas heredadas dentro de imágenes usan `scripts/test-stack.sh --runtime-only /app`: mantienen los fixtures operativos sin requerir herramientas de Sonar en las imágenes. La validación del host y `make sonar` ejecutan también todas las pruebas del tooling; Sonar continúa fuera de CI.
