# Guía de Troubleshooting

## Problemas Comunes de Instalación

### El contenedor no inicia

**Síntomas:**
- El contenedor se cierra inmediatamente
- Error "Exited (1)" en Docker

**Diagnóstico:**
```bash
# Ver logs del contenedor
docker-compose logs comp_l4d2

# Verificar estado del contenedor
docker-compose ps
```

**Soluciones:**
1. **Verificar variables de entorno:**
   ```bash
   # Asegurar que .env existe y tiene las variables básicas
   cat .env
   ```

2. **Problemas de permisos:**
   ```bash
   # Verificar permisos del volumen
   docker-compose down
   docker volume rm comp_data
   docker-compose up -d
   ```

3. **Puerto en uso:**
   ```bash
   # Verificar si el puerto SSH está ocupado
   netstat -tlnp | grep :2222
   
   # Cambiar puerto en .env
   SSH_PORT=2223
   ```

### Error de instalación de SteamCMD

**Síntomas:**
- Error "app_update 222860" failed
- SteamCMD no puede descargar Left 4 Dead 2

**Diagnóstico:**
```bash
# Acceder al contenedor y revisar logs
docker-compose exec comp_l4d2 bash
tail -f /data/log/l4d2server-console.log
```

**Soluciones:**
1. **Problemas de red:**
   ```bash
   # Verificar conectividad
   ping steampowered.com
   
   # Verificar DNS
   nslookup steampowered.com
   ```

2. **Espacio en disco:**
   ```bash
   # Verificar espacio disponible
   df -h
   
   # Limpiar si es necesario
   docker system prune -a
   ```

3. **Forzar reinstalación:**
   ```bash
   # Dentro del contenedor
   rm -rf /data/serverfiles/*
   bash /data/server-scripts/l4d2_fix_install.sh
   ```

### Problemas con SSH

**Síntomas:**
- No se puede conectar por SSH
- "Connection refused" o timeout

**Diagnóstico:**
```bash
# Verificar si el puerto está abierto
nc -zv localhost 2222

# Ver estado del servicio SSH en el contenedor
docker-compose exec comp_l4d2 service ssh status
```

**Soluciones:**
1. **Verificar configuración:**
   ```bash
   # En .env
   SSH_PORT=2222
   SSH_KEY=ssh-rsa AAAAB3NzaC1yc2EAAA...
   ```

2. **Reiniciar servicio SSH:**
   ```bash
   docker-compose exec comp_l4d2 service ssh restart
   ```

3. **Verificar firewall del host:**
   ```bash
   # Ubuntu/Debian
   ufw status
   ufw allow 2222
   ```

## Problemas del Servidor L4D2

### El servidor no inicia

**Síntomas:**
- `./l4d2server start` falla
- No hay proceso srcds_run

**Diagnóstico:**
```bash
# Verificar detalles del servidor
./l4d2server details

# Ver logs de inicio
./l4d2server console

# Verificar archivos del servidor
ls -la /data/serverfiles/left4dead2/
```

**Soluciones:**
1. **Verificar instalación:**
   ```bash
   # Reinstalar si faltan archivos
   ./l4d2server validate
   
   # O forzar instalación completa
   bash /data/server-scripts/l4d2_fix_install.sh
   ```

2. **Problemas de configuración:**
   ```bash
   # Verificar cfg del servidor
   cat /data/serverfiles/left4dead2/cfg/l4d2server.cfg
   
   # Verificar puerto no esté en uso
   netstat -tlnp | grep :27015
   ```

3. **Problemas de permisos:**
   ```bash
   # Corregir permisos
   chown -R linuxgsm:linuxgsm /data/serverfiles
   chmod +x /data/serverfiles/left4dead2/srcds_run
   ```

### El servidor se crashea constantemente

**Síntomas:**
- Servidor inicia pero se cierra después de poco tiempo
- Errores en los logs

**Diagnóstico:**
```bash
# Ver logs de crash
cat /data/log/l4d2server-console.log
cat /data/serverfiles/left4dead2/logs/L*.log

# Verificar SourceMod
cat /data/serverfiles/left4dead2/addons/sourcemod/logs/errors_*.log
```

