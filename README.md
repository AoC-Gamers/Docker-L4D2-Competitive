# Docker-L4D2-Competitive

[![Docker](https://img.shields.io/badge/docker-%230db7ed.svg?style=for-the-bad| **[🚀 Inicio Rápido](docs/quick-start.md)** | Instalación y primeros pasos | Nuevos usuarios |
| **[⚙️ Configuración Avanzada](docs/configuration.md)** | Variables, workshop, múltiples servidores | Usuarios experimentados |
| **[🔄 L4D2Updater](docs/l4d2-updater.md)** | Sistema de actualizaciones automáticas | Administradores |
| **[📜 Scripts](docs/scripts.md)** | Referencia completa de todos los scripts | Administradores |
| **[🔧 API Reference](docs/api-reference.md)** | Funciones y APIs técnicas | Integradores |=docker&logoColor=white)](https://hub.docker.com/r/aocgamers/lgsm-l4d2-competitive)
[![GitHub](https://img.shields.io/badge/github-%23121011.svg?style=for-the-badge&logo=github&logoColor=white)](https://github.com/AoC-Gamers/Docker-L4D2-Competitive)

**Contenedor Docker para servidores competitivos de Left 4 Dead 2** con configuración automática, gestión de workshop, clonación de servidores y scripts de post-procesamiento Git.

## 🚀 Inicio Rápido

```bash
# 1. Clonar el repositorio
git clone https://github.com/AoC-Gamers/Docker-L4D2-Competitive.git
cd Docker-L4D2-Competitive

# 2. Configurar variables básicas (SEGURO)
cp example.env .env
nano .env  # Editar LGSM_PASSWORD, SSH_PORT, STEAM_USER, etc.
chmod 600 .env  # Permisos restrictivos para seguridad

# 3. Iniciar el contenedor
docker-compose up -d

# 4. Acceder por SSH (opcional)
ssh linuxgsm@localhost -p 2222
```

> **⚠️ Volumen Obligatorio**: El volumen `comp_data:/data` es **crítico** para persistir configuraciones, mapas y datos del servidor.

## ✨ Características Principales

- **� 3 Métodos de Instalación**: Steam oficial, workaround automático, o manual
- **�🔧 Configuración Automática**: Instalación y configuración completa del servidor L4D2
- **🚀 L4D2Updater**: Sistema de actualizaciones automáticas usando mecanismo nativo de Valve
- **🎮 Servidores Múltiples**: Clonación automática de instancias L4D2 independientes
- **📦 Steam Workshop**: Descarga automática de colecciones y artículos (con procesamiento por lotes)
- **🗺️ Gestión de Mapas**: Descarga desde L4D2Center con verificación MD5
- **🌿 Ramas Dinámicas**: Sistema `BRANCH_*` para usar diferentes versiones por entorno
- **🔗 Enlaces Simbólicos**: Actualizaciones automáticas de scripts vía `symlink.sh`
- **📊 Menú Interactivo**: Control centralizado de todos los servidores
- **🔒 Seguridad**: Gestión segura de credenciales con limpieza automática

## 🏗️ Arquitectura del Sistema

### Directorios Clave
- **`/app/`** (No persistente): Scripts actualizables con nuevas versiones
- **`/data/`** (Persistente): Gameserver, configuraciones, logs y datos de usuario
- **Enlaces simbólicos**: Conectan `/app` con `/data` para coherencia automática

### Flujo de Trabajo
```mermaid
graph LR
    A[Docker Compose] --> B[Entrypoint]
    B --> C[Configuración SSH]
    C --> D[Instalación L4D2]
    D --> E[L4D2Updater]
    E --> F[Install Gameserver]
    F --> G[Workshop/Mapas]
    G --> H[Servidores Listos]
```

## 📊 Variables de Entorno Principales

| Variable | Descripción | Ejemplo |
|----------|-------------|---------|
| `LGSM_PASSWORD` | Contraseña SSH (obligatorio) | `mi_password_seguro` |
| `SSH_PORT` | Puerto SSH del contenedor | `2222` |
| `STEAM_USER` | Usuario Steam (instalación oficial) | `mi_usuario_steam` |
| `STEAM_PASSWD` | Contraseña Steam (limpieza automática) | `mi_contraseña` |
| `L4D2_NO_INSTALL` | Evitar instalación automática | `false` |
| `L4D2_NO_UPDATER` | Deshabilitar L4D2Updater | `false` |
| `BRANCH_SIR` | Rama del repo L4D2-Competitive-Rework | `development` |
| `GIT_FORCE_DOWNLOAD` | Forzar descarga de repositorios | `false` |

Ver [configuración completa](docs/configuration.md) para todas las opciones.

## 🎯 Casos de Uso

### Instalación con Steam (Recomendado)
```bash
# .env
STEAM_USER=mi_usuario_steam
STEAM_PASSWD=mi_contraseña_steam
LGSM_PASSWORD=mi_password_seguro
```

### Desarrollo
```yaml
environment:
  - BRANCH_SIR=development
  - GIT_FORCE_DOWNLOAD=true
  - L4D2_NO_AUTOSTART=true
```

### Producción
```yaml
environment:
  - LGSM_PASSWORD=${LGSM_PASSWORD}
  - SSH_KEY=${SSH_KEY}
  # Sin BRANCH_* = usa ramas estables
```

## 📚 Documentación Completa

| Documento | Descripción | Para quién |
|-----------|-------------|------------|
| **[🚀 Inicio Rápido](docs/quick-start.md)** | Instalación y primeros pasos | Nuevos usuarios |
| **[⚙️ Configuración Avanzada](docs/configuration.md)** | Variables, workshop, múltiples servidores | Usuarios experimentados |
| **[📜 Scripts](docs/scripts.md)** | Referencia completa de todos los scripts | Administradores |
| **[� Diagramas de Flujo](docs/flowcharts.md)** | Flujos visuales de instalación | Desarrolladores |
| **[🔧 API Reference](docs/api-reference.md)** | Funciones y APIs técnicas | Integradores |
| **[🐛 Troubleshooting](docs/troubleshooting.md)** | Solución de problemas | Todos |
| **[👨‍💻 Desarrollo](docs/development.md)** | Contribuir al proyecto | Contribuidores |

## 🛠️ Requisitos del Sistema

- **Docker**: 20.10+ y Docker Compose 1.29+
- **RAM**: 4GB mínimo, 8GB recomendado para producción
- **Almacenamiento**: 20GB disponibles (50GB+ para producción)
- **Red**: Conexión estable (descarga inicial ~10GB)

## 🚨 Información Importante

### ⚠️ Primera Instalación
- **Tiempo**: 30-60 minutos (dependiendo de conexión)
- **Descarga**: ~8GB de L4D2 + ~2GB de configuraciones competitivas
- **Volumen Docker**: **OBLIGATORIO** para persistir datos

### 🔐 Seguridad
- Cambiar `LGSM_PASSWORD` por defecto
- Configurar claves SSH para acceso remoto seguro
- Revisar configuración de puertos según entorno

## 🤝 Contribuir y Soporte

### 🐛 Reportar Problemas
[**Issues**](https://github.com/AoC-Gamers/Docker-L4D2-Competitive/issues) • [**Releases**](https://github.com/AoC-Gamers/Docker-L4D2-Competitive/releases)

### 🤝 Contribuir
1. Fork del repositorio
2. Crear rama: `git checkout -b feature/mejora-increible`
3. Commit: `git commit -m 'Add mejora increible'`
4. Push: `git push origin feature/mejora-increible`
5. Abrir Pull Request

Consulta la [documentación completa](docs/) para información técnica detallada.

### 🙏 Agradecimientos
- [GameServerManagers/LinuxGSM](https://github.com/GameServerManagers/LinuxGSM) - Base de gestión de servidores
- [SirPlease/L4D2-Competitive-Rework](https://github.com/SirPlease/L4D2-Competitive-Rework) - Configuración competitiva
- [Geam/steam_workshop_downloader](https://github.com/Geam/steam_workshop_downloader) - Herramienta de workshop

## 📜 Licencia

Distribuido bajo la [**Licencia MIT**](LICENSE). Ver `LICENSE` para más información.

---

<div align="center">

**¿Nuevo en el proyecto?** → [Guía de Inicio Rápido](docs/quick-start.md)  
**¿Necesitas ayuda?** → [Documentación Completa](docs/)  
**¿Quieres contribuir?** → [Issues & Pull Requests](https://github.com/AoC-Gamers/Docker-L4D2-Competitive)

</div>
