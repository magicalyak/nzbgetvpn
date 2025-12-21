# Multi-architecture Dockerfile for nzbgetvpn
# Supports: linux/amd64, linux/arm64

# Use specific version tag for reproducibility and attestation
# LinuxServer base already handles non-root user via PUID/PGID
# Base image: NZBGet v25.4 (LinuxServer build ls225)
FROM ghcr.io/linuxserver/nzbget:v25.4-ls225

# Build arguments for multi-architecture support
ARG BUILDPLATFORM
ARG TARGETPLATFORM
ARG TARGETOS
ARG TARGETARCH

# Build metadata for supply chain attestation
ARG BUILD_DATE
ARG VCS_REF
ARG VERSION

# Add ARG for VPN credentials
ARG VPN_USER
ARG VPN_PASS

# Set ENV from ARG
ENV VPN_USER=$VPN_USER
ENV VPN_PASS=$VPN_PASS

# Additional ENV for runtime variables needed by s6 scripts
ENV VPN_CLIENT=${VPN_CLIENT:-openvpn}
ENV VPN_CONFIG=${VPN_CONFIG:-}
ENV ENABLE_PRIVOXY=${ENABLE_PRIVOXY:-no}
ENV DEBUG=${DEBUG:-false}
# Default umask, gives rwxr-xr-x for dirs, rw-r--r-- for files. Handled by LSIO base scripts.
ENV UMASK=${UMASK:-022}
ENV NAME_SERVERS=${NAME_SERVERS:-}
ENV VPN_OPTIONS=${VPN_OPTIONS:-}
ENV LAN_NETWORK=${LAN_NETWORK:-}
ENV ADDITIONAL_PORTS=${ADDITIONAL_PORTS:-}
ENV PRIVOXY_PORT=${PRIVOXY_PORT:-8118}
ENV PRIVOXY_SKIP_FILE_SETUP=${PRIVOXY_SKIP_FILE_SETUP:-no}

# NZBGet Server1 Configuration ENV (populated by 02-nzbget-news-server.sh)
ENV NZBGET_S1_NAME=${NZBGET_S1_NAME:-}
ENV NZBGET_S1_HOST=${NZBGET_S1_HOST:-}
ENV NZBGET_S1_PORT=${NZBGET_S1_PORT:-}
ENV NZBGET_S1_USER=${NZBGET_S1_USER:-}
ENV NZBGET_S1_PASS=${NZBGET_S1_PASS:-}
ENV NZBGET_S1_CONN=${NZBGET_S1_CONN:-}
ENV NZBGET_S1_SSL=${NZBGET_S1_SSL:-}
ENV NZBGET_S1_LEVEL=${NZBGET_S1_LEVEL:-0}
ENV NZBGET_S1_ENABLED=${NZBGET_S1_ENABLED:-yes}

# Monitoring and Auto-restart ENV
ENV ENABLE_MONITORING=${ENABLE_MONITORING:-yes}
ENV MONITORING_PORT=${MONITORING_PORT:-8080}
ENV MONITORING_LOG_LEVEL=${MONITORING_LOG_LEVEL:-INFO}
ENV ENABLE_AUTO_RESTART=${ENABLE_AUTO_RESTART:-false}
ENV RESTART_COOLDOWN_SECONDS=${RESTART_COOLDOWN_SECONDS:-300}
ENV MAX_RESTART_ATTEMPTS=${MAX_RESTART_ATTEMPTS:-3}
ENV RESTART_ON_VPN_FAILURE=${RESTART_ON_VPN_FAILURE:-true}
ENV RESTART_ON_NZBGET_FAILURE=${RESTART_ON_NZBGET_FAILURE:-true}
ENV DISABLE_IP_LEAK_CHECK=${DISABLE_IP_LEAK_CHECK:-false}
ENV VPN_NETWORK=${VPN_NETWORK:-}
ENV NOTIFICATION_WEBHOOK_URL=${NOTIFICATION_WEBHOOK_URL:-}

# Platform information (for runtime detection)
ENV BUILDPLATFORM=${BUILDPLATFORM}
ENV TARGETPLATFORM=${TARGETPLATFORM}
ENV TARGETARCH=${TARGETARCH}

# Display build information
RUN echo "Building for platform: ${TARGETPLATFORM:-unknown}" && \
    echo "Target architecture: ${TARGETARCH:-unknown}" && \
    echo "Build platform: ${BUILDPLATFORM:-unknown}"

