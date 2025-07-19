# Guía de Inicio Rápido

## Requisitos Previos

- Docker y Docker Compose instalados
- Git
- Acceso a internet para descargar contenidos del Steam Workshop

## Instalación Básica

### 1. Clonación del Repositorio

```bash
git clone https://github.com/AoC-Gamers/Docker-L4D2-Competitive.git
cd Docker-L4D2-Competitive
```

### 2. Configuración del Entorno

```bash
# Copia el archivo de ejemplo
cp example.env .env

# Edita las variables necesarias
nano .env
```

### 3. Variables de Entorno Básicas

```bash
# Contraseña para el usuario linuxgsm
LGSM_PASSWORD=mi_contraseña_segura

# Puerto SSH (opcional, default: 22)
SSH_PORT=2222

# Clave SSH pública para acceso remoto (opcional)
SSH_KEY=ssh-rsa AAAAB3NzaC1yc2E...

# Evitar instalación automática (útil para configuración manual)
L4D2_NO_INSTALL=false

# Evitar inicio automático del servidor
L4D2_NO_AUTOSTART=false
```

### 4. Ejecución del Contenedor

```bash
# Modo desarrollo (con archivos locales)
docker-compose -f docker-compose.dev.yml up -d

# Modo producción
docker-compose up -d
```

### 5. Verificación del Estado

```bash
# Ver logs del contenedor
docker-compose logs -f comp_l4d2

# Acceder al contenedor
docker-compose exec comp_l4d2 bash

# Verificar estado del servidor L4D2
docker-compose exec comp_l4d2 gosu linuxgsm ./l4d2server details
```

## Primeros Pasos

### Acceso SSH al Contenedor

```bash
ssh linuxgsm@localhost -p 2222
```

### Gestión Básica del Servidor

```bash
# Iniciar servidor
./menu_gameserver.sh start

# Detener servidor
./menu_gameserver.sh stop

# Reiniciar servidor
./menu_gameserver.sh restart

# Actualizar servidor
./menu_gameserver.sh update
```

### Configuración de Mapas y Workshop

El proyecto incluye dos scripts para gestionar contenido del Steam Workshop:

- **`workshop.py`**: Script base en Python que interactúa directamente con la API de Steam
- **`workshop_downloader.sh`**: Script wrapper que facilita el uso mediante configuración .env

#### Configuración del Workshop

```bash
# Acceder al contenedor y navegar a scripts
docker-compose exec comp_l4d2 bash
cd /data/server-scripts

# Crear archivo de configuración basado en el ejemplo
cp .env.example .env
nano .env

# O crear manualmente con configuración básica:
cat > .env << EOF
# Artículos individuales del Workshop (IDs separados por comas)
WORKSHOP_ITEMS=123456789,987654321

# Colecciones del Workshop (IDs separados por comas)
WORKSHOP_COLLECTIONS=3489804150

# Directorio de salida (usando variable de entorno del sistema)
OUTPUT_DIR=\$DIR_LEFT4DEAD2/addons/workshop

# Configuración de procesamiento por lotes
BATCH_SIZE=5
BATCH_DELAY=10
EOF
```

#### Descarga de Contenido

```bash
# Descargar usando el script wrapper (recomendado)
./workshop_downloader.sh

# Alternativas con opciones específicas:
./workshop_downloader.sh -b 10 -d 5  # Lotes más grandes, menos delay
./workshop_downloader.sh -o /ruta/custom  # Directorio personalizado

# Uso directo de workshop.py (avanzado)
python3 workshop.py -o /data/serverfiles/left4dead2/addons/workshop 3489804150
```

**Ventajas del sistema:**
- **Persistencia**: La configuración .env guarda tus colecciones y artículos
- **Procesamiento por lotes**: Evita sobrecargar la API de Steam
- **Reintentos automáticos**: Maneja errores de red automáticamente
- **Logging detallado**: Registra todo el proceso para debugging

## Solución de Problemas Comunes

### El contenedor no inicia
- Verificar que los puertos no estén en uso
- Revisar los logs: `docker-compose logs comp_l4d2`

### No se puede conectar por SSH
- Verificar que `SSH_PORT` esté configurado correctamente
- Comprobar que el servicio SSH esté activo en el contenedor

### El servidor L4D2 no responde
- Verificar que la instalación se completó: revisar logs
- Comprobar configuración del servidor en `/data/serverfiles/left4dead2/cfg/`

## Siguientes Pasos

- Lee la [Guía de Configuración Avanzada](configuration.md)
- Consulta la [Documentación de Scripts](scripts.md)
- Revisa la [Guía de Troubleshooting](troubleshooting.md)
