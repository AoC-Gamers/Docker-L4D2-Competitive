# Contexto — Docker-L4D2-Competitive

Este repositorio forma parte del stack L4D2 Ubuntu 26.04, con runtime i386 y múltiples instancias sobre datos compartidos.

## Lectura inicial

1. [README](README.md): uso y variables.
2. [Seguridad del bootstrap](docs/bootstrap-security.md): responsabilidades, compatibilidad y referencias.
3. [Fiabilidad](docs/reliability.md): publicación, recuperación y conservación del estado.
4. [Implementación raíz y aceptación](docs/root-bootstrap-plan.md): progreso y evidencia.

## Autoridades

- `Dockerfile`/`Dockerfile.dev` y `BASE_IMAGE`: padre y dependencias de construcción.
- `stack/manifests` + `stack/profiles`: composición, sin inventar componentes a partir de una imagen anterior.
- `/data/config-lgsm/l4d2server/<instancia>.cfg`: puertos y basepath por instancia.
- `/data/installer/state`: recibos, estado e intención de arranque; no editar journals para forzar aceptación.
- Bootstrap API 2 y supervisor: implementados únicamente en Competitive.
- `/var/lib/l4d2/ssh`: claves persistentes protegidas; `/data/ssh` es origen legacy de migración.

## Límites

El contenedor inicia una preparación administrativa como root y mantiene OpenSSH con privilegios; no es una imagen íntegramente non-root. Las instancias comparten UID y no son fronteras de seguridad entre sí. `healthy` administrativo no implica gameplay validado.

## Recursos del entorno local

El usuario limitó las pruebas del notebook a dos gameservers reales en total. La evidencia anterior de seis instancias se conserva, pero no debe repetirse. Contar también los servidores locales existentes antes de iniciar cualquier laboratorio.

## Herramientas de calidad

Ver [Sonar manual y ShellCheck](docs/sonar.md). Sonar se ejecuta desde el host mediante Makefile/scripts, exclusivamente contra develop; no integrarlo en CI sin solicitud del usuario. No iniciar juegos para validar estas herramientas.