**Soluciones:**
1. **Plugins problemáticos:**
   ```bash
   # Deshabilitar todos los plugins
   mv /data/serverfiles/left4dead2/addons/sourcemod/plugins /data/serverfiles/left4dead2/addons/sourcemod/plugins.bak
   mkdir /data/serverfiles/left4dead2/addons/sourcemod/plugins
   
   # Habilitar uno por uno para identificar el problemático
   ```

2. **Configuración de memoria:**
   ```bash
   # En l4d2server.cfg, ajustar límites
   echo 'sm_memory_limit 128' >> /data/lgsm-config/l4d2server/l4d2server.cfg
   ```

3. **Actualizar SourceMod:**
   ```bash
   # Forzar actualización
   GIT_FORCE_DOWNLOAD=true bash /data/server-scripts/install_gameserver.sh update
   ```

## Problemas del Workshop

### Workshop Downloader falla

**Síntomas:**
- Error "workshop.py no encontrado"
- Error "path doesn't exist"

**Diagnóstico:**
```bash
# Verificar archivos necesarios
ls -la /data/server-scripts/workshop*

# Verificar Python
python3 --version

# Ver logs del downloader
tail -f /data/server-scripts/workshop_*.log
```

**Soluciones:**
1. **Dependencias faltantes:**
   ```bash
   # Instalar Python si no está disponible
   apt-get update && apt-get install -y python3
   ```

2. **Configuración incorrecta:**
   ```bash
   # Verificar .env del workshop
   cat /data/server-scripts/.env
   
   # Ejemplo de configuración correcta:
   echo 'OUTPUT_DIR=/data/serverfiles/left4dead2/addons/workshop' > /data/server-scripts/.env
   echo 'WORKSHOP_COLLECTIONS=3489804150' >> /data/server-scripts/.env
   ```

3. **Permisos de escritura:**
   ```bash
   # Crear directorio si no existe
   mkdir -p /data/serverfiles/left4dead2/addons/workshop
   chown -R linuxgsm:linuxgsm /data/serverfiles/left4dead2/addons/
   ```

### Mapas no se descargan de L4D2Center

**Síntomas:**
- Script maps_l4d2center.sh falla
- Error de conectividad o permisos

**Diagnóstico:**
```bash
# Verificar conectividad
curl -I https://l4d2center.com/maps/servers/index.json

# Ver logs del script
tail -f /data/tmp/maps_l4d2center.log
```

**Soluciones:**
1. **Problemas de red:**
   ```bash
   # Verificar acceso a internet
   ping google.com
   
   # Configurar proxy si es necesario
   export http_proxy=http://proxy:port
   ```

2. **Forzar descarga:**
   ```bash
   # Eliminar caché y forzar descarga
   rm /data/tmp/cache_maps_l4d2center.json
   L4D2_MAPS_FORCE_DOWNLOAD=true bash /data/server-scripts/maps_l4d2center.sh
   ```

## Problemas de Rendimiento

### Alto uso de CPU/RAM

**Síntomas:**
- Sistema lento
- Servidores lagueados
- OOM Killer activo

**Diagnóstico:**
```bash
# Monitorear recursos
docker stats comp_l4d2

# Ver procesos dentro del contenedor
docker-compose exec comp_l4d2 htop

# Verificar logs del sistema
dmesg | grep -i "killed process"
```

**Soluciones:**
1. **Limitar recursos del contenedor:**
   ```yaml
   # En docker-compose.yml
   services:
     comp_l4d2:
       deploy:
         resources:
           limits:
             memory: 4G
             cpus: '2.0'
   ```

2. **Optimizar configuración del servidor:**
   ```bash
   # En server.cfg
   echo 'sv_minrate 25000' >> /data/serverfiles/left4dead2/cfg/server.cfg
   echo 'sv_maxrate 30000' >> /data/serverfiles/left4dead2/cfg/server.cfg
   echo 'fps_max 300' >> /data/serverfiles/left4dead2/cfg/server.cfg
   ```

