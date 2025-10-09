# Build arguments
ARG FREERADIUS_VERSION=latest

# Start from FreeRadius image
FROM freeradius/freeradius-server:${FREERADIUS_VERSION}

LABEL org.opencontainers.image.source="https://github.com/ict-solutions-dev/docker-freeradius" \
      org.opencontainers.image.description="Docker image for FreeRADIUS server with enhanced features including SQL, CoA and Status support" \
      org.opencontainers.image.title="FreeRADIUS Server - AAA Solution" \
      org.opencontainers.image.authors="Jozef Rebjak <jozef.rebjak@ictsolutions.net>" \
      org.opencontainers.image.vendor="ICT Solutions"

# Set non-interactive mode
ARG DEBIAN_FRONTEND=noninteractive

# Set timezone
ENV TZ=Europe/Bratislava

# Install packages and cleanup in one RUN statement
RUN apt-get update && apt-get install --yes --no-install-recommends \
    socat \
    apt-utils \
    ipcalc \
    tzdata \
    net-tools \
    mariadb-client \
    libmysqlclient-dev \
    unzip \
    wget \
    && ln -fs /usr/share/zoneinfo/${TZ} /etc/localtime \
    && dpkg-reconfigure tzdata \
    && rm -rf /var/lib/apt/lists/* \
    # Create directories
    && mkdir /data /internal_data \
    # Forward radius logs to docker log collector
    && ln -sf /dev/stdout /var/log/freeradius/radius.log

# Copy assets
COPY assets/01-init.sh /
COPY assets/02-restart-handler.sh /usr/local/bin/

# Set permissions
RUN chmod +x /01-init.sh \
    /usr/local/bin/02-restart-handler.sh

# Expose necessary ports
EXPOSE 1812/udp 1813/udp 18121/udp

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD pgrep freeradius || exit 1

# Set entrypoint
ENTRYPOINT ["/01-init.sh"]

# Set default command
CMD ["freeradius"]
