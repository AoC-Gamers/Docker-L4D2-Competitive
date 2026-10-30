# Reducción de privilegios — implementación y aceptación

Estado: aceptación local completada; publicación y CI pendientes. No publicar hasta completar la aceptación local.

Evidencia local (`tmp/root-bootstrap-20261029`, ignorado): Competitive 143 pruebas offline OK; AoC 17 pruebas OK (1 skip existente); Vanilla 6 pruebas OK. Tres imágenes locales root-v2 construidas. SSH por clave y contraseña y SFTP reales OK; sesiones UID 1000/NoNewPrivs=1. Remapeo UID/GID 2000, GID compartido 10001, archivos 0660 y SDK read-only verificados.

Seis SRCDS reales respondieron por UDP (28101..28106), cargaron 134 plugins por instancia y las extensiones nativas requeridas sin fallos. Apagado exit0, reanudación automática de seis con capabilities efectivas/bounding vacías y NNP1. Selección parcial 1/3/4/6 conservada; 2/5 permanecieron detenidas. Seis SQLite canary conservaron hash, inodo y propietarios tras ambos reinicios. Huellas SSH originales conservadas y claves legacy/protegidas inaccesibles al juego.

El laboratorio se detuvo y sus volúmenes propios se retiraron al establecer el usuario el límite de dos gameservers reales. Los informes permanecen; no se conservó una copia adicional de Valve. Vanilla se migró sobre su volumen original: healthy, UDP27016, 128 plugins y bibliotecas verificadas; SSH y metadatos SQLite conservados. AoC también se migró sobre su volumen original, manteniendo huellas SSH, GID 10001, bibliotecas verificadas y un SRCDS con NNP1/capabilities efectivas y bounding vacías. Ambos contenedores actuales están healthy y suman exactamente dos gameservers. Publicación y CI aún pendientes.

1. Bootstrap/supervisor protegido en Competitive, sudo eliminado, runtime sin capacidades y con no_new_privs.
2. SSH con claves persistentes protegidas, migración de huellas existentes, shell/SFTP sin privilegios.
3. Preparación de volúmenes sin chown general en cada inicio; preservar SDK read-only y grupo de artefactos.
4. Apagado de todas las instancias con conservación de intención; contrato heredable para AoC/Vanilla.
5. Pruebas offline, construcción local de las tres imágenes, SSH y SFTP reales, permisos/NNP, seis instancias reales, parada/reinicio y selección parcial.
6. Documentación y contexto AGENTS.md/CONTEXT.md; publicar develop en orden Competitive → AoC → Vanilla, verificar CI y padres exactos.

Los volúmenes actuales son autoridad y se conservan. Las pruebas usarán volúmenes separados y una sola instalación de Valve para todas las instancias. No crear imágenes tar ni copias de Valve por instancia.

Fuera de esta implementación: separar SSH en otro contenedor, cambiar el proveedor LinuxGSM, multi-stage de compiladores y cambiar el actualizador nativo Valve. Esas mejoras requieren una migración independiente; no se confunden con reducir root. Se documentan como pendientes de arquitectura, sin declarar que se probaron.

Referencias: [LinuxGSM](https://github.com/GameServerManagers/docker-linuxgsm), [SteamCMD](https://github.com/GameServerManagers/docker-steamcmd), [Ubuntu](https://hub.docker.com/_/ubuntu), [no_new_privs](https://www.kernel.org/doc/html/latest/userspace-api/no_new_privs.html).


## Restricción de recursos posterior a la aceptación

El usuario estableció un máximo de DOS gameservers reales simultáneos en todo el notebook, incluyendo los existentes. El laboratorio de seis ya había completado respuesta UDP, carga de extensiones, apagado, reanudación y selección parcial; se conserva esa evidencia y se detiene. No repetir esa carga. Las siguientes verificaciones se realizan con los dos servidores locales o con fixtures que no lanzan SRCDS.


## Orden de publicación

Primero se preparan los commits de las derivadas en develop con `[skip ci]` para no construir contra un padre API1. Después se publica Competitive y su job de validación ejecuta el gate SSH/SFTP de scripts/test-stack.sh antes de publicar la imagen; el dispatch por digest construye AoC y, al finalizar, Vanilla. Los dispatch no son omitidos por `[skip ci]` ([GitHub](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/skip-workflow-runs)). No se deshabilitan workflows ni se modifican secretos/variables del repositorio.


La credencial de publicación no incluye permiso workflow. El cambio de workflow inicialmente propuesto no se publicó: se mantuvo el YAML original y se incorporó el gate de construcción/SSH/SFTP al script de validación que ese workflow ya ejecuta. No se amplían permisos ni se omite la validación.
