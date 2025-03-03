#!/bin/bash
set -euo pipefail

#####################################################
# Definir LOG_FILE según si se ejecuta como root o no
if [ "$(id -u)" -eq 0 ]; then
    LOG_FILE="/dev/null"
else
    LOG_FILE="${DIR_SCRIPTING:-.}/dependencies.log"
fi

echo "Iniciando verificación de dependencias..." | tee -a "$LOG_FILE"

#####################################################
# Flag para evitar múltiples actualizaciones de apt
APT_UPDATED=false

#####################################################
# Función que actualiza la información de paquetes una única vez
update_apt() {
    if [ "$APT_UPDATED" = false ]; then
        DEBIAN_FRONTEND=noninteractive apt-get update > /dev/null
        DEBIAN_FRONTEND=noninteractive apt-get upgrade -y > /dev/null
        APT_UPDATED=true
    fi
}

#####################################################
# Función para verificar e instalar un paquete
check_package() {
    local pkg="$1"
    echo "Verificando paquete: $pkg" | tee -a "$LOG_FILE"
    if dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
        echo "[x] $pkg" | tee -a "$LOG_FILE"
    else
        echo "[ ] $pkg" | tee -a "$LOG_FILE"
        echo "Instalando $pkg..." | tee -a "$LOG_FILE"
        update_apt
        if DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg" > /dev/null; then
            echo "Instalado $pkg" | tee -a "$LOG_FILE"
        else
            echo "Error al instalar $pkg" | tee -a "$LOG_FILE"
        fi
    fi
}

#####################################################
# Función para iterar sobre la lista de paquetes
print_checklist() {
    echo "Checklist de paquetes:" | tee -a "$LOG_FILE"
    for package in "$@"; do
        check_package "$package"
    done
}

#####################################################
# Lista de paquetes a verificar
packages=("openssh-server" "curl" "wget" "file" "tar" "bzip2" "gzip" "unzip" "bsdmainutils" "util-linux" "ca-certificates" "binutils" "bc" "jq" "tmux" "netcat-openbsd" "lib32gcc-s1" "lib32stdc++6" "libsdl2-2.0-0:i386" "steamcmd" "gdb" "lib32z1" "rsync" "libcurl4" "htop" "git" "p7zip-full" "p7zip-rar" "sed")

print_checklist "${packages[@]}"

echo "Verificación de dependencias completada." | tee -a "$LOG_FILE"
