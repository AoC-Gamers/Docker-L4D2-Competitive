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

## Activacion

Por defecto, el sistema queda activo salvo que se deshabilite con:

```bash
L4D2_NO_UPDATER=true
```

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