# Update packages for security before installing new ones
RUN apk update && \
    apk upgrade --no-cache && \
    rm -rf /var/cache/apk/*

# Install OpenVPN, WireGuard, Privoxy, Python3, jq, bc and tools
# Include platform-specific optimizations
RUN apk add --no-cache \
    openvpn \
    iptables \
    bash \
    curl \
    iproute2 \
    wireguard-tools \
    privoxy \
    python3 \
    py3-psutil \
    jq \
    bc \
    && for f in /etc/privoxy/*.new; do mv -n "$f" "${f%.new}"; done

# Platform-specific optimizations
RUN case "${TARGETARCH}" in \
    "arm64") \
        echo "Applying ARM64 optimizations..." && \
        # ARM64-specific optimizations
        echo "net.core.rmem_max = 16777216" >> /etc/sysctl.conf && \
        echo "net.core.wmem_max = 16777216" >> /etc/sysctl.conf && \
        echo "ARM64 optimizations applied" \
        ;; \
    "amd64") \
        echo "Applying AMD64 optimizations..." && \
        # AMD64-specific optimizations
        echo "AMD64 optimizations applied" \
        ;; \
    *) \
        echo "Using default configuration for architecture: ${TARGETARCH}" \
        ;; \
    esac

# Copy s6-overlay init scripts
COPY root/etc/cont-init.d/01-ensure-vpn-config-dirs.sh /etc/cont-init.d/01-ensure-vpn-config-dirs
COPY root/etc/cont-init.d/99-nzbget-news-server-override.sh /etc/cont-init.d/99-nzbget-news-server-override
COPY root/vpn-setup.sh /etc/cont-init.d/50-vpn-setup

# Copy enhanced healthcheck and monitoring scripts
COPY root/healthcheck.sh /root/healthcheck.sh
COPY root/monitoring-server.py /root/monitoring-server.py
COPY root/auto-restart.sh /root/auto-restart.sh

# Copy architecture detection script
COPY root/platform-info.sh /root/platform-info.sh

# Copy Privoxy configuration template and s6 service files
COPY config/privoxy/config /etc/privoxy/config.template
COPY config/privoxy/*.filter /etc/privoxy/
COPY config/privoxy/*.action /etc/privoxy/
COPY root_s6/privoxy/run /etc/s6-overlay/s6-rc.d/privoxy/run
COPY root_s6/monitoring/run /etc/s6-overlay/s6-rc.d/monitoring/run
COPY root_s6/auto-restart/run /etc/s6-overlay/s6-rc.d/auto-restart/run
COPY root_s6/openvpn/run /etc/s6-overlay/s6-rc.d/openvpn/run
COPY root_s6/openvpn/type /etc/s6-overlay/s6-rc.d/openvpn/type

# Setup s6-overlay services
RUN mkdir -p /etc/s6-overlay/s6-rc.d/user/contents.d && \
    echo "longrun" > /etc/s6-overlay/s6-rc.d/privoxy/type && \
    echo "longrun" > /etc/s6-overlay/s6-rc.d/monitoring/type && \
    echo "longrun" > /etc/s6-overlay/s6-rc.d/auto-restart/type && \

    touch /etc/s6-overlay/s6-rc.d/user/contents.d/privoxy && \
    touch /etc/s6-overlay/s6-rc.d/user/contents.d/monitoring && \
    touch /etc/s6-overlay/s6-rc.d/user/contents.d/auto-restart && \
    touch /etc/s6-overlay/s6-rc.d/user/contents.d/openvpn

# Make scripts executable
RUN chmod +x /etc/cont-init.d/* /root/healthcheck.sh /root/monitoring-server.py /root/auto-restart.sh \
    /root/platform-info.sh /etc/s6-overlay/s6-rc.d/privoxy/run /etc/s6-overlay/s6-rc.d/monitoring/run \
    /etc/s6-overlay/s6-rc.d/auto-restart/run /etc/s6-overlay/s6-rc.d/openvpn/run

# Enhanced healthcheck with more frequent checks and longer timeout for monitoring features
HEALTHCHECK --interval=30s --timeout=15s --start-period=2m --retries=3 \
  CMD /root/healthcheck.sh

# Expose monitoring port (optional, can be mapped in docker run/compose)
EXPOSE 8080

# Add build information labels with attestation metadata
LABEL org.opencontainers.image.title="nzbgetvpn" \
      org.opencontainers.image.description="NZBGet with VPN integration - Multi-architecture support" \
      org.opencontainers.image.vendor="magicalyak" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.source="https://github.com/magicalyak/nzbgetvpn" \
      org.opencontainers.image.documentation="https://github.com/magicalyak/nzbgetvpn/blob/main/README.md" \
      org.opencontainers.image.platform="${TARGETPLATFORM}" \
      org.opencontainers.image.architecture="${TARGETARCH}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.base.name="ghcr.io/linuxserver/nzbget:v25.4-ls224"

# Non-root user handling:
# The LinuxServer base image already provides proper non-root user functionality
# through PUID/PGID environment variables. Users can run as non-root by setting:
# PUID=1000 PGID=1000 (or any other valid UID/GID)
#
# IMPORTANT: Do NOT add a USER directive here!
# The LinuxServer s6-overlay REQUIRES root to initialize properly.
# It will automatically drop privileges to PUID/PGID after initialization.
# Adding USER breaks the container startup.
#
# Docker Scout may report "no non-root user" but this is a false positive
# for s6-overlay based containers. The container DOES run services as non-root
# via the PUID/PGID mechanism, which is more flexible than a fixed USER.

# CMD is inherited from linuxserver base
