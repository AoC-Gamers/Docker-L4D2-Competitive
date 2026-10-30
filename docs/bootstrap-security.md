# Bootstrap API 2: privilegios, almacenamiento y herencia

## Cadena y referencias

Ubuntu 26.04 → SteamCMD → LinuxGSM → Competitive → AoC → Vanilla.

- [SteamCMD Docker](https://github.com/GameServerManagers/docker-steamcmd), [Dockerfile](https://github.com/GameServerManagers/docker-steamcmd/blob/main/Dockerfile), [entrypoint](https://github.com/GameServerManagers/docker-steamcmd/blob/main/docker-entrypoint.sh).
- [LinuxGSM Docker](https://github.com/GameServerManagers/docker-linuxgsm), [Dockerfile](https://github.com/GameServerManagers/docker-linuxgsm/blob/main/Dockerfile).
- [Competitive](https://github.com/AoC-Gamers/Docker-L4D2-Competitive), [AoC](https://github.com/AoC-Gamers/Docker-L4D2-AoC), [Vanilla](https://github.com/AoC-Gamers/Docker-L4D2-AoC-Vanilla).
- [Docker: procesos múltiples](https://docs.docker.com/engine/containers/multi-service_container/), [OpenSSH](https://man.openbsd.org/sshd), [no_new_privs](https://www.kernel.org/doc/html/latest/userspace-api/no_new_privs.html).

Los entrypoints de SteamCMD/LinuxGSM son sustituidos por Competitive. Se heredan paquetes y configuración, incluida originalmente la regla sudo ilimitada. API 2 elimina esa regla y la dependencia de ejecutar hooks operativos como root.

## Dos dominios de privilegio

`/usr/bin/python3 -I /usr/local/libexec/l4d2/bootstrap.py` es el entrypoint protegido de la imagen. Python aislado evita importar código desde el cwd mutable. Prepara UID/GID, grupos declarados, acceso al volumen, entorno de sesiones y SSH. No importa bibliotecas del instalador ni ejecuta hooks de `/app` o `/data` como root.

El supervisor mínimo mantiene `sshd -D -e` y un gestor de runtime separado. Este último se ejecuta como linuxgsm, inicializa grupos suplementarios, elimina capacidades efectivas/ambientales/heredables/bounding y aplica `no_new_privs`. Instalación, compilaciones, actualizador, enlaces, hooks after-sync/idle y gameservers heredan esas restricciones. SSH conserva PAM, shell y SFTP del usuario linuxgsm; root no puede autenticarse. La shell de sesiones carga el entorno como JSON, nunca como código de credenciales, y aplica `no_new_privs`. Las instancias iniciadas automáticamente tienen bounding set vacío; las iniciadas desde SSH conservan el bounding set de esa sesión, pero sin capacidades efectivas y sin poder adquirir privilegios por exec.

El listener de SSH y el bootstrap siguen siendo root. El aviso de Sonar requiere revisión de esta necesidad; no se oculta con USER ni NOSONAR. Root no se usa para instalar paquetes al arrancar. El verificador de bibliotecas sigue siendo de solo lectura; build estricto y runtime informativo.

## Volúmenes e identidades

- `data:/data`: los datos actuales no se reemplazan con defaults de la nueva imagen.
- `ssh:/var/lib/l4d2/ssh`: volumen pequeño root-owned; `SSH_VOLUME_NAME` debe permanecer estable entre recreaciones. Se importan las claves privadas legacy de `/data/ssh` sin seguir symlinks y sin sobrescribir identidades ya migradas. Las copias legacy conservan sus bytes para rollback, pero pasan a root:root (directorio 0700, claves 0600) para no dejar expuesta la misma clave al juego. Si las claves existentes son inseguras o inválidas, la preparación falla antes de servir SSH.
- `resources`: SDK/recursos compartidos en solo lectura; nunca cambiar propietarios ni permisos.
- Artefactos BanSystem: volumen externo con GID compartido, directorios 2770 y archivos 0660. Los grupos declarados en el JSON protegido se incorporan a la cuenta, también para sesiones SSH.

`L4D2_VOLUME_OWNERSHIP=auto` prepara una inicialización o un remapeo de UID/GID detectado, sin recorrer datos en cada arranque normal. `check` solo valida acceso; `repair` solicita explícitamente la migración de propietarios. La migración omite symlinks, montajes anidados, recursos, SSH legacy y artefactos compartidos; conserva grupos ajenos y SGID. La reparación no es una herramienta para adoptar datos de propietarios desconocidos.

## Instancias y apagado

Los puertos y `basepath` permanecen en cada CFG LinuxGSM. Se conserva el layout de enlaces compartidos, logs/data físicos por instancia y los recibos del instalador. No se clona Valve por cada gameserver.

Al apagar se cancela primero una preparación en curso, se guarda la selección activa y se detienen todas sus instancias. La parada del contenedor no captura nuevamente la lista vacía. En el siguiente inicio se reanuda solo la selección previa, respetando L4D2_AUTOSTART=false. Un fallo de despliegue conserva SSH para diagnóstico; no se declara gameplay aceptado.

Compose usa init y stop_grace_period=2m. No imponer cap_drop:ALL ni restricciones globales a SSH/PAM sin validarlas; las restricciones de capacidades ya se aplican a la rama de runtime.

## Extensión de las derivadas

AoC copia un `groups.json` protegido que declara BANSYSTEM_ARTIFACT_GID y fija sus defaults mediante Docker ENV. Su hook operativo no modifica usuarios ni /etc/environment. after-sync/idle conservan su API y se ejecutan como linuxgsm. Vanilla hereda el contrato sin duplicar supervisor ni claves.

## Validación y pendientes

La aceptación exige SSH por clave y contraseña (si está configurada), comandos no interactivos y SFTP, persistencia de huellas tras recreación, grupos y acceso a volúmenes, bloqueo de sudo/NNP, bibliotecas y extensiones y conservación de selección tras parada/reinicio. La aceptación de esta versión incluyó seis instancias reales antes del límite posterior del usuario: no repetir esa carga en el notebook, donde el máximo actual es DOS gameservers reales en total. Los fixtures cubren doce instancias sin crear doce instalaciones Valve. Ver el plan de Competitive para resultados concretos.

Optimizaciones posteriores independientes: coordinar el actualizador Valve compartido (riesgo de concurrencia aún sin fallo reproducido), fijar revisiones de módulos LinuxGSM, separar toolchains de compilación y evaluar extracción de SSH a otro servicio. No cambiar esos contratos incidentalmente durante esta migración.
