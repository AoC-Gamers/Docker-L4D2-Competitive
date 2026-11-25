# L4D2Updater

## Resumen

L4D2Updater configura el servidor L4D2 para usar el mecanismo nativo de actualizaciones de Valve mediante un `srcds_l4d2` derivado de `srcds_run`.

## Como funciona

1. clona `srcds_run` hacia `srcds_l4d2`
2. ajusta variables de auto update
3. genera `update_l4d2.txt`
4. configura LinuxGSM para usar el ejecutable nuevo

## Variables afectadas

```bash
AUTO_UPDATE="yes"
STEAM_DIR="$HOME/.steam/steam/steamcmd"
STEAMCMD_SCRIPT="$HOME/serverfiles/update_l4d2.txt"
```

## Archivo generado

```bash
@ShutdownOnFailedCommand 1
@NoPromptForPassword 1
force_install_dir /data/serverfiles/
login anonymous
app_update 222860
quit
```

## Activación

Por defecto, el sistema queda activo salvo que se deshabilite con:

```bash
L4D2_UPDATER=false
```

Al preparar un volumen nuevo o existente, el bootstrap configura `./srcds_run`
en lugar de `./srcds_l4d2` en la asignación gestionada de `common.cfg`. Los
arranques posteriores usan el build instalado. Volver a `true` prepara el
lanzador con SteamCMD y vuelve a seleccionarlo. El cambio conserva los
lanzadores personalizados y deja los archivos del actualizador disponibles.

Comprueba que las configuraciones por instancia no vuelvan a seleccionar el
actualizador ni añadan `-autoupdate`, y que `updateonstart` esté en `off` para
mantener el build instalado. Una instalación inicial o explícita y los comandos
manuales de actualización siguen pudiendo descargar archivos de Valve.

## Promoción de builds

Usa `./l4d2server check-update` desde `/app` para consultar una actualización
sin aplicarla. Valida el nuevo motor y sus extensiones en DEV. En PROD,
aplica la actualización manual una vez por volumen durante una ventana en que
todas las instancias de ese volumen estén detenidas. Verifica el build, Steam/VAC
y la carga de las extensiones al volver a iniciar.

## Archivos implicados

```text
/data/serverfiles/srcds_run
/data/serverfiles/srcds_l4d2
/data/serverfiles/update_l4d2.txt
/data/config-lgsm/l4d2server/common.cfg
```

## Verificacion

```bash
ls -la /data/serverfiles/srcds_l4d2
cat /data/serverfiles/update_l4d2.txt
grep "executable=" /data/config-lgsm/l4d2server/common.cfg
```

## Nota operativa

Si `srcds_run` aun no existe, el bootstrap no puede configurar L4D2Updater. En ese caso primero debe terminar la instalacion base del juego.
