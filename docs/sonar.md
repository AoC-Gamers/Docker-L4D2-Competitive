# Sonar manual y ShellCheck

## Interfaz del host

El esquema sigue a [BanSystem-Backend](https://github.com/AoC-Gamers/BanSystem-Backend) y [Connect-Core](https://github.com/AoC-Gamers/Connect-Core): `Makefile`, `scripts/make_sonar.py`, helpers de evidencia y `sonar-project.properties` por repositorio. Las fuentes de esos proyectos no se modifican. Los helpers adaptados conservan recibos de tarea/analysisId, verificación de identidad de fuentes, paginación completa y protección de credenciales.

Sonar se ejecuta **manualmente**, sin job Sonar en GitHub Actions. Requiere Python 3.10+, Make, Git, SonarScanner CLI (verificado 8.1.0) y ShellCheck (verificado 0.11.0) en el host. No requiere Docker para analizar ni inicia juegos, contenedores, SteamCMD o compilaciones.

```bash
cp .env.sonar.example .env.sonar
chmod 600 .env.sonar
# Completar SONAR_TOKEN localmente, sin pegarlo en el chat ni en Git.
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

`make sonar` ejecuta primero las pruebas offline existentes y ShellCheck, después envía el análisis y espera Compute Engine/Quality Gate. Un gate rojo devuelve error conservando diagnósticos, sin ocultar hallazgos ni desactivar reglas. Revisar el hotspot de root con [bootstrap API 2](bootstrap-security.md): root sigue siendo necesario para preparación administrativa/OpenSSH; los juegos trabajan sin privilegios. No marcarlo seguro automáticamente.

## Evidencia y cobertura

Los resultados están en `reports/`, ignorado por Git/Docker: `sonar-run.json`, `sonar-quality-gate.json`, `sonar-issues.json`, `sonar-hotspots.json`, `sonar-coverage.json` y `sonar-duplications.json`; cada ejecución conserva tarea/log en `reports/sonar-runs/<id>/`. Las exportaciones rechazan recibos ajenos, fuentes cambiadas o un análisis posterior y no publican páginas parciales.

`sonar-coverage` consulta la cobertura disponible en el servidor; este cambio **no genera ni importa cobertura Python**. Una métrica ausente o cero no demuestra que las pruebas no existan. Los tests de subprocess no deben presentarse como cobertura medida de todo el runtime. Las pruebas offline tampoco sustituyen carga real de extensiones ni gameplay.

## ShellCheck en CI

La publicación mantiene `validate → image-test → build-and-push`. `validate` instala ShellCheck y ejecuta `scripts/shellcheck.sh`: scripts propios versionados y nuevos no ignorados, Bash, severidad warning (incluye errores). Fallos bloquean la construcción/publicación. No se analiza código descargado de Valve, LinuxGSM ni plugins externos. Las excepciones se documentan en líneas concretas: parámetros/variables del contrato compartido (SC2034), glob intencional (SC2053), dotenv dinámico (source=/dev/null) y listas intencionales de un archivo (SC2066); no hay exclusiones globales de reglas.

Referencias: [Community y ramas](https://docs.sonarsource.com/sonarqube-community-build/feature-comparison-table), [lenguajes](https://docs.sonarsource.com/sonarqube-community-build/analyzing-source-code/languages/overview), [ShellCheck](https://github.com/koalaman/shellcheck).