3. **Reducir número de servidores:**
   ```bash
   # Detener servidores innecesarios
   ./menu_gameserver.sh stop 3 4
   ```

### Problemas de red/conexión

**Síntomas:**
- Players no pueden conectar
- Timeouts frecuentes
- Lag excesivo

**Diagnóstico:**
```bash
# Verificar puertos del servidor
netstat -tlnp | grep srcds

# Test de conexión externa
telnet tu_ip 27015

# Verificar firewall
iptables -L -n
```

**Soluciones:**
1. **Configurar puertos correctamente:**
   ```bash
   # Abrir puertos necesarios
   ufw allow 27015/udp
   ufw allow 27020/udp  # SourceTV
   ```

2. **Optimizar configuración de red:**
   ```bash
   # En server.cfg
   echo 'net_splitpacket_maxrate 50000' >> /data/serverfiles/left4dead2/cfg/server.cfg
   echo 'sv_parallel_packetsend 1' >> /data/serverfiles/left4dead2/cfg/server.cfg
   ```

## Problemas de Actualización

### Actualizaciones fallan

**Síntomas:**
- Error durante `install_gameserver.sh update`
- Repositorios git no se actualizan

**Diagnóstico:**
```bash
# Ver logs de instalación
tail -f /data/server-scripts/install_gameserver.log

# Verificar conectividad git
git ls-remote https://github.com/SirPlease/L4D2-Competitive-Rework.git
```

**Soluciones:**
1. **Forzar descarga:**
   ```bash
   # Limpiar caché y forzar descarga
   rm /data/tmp/cache_gameserver.log
   GIT_FORCE_DOWNLOAD=true bash /data/server-scripts/install_gameserver.sh update
   ```

2. **Problemas de espacio:**
   ```bash
   # Limpiar archivos temporales
   rm -rf /data/tmp/*
   
   # Verificar espacio
   df -h /data
   ```

## Comandos de Diagnóstico Útiles

### Estado del sistema:
```bash
# Estado del contenedor
docker-compose ps
docker-compose logs --tail=50 comp_l4d2

# Recursos del sistema
docker stats comp_l4d2
docker-compose exec comp_l4d2 free -h
docker-compose exec comp_l4d2 df -h
```

### Estado del servidor L4D2:
```bash
# Dentro del contenedor
./l4d2server details
./l4d2server monitor
ps aux | grep srcds
netstat -tlnp | grep 27015
```

### Logs importantes:
```bash
# Logs del sistema Docker
/var/log/docker.log

# Logs del servidor L4D2
/data/log/l4d2server-console.log
/data/log/l4d2server-script.log

# Logs de SourceMod
/data/serverfiles/left4dead2/addons/sourcemod/logs/errors_*.log

# Logs de scripts personalizados
/data/server-scripts/*.log
/data/tmp/*.log
```

### Verificación de archivos críticos:
```bash
# Archivos de configuración
ls -la /data/lgsm-config/l4d2server/
ls -la /data/serverfiles/left4dead2/cfg/

# Archivos ejecutables
ls -la /data/serverfiles/left4dead2/srcds_run
ls -la /app/l4d2server

# Scripts del proyecto
ls -la /data/server-scripts/
```

## Restauración de Emergencia

### Backup rápido:
```bash
# Crear backup completo
tar -czf backup_emergency_$(date +%Y%m%d_%H%M%S).tar.gz \
  /data/serverfiles/left4dead2/cfg/ \
  /data/serverfiles/left4dead2/addons/sourcemod/configs/ \
  /data/lgsm-config/
```

### Restauración limpia:
```bash
# Parar el contenedor
docker-compose down

# Eliminar volumen
docker volume rm comp_data

# Recrear desde cero
docker-compose up -d

# Restaurar configuraciones desde backup
tar -xzf backup_emergency_*.tar.gz -C /
```

### Factory Reset:
```bash
# Eliminar todo y empezar de nuevo
docker-compose down
docker volume rm comp_data
docker image rm ghcr.io/aoc-gamers/lgsm-l4d2-competitive:latest
docker-compose pull
docker-compose up -d
```
