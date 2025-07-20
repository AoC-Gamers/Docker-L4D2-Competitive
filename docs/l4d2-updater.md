# L4D2Updater - Sistema de Actualizaciones Automáticas

## 📑 Tabla de Contenidos

1. [Visión General](#visión-general)
2. [Cómo Funciona](#cómo-funciona)
3. [Instalación y Configuración](#instalación-y-configuración)
4. [Archivos Generados](#archivos-generados)
5. [Control y Configuración](#control-y-configuración)
6. [Resolución de Problemas](#resolución-de-problemas)

---

## Visión General

L4D2Updater es un sistema que configura el servidor L4D2 para usar el **mecanismo nativo de actualizaciones de Valve** mediante un `srcds_run` personalizado. Esto permite que el servidor se actualice automáticamente usando la infraestructura oficial de Steam.

### 🎯 **Beneficios Principales**

- ✅ **Actualizaciones automáticas**: Usa el sistema oficial de Valve
- ✅ **Sin intervención manual**: Completamente automático
- ✅ **Login anónimo**: Evita solicitudes SteamGuard en cada inicio
- ✅ **Instalación automática**: Se configura después de cada instalación fresh
- ✅ **Compatible**: Funciona con todos los métodos de instalación

## Cómo Funciona

### 🔧 **Proceso de Configuración**

1. **Clona `srcds_run`**: Crea `srcds_l4d2` personalizado
2. **Modifica variables**: Configura actualizaciones automáticas
3. **Genera script**: Crea `update_l4d2.txt` con comandos SteamCMD
4. **Configura LGSM**: Modifica LinuxGSM para usar el nuevo ejecutable

### ⚙️ **Variables Modificadas en `srcds_l4d2`**

```bash
# Variables configuradas automáticamente:
AUTO_UPDATE="yes"                                    # Habilita actualizaciones
STEAM_DIR="$HOME/.steam/steam/steamcmd"             # Directorio SteamCMD
STEAMCMD_SCRIPT="$HOME/serverfiles/update_l4d2.txt" # Script de actualización
```

### 📝 **Contenido de `update_l4d2.txt`**

```bash
@ShutdownOnFailedCommand 1
@NoPromptForPassword 1
force_install_dir /data/serverfiles/
login anonymous
app_update 222860
quit
```

## Instalación y Configuración

### 🚀 **Instalación Automática**

L4D2Updater se instala automáticamente después de:
- ✅ Instalación fresh del servidor L4D2
- ✅ Verificación de que `srcds_run` existe
- ✅ Confirmación de que `L4D2_NO_UPDATER` no está habilitado

### 🎛️ **Variable de Control**

```bash
# En .env o docker-compose.yml
L4D2_NO_UPDATER=false  # Instalar L4D2Updater (predeterminado)
L4D2_NO_UPDATER=true   # Deshabilitar instalación del sistema
```

## Archivos Generados

### 📁 **Estructura de Archivos**

```
/data/serverfiles/
├── srcds_run              # Original de Valve
├── srcds_l4d2            # ← Clon personalizado para actualizaciones
└── update_l4d2.txt       # ← Script SteamCMD para actualizaciones

/data/config-lgsm/l4d2server/
└── common.cfg            # ← Modificado para usar srcds_l4d2
```

### 🔧 **Configuración LGSM**

L4D2Updater agrega la siguiente línea a `common.cfg`:

```bash
## Game Server Directories
executable="./srcds_l4d2"
```

Esto hace que LinuxGSM use el ejecutable personalizado con actualizaciones automáticas.

## Control y Configuración

### ✅ **Verificar Instalación**

```bash
# Verificar que srcds_l4d2 existe
ls -la /data/serverfiles/srcds_l4d2

# Verificar script de actualización
cat /data/serverfiles/update_l4d2.txt

# Verificar configuración LGSM
grep "executable=" /data/config-lgsm/l4d2server/common.cfg
```

### ⚠️ **Sistema deshabilitado**

Si `L4D2_NO_UPDATER=true`, verás este mensaje:
```
L4D2Updater installation skipped (L4D2_NO_UPDATER=true)
```

Para habilitar, cambiar a `L4D2_NO_UPDATER=false` o eliminar la variable.

---

L4D2Updater proporciona un sistema robusto y automático para mantener tu servidor L4D2 actualizado usando la infraestructura oficial de Valve, sin requerir intervención manual! 🚀
