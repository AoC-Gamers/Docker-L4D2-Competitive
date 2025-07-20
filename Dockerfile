#
# LinuxGSM Left 4 Dead 2 Dockerfile with SFTP Support
#
# https://github.com/GameServerManagers/docker-gameserver
#

FROM gameservermanagers/linuxgsm:ubuntu-24.04
LABEL maintainer="L4D2 LGSM Competitive <lechuga>"
LABEL version="2.1.0"

ARG SHORTNAME=l4d2
ENV GAMESERVER=l4d2server

WORKDIR /app

# Agregar arquitectura i386 e instalar paquetes adicionales
RUN dpkg --add-architecture i386 && \
    apt-get update && apt-get install -y \
    apt-utils \
    openssh-server \
    curl \
    wget \
    file \
    tar \
    bzip2 \
    gzip \
    unzip \
    bsdmainutils \
    util-linux \
    ca-certificates \
    binutils \
    bc \
    jq \
    tmux \
    netcat-openbsd \
    lib32gcc-s1 \
    lib32stdc++6 \
    libsdl2-2.0-0:i386 \
    steamcmd \
    gdb \
    lib32z1 \
    rsync \
    libcurl4 \
    htop \
    git \
    p7zip-full \
    p7zip-rar \
    gettext && \
    apt-get -y autoremove && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Auto-install game server requirements y gdb
RUN depshortname=$(curl --connect-timeout 10 -s https://raw.githubusercontent.com/GameServerManagers/LinuxGSM/master/lgsm/data/ubuntu-24.04.csv | \
    awk -v shortname="l4d2" -F, '$1==shortname {$1=""; print $0}') && \
    if [ -n "${depshortname}" ]; then \
    echo "**** Install ${depshortname} ****" && \
    apt-get update && apt-get install -y ${depshortname} && \
    apt-get -y autoremove && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*; \
    fi

# Cambiar el shell predeterminado del usuario linuxgsm a bash y crear directorios necesarios
RUN usermod --shell /bin/bash linuxgsm && \
    mkdir -p /data/server-scripts/git-gameserver/

RUN date > /build-time.txt

COPY entrypoint.sh /app/entrypoint.sh
COPY entrypoint-user.sh /app/entrypoint-user.sh
COPY entrypoint-healthcheck.sh /app/entrypoint-healthcheck.sh

# Copiar todos los archivos de /config-lgsm/l4d2server/ a /data/config-lgsm/l4d2server/
COPY config-lgsm/l4d2server/* /data/config-lgsm/l4d2server/

# Copiar todos los archivos de /server-scripts/ a /app/server-scripts/
COPY server-scripts/ /app/server-scripts/

# Copiar todos los archivos de /docker-scripts/ a /app/docker-scripts/
COPY docker-scripts/* /app/docker-scripts/

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD /app/entrypoint-healthcheck.sh healthcheck || exit 1

ENTRYPOINT ["/bin/bash", "./entrypoint.sh"]