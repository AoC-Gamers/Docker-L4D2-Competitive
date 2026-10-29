# Auto-install runtime dependencies and gdb
#
# LinuxGSM Left 4 Dead 2 Dockerfile with SFTP Support
#
# https://github.com/GameServerManagers/docker-gameserver
#

ARG BASE_IMAGE=gameservermanagers/linuxgsm:ubuntu-26.04
FROM ${BASE_IMAGE}
ARG BASE_IMAGE
LABEL org.opencontainers.image.base.name="${BASE_IMAGE}"
LABEL maintainer="L4D2 LGSM Competitive <lechuga>"
LABEL version="2.1.0"

ARG SHORTNAME=l4d2
ENV GAMESERVER=l4d2server \
    NPM_CONFIG_AUDIT=false

WORKDIR /app
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

COPY container/runtime-packages.txt /app/container/runtime-packages.txt
COPY container/bootstrap/dependencies_check.sh /app/container/bootstrap/dependencies_check.sh

# Agregar arquitectura i386 e instalar paquetes adicionales
RUN dpkg --add-architecture i386 && \
    apt-get update && \
    mapfile -t packages < /app/container/runtime-packages.txt && \
    apt-get install -y "${packages[@]}" && \
    bash /app/container/bootstrap/dependencies_check.sh --strict && \
    apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Auto-install primary runtime requirements and gdb
RUN depshortname=$(curl --fail --show-error --location --connect-timeout 10 -s https://raw.githubusercontent.com/GameServerManagers/LinuxGSM/master/lgsm/data/ubuntu-26.04.csv | \
    awk -v shortname="l4d2" -F, '$1==shortname {$1=""; print $0}') && \
    if [ -n "${depshortname}" ]; then \
    echo "**** Install ${depshortname} ****" && \
    apt-get update && apt-get install -y ${depshortname} && \
    apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*; \
    fi

# Cambiar el shell predeterminado del usuario linuxgsm a bash y crear directorios necesarios
RUN usermod --shell /bin/bash linuxgsm && \
    mkdir -p /data/installer/bin /data/installer/lib /data/installer/config /data/stack/hooks

RUN date > /build-time.txt

COPY container/ /app/container/

# Copiar todos los archivos de /config-lgsm/l4d2server/ a /data/config-lgsm/l4d2server/
COPY config-lgsm/l4d2server/* /data/config-lgsm/l4d2server/

# Copiar el framework del instalador y el stack base
COPY installer/ /app/installer/
COPY stack/ /app/stack/

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD /app/container/entrypoint-healthcheck.sh healthcheck || exit 1

ENTRYPOINT ["/bin/bash", "./container/entrypoint.sh"]
