# 🛡️ NZBGet VPN Docker 🚀

[![Docker Pulls](https://img.shields.io/docker/pulls/magicalyak/nzbgetvpn)](https://hub.docker.com/r/magicalyak/nzbgetvpn) [![Docker Stars](https://img.shields.io/docker/stars/magicalyak/nzbgetvpn)](https://hub.docker.com/r/magicalyak/nzbgetvpn) [![Build Status](https://github.com/magicalyak/nzbgetvpn/actions/workflows/build-and-publish.yml/badge.svg)](https://github.com/magicalyak/nzbgetvpn/actions/workflows/build-and-publish.yml) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Supercharge your NZBGet downloads with robust VPN security and an optional Privoxy web proxy! This Docker image bundles the latest NZBGet (from `linuxserver/nzbget`) with OpenVPN & WireGuard clients, all seamlessly managed by s6-overlay.

**➡️ Get it now from Docker Hub:**
```bash
docker pull magicalyak/nzbgetvpn:latest
```

## ✨ Core Features

*   **🔒 Secure NZBGet:** Runs the latest NZBGet with all its traffic automatically routed through your chosen VPN.
    *   🔑 **Default Login:** Username: `nzbget`, Password: `tegbzn6789` (Change this in NZBGet settings after first login!).
*   **⚙️ Automated News Server Setup:** Configure NZBGet's primary news server (Server1) directly through environment variables! No manual WebUI setup needed for your main server.
*   **🛡️ VPN Freedom:** Supports both **OpenVPN** and **WireGuard** VPN clients. You choose!
*   **📄 Simplified OpenVPN Credentials:**
    *   Use environment variables (`VPN_USER`/`VPN_PASS`).
    *   Or, simply place a `credentials.txt` file (username on line 1, password on L2) at `/config/openvpn/credentials.txt` inside the container. The script auto-detects it!
*   **🌐 Optional Privoxy:** Includes Privoxy for HTTP proxying. If enabled, Privoxy's traffic also uses the VPN.
*   **💻 Easy Host Access:** Access the NZBGet Web UI (port `6789`) and Privoxy (if enabled, default port `8118`) from your Docker host.
*   **🗂️ Simple Volume Mounts:** Map `/config` for settings & VPN files, and `/downloads` for your media. NZBGet's internal paths (`MainDir`, `LogFile`, etc.) are automatically configured for compatibility.
*   **🔧 Richly Configurable:** A comprehensive set of environment variables to tailor the container.
*   **🚦 Healthcheck:** Built-in healthcheck to monitor NZBGet and VPN operational status.

## 💾 Volume Mapping: Your Data, Your Rules

Properly mapping volumes is crucial for data persistence and custom configurations.

*   **`/config` (Required):** This is the heart of your persistent storage.
    *   **NZBGet Configuration:** Stores `nzbget.conf` (modified by startup scripts for server/path setup), history, scripts, etc.
    *   **VPN Configuration:**
        *   Place OpenVPN files (`.ovpn`, certs, keys) in `your_host_config_dir/openvpn/`.
        *   **OpenVPN Credentials (Optional File):** For file-based auth, put `credentials.txt` (user L1, pass L2) in `your_host_config_dir/openvpn/credentials.txt`.
        *   Place WireGuard files (`.conf`) in `your_host_config_dir/wireguard/`.
*   **`/downloads` (Required):** This is where NZBGet saves your completed downloads. Internal NZBGet directories like `completed`, `intermediate`, `tmp`, `queue`, and `nzb` are automatically configured by the startup script to reside within this volume (e.g., `/downloads/completed`, `/downloads/tmp`).

**Example Host Directory Structure 🌳:**
```
/opt/nzbgetvpn_data/      # Your chosen base directory on the host
├── config/                # Maps to /config in container
│   ├── nzbget.conf        # (NZBGet will create/manage this; our scripts will update it)
│   ├── openvpn/           # For OpenVPN files
│   │   └── your_provider.ovpn
│   │   └── credentials.txt  # Optional: user on L1, pass on L2
│   │   └── ca.crt         # And any other certs/keys
│   └── wireguard/         # For WireGuard files
│       └── wg0.conf
└── downloads/             # Maps to /downloads in container
    # NZBGet will use subdirs here like 'completed', 'tmp', etc.
```

**🔄 Migrating from `jshridha/docker-nzbgetvpn` or similar?**
*   Host directory previously for `/data` (downloads) ➡️ Map to **`/downloads`**.
*   Host directory previously for `/config` (NZBGet settings & VPN files) ➡️ Map to **`/config`**. Ensure VPN files are in `openvpn/` or `wireguard/` subfolders. For credentials, use `openvpn/credentials.txt`.

## 🚀 Quick Start Guide

This guide focuses on running the pre-built `magicalyak/nzbgetvpn` image from Docker Hub.

**1. Prepare Your Docker Host System 🛠️**

It's highly recommended to create your host directories *before* running the container. This ensures correct ownership and provides a clear place for your VPN and `.env` files.

*   **Why pre-create directories?**
    *   **Permissions:** Avoids `root`-owned directories if Docker auto-creates them, which can cause permission issues with NZBGet (running as `PUID`/`PGID`).
    *   **VPN Config:** Your VPN files *must* be in place before the first start.
    *   **Control:** You explicitly manage your data locations.

Example:
```bash
# Choose your base directory (e.g., /opt/nzbgetvpn_data or ~/nzbgetvpn_data)
HOST_DATA_DIR="/opt/nzbgetvpn_data"

mkdir -p "${HOST_DATA_DIR}/config/openvpn"
mkdir -p "${HOST_DATA_DIR}/config/wireguard"
mkdir -p "${HOST_DATA_DIR}/downloads"

echo "Host directories created under ${HOST_DATA_DIR}"
# Ensure correct ownership for PUID/PGID if needed.
```
Place your VPN files into `${HOST_DATA_DIR}/config/openvpn/` or `${HOST_DATA_DIR}/config/wireguard/`.

**2. Create Your `.env` Configuration File 📝**

In your `HOST_DATA_DIR` (e.g., `/opt/nzbgetvpn_data/.env`), create an `.env` file. See `.env.sample` for all options.

**Minimal `.env` for OpenVPN (using `VPN_USER`/`VPN_PASS`):**
```ini
# ---- VPN Settings ----
VPN_CLIENT=openvpn
VPN_CONFIG=/config/openvpn/your_provider.ovpn # Path *inside the container*
VPN_USER=your_vpn_username
VPN_PASS=your_vpn_password

# ---- System Settings ----
PUID=1000
PGID=1000
TZ=America/New_York

# ---- NZBGet Server1 Settings (Example) ----
NZBGET_S1_NAME=MyNewsServer
NZBGET_S1_HOST=news.example.com
NZBGET_S1_PORT=563
NZBGET_S1_USER=server_username
NZBGET_S1_PASS=server_password
NZBGET_S1_CONN=10
NZBGET_S1_SSL=yes # Use 'yes' for SSL, 'no' otherwise
# NZBGET_S1_LEVEL=0 # Optional: Server level (priority)
# NZBGET_S1_ENABLED=yes # Server is configured if NZBGET_S1_NAME is set
```

**Minimal `.env` for WireGuard:**
```ini
# ---- VPN Settings ----
VPN_CLIENT=wireguard
VPN_CONFIG=/config/wireguard/wg0.conf # Path *inside the container*

# ---- System Settings ----
PUID=1000
PGID=1000
TZ=America/New_York

# ---- NZBGet Server1 Settings (Example) ----
NZBGET_S1_NAME=MyNewsServer
NZBGET_S1_HOST=news.example.com
# ... (other NZBGET_S1_* settings as above) ...
```

**❗️ Important Notes for `.env`:**
*   `VPN_CONFIG` is the *container's internal path*.
*   If using `credentials.txt` for OpenVPN, ensure `VPN_USER`/`VPN_PASS` are unset/empty.
*   The first news server in NZBGet is automatically configured using `NZBGET_S1_*` variables. If `NZBGET_S1_NAME` is set, the server will be configured and active.

**3. Running with `docker run` 🐳**

Adjust `HOST_DATA_DIR` to your actual path.

**Universal Example (OpenVPN or WireGuard based on your `.env`):**
```bash
HOST_DATA_DIR="/opt/nzbgetvpn_data" # Or your preferred path, e.g., "$(pwd)/data"

docker run -d \\
  --name nzbgetvpn \\
  --rm \\
  --cap-add=NET_ADMIN \\
  # Add these for WireGuard if needed, harmless for OpenVPN:
  --cap-add=SYS_MODULE \\
  --sysctl="net.ipv4.conf.all.src_valid_mark=1" \\
  # --sysctl="net.ipv6.conf.all.disable_ipv6=0" \\ # If using IPv6 with WireGuard
  --device=/dev/net/tun \\
  -p 6789:6789 \\ # NZBGet WebUI
  # -p YOUR_HOST_PRIVOXY_PORT:8118 \\ # Uncomment if ENABLE_PRIVOXY=yes in .env
  -v "${HOST_DATA_DIR}/config:/config" \\
  -v "${HOST_DATA_DIR}/downloads:/downloads" \\
  --env-file "${HOST_DATA_DIR}/.env" \\
  magicalyak/nzbgetvpn:latest
```
*Remember to set `YOUR_HOST_PRIVOXY_PORT` if enabling Privoxy.*

**4. Running with Docker Compose ⚙️**

A `docker-compose.yml` is provided in the repository.
1.  Copy `docker-compose.yml` and `.env.sample` (rename to `.env`) to your project directory.
2.  **Edit `docker-compose.yml` volume paths** to match your host system.
3.  Configure your settings in the `.env` file.
4.  Run: `docker-compose up -d`

**Example `docker-compose.yml` snippet (edit paths!):**
```yaml
version: "3.8"

services:
  nzbgetvpn:
    image: magicalyak/nzbgetvpn:latest
    container_name: nzbgetvpn
    env_file:
      - .env # Load environment variables from .env file
    ports:
      - "6789:6789" # NZBGet Web UI
      # - "YOUR_HOST_PRIVOXY_PORT:8118" # Uncomment if ENABLE_PRIVOXY=yes
    volumes:
      # ‼️ IMPORTANT: Change './data/config' and './data/downloads'
      # to your actual host paths, e.g., /opt/nzbgetvpn_data/config
      - ./data/config:/config
      - ./data/downloads:/downloads
    cap_add:
      - NET_ADMIN
      - SYS_MODULE # Good to have for WireGuard, harmless for OpenVPN
    devices:
      - /dev/net/tun
    sysctls:
      - net.ipv4.conf.all.src_valid_mark=1
      # - net.ipv6.conf.all.disable_ipv6=0 # If using IPv6
    restart: unless-stopped
    # healthcheck: # Using built-in healthcheck from Dockerfile
    #   test: ["CMD", "/root/healthcheck.sh"]
    #   interval: 1m
    #   timeout: 10s
    #   retries: 3
    #   start_period: 2m
```

## 🔧 Environment Variables

This image uses environment variables for configuration. See `.env.sample` for a full list and descriptions.

### Key Variable Groups:

*   **VPN Settings (`VPN_CLIENT`, `VPN_CONFIG`, etc.):** Configure your VPN client (OpenVPN or WireGuard), specify config files, credentials.
*   **System Settings (`PUID`, `PGID`, `TZ`, `UMASK`):** Standard LinuxServer.io user/group mapping and timezone.
*   **NZBGet News Server Configuration (Server1 - `NZBGET_S1_*`):**
    *   These variables allow you to pre-configure the *first news server (Server1)* in NZBGet directly.
    *   An internal script (`99-nzbget-news-server-override.sh`) applies these to `/config/nzbget.conf` on startup.
    *   If `NZBGET_S1_NAME` and `NZBGET_S1_HOST` are set, the server will be configured and active.
    *   **Available variables:**
        *   `NZBGET_S1_NAME`: Recognizable name (e.g., `MyProvider`).
        *   `NZBGET_S1_HOST`: News server hostname or IP.
        *   `NZBGET_S1_PORT`: Port number (e.g., `563` for SSL, `119` for non-SSL).
        *   `NZBGET_S1_USER`: Username for the news server.
        *   `NZBGET_S1_PASS`: Password for the news server.
        *   `NZBGET_S1_CONN`: Number of connections (e.g., `10`).
        *   `NZBGET_S1_SSL`: Set to `yes` to enable SSL/TLS, `no` otherwise. This sets `Server1.Encryption` in `nzbget.conf`.
        *   `NZBGET_S1_LEVEL`: Server priority level (integer, default `0`).
        *   `NZBGET_S1_ENABLED`: Default `yes`. If you set `NZBGET_S1_NAME=""` (empty), Server1 effectively won't be configured by these env vars. The server is considered active if its core details (Name, Host) are provided.
*   **Privoxy Settings (`ENABLE_PRIVOXY`, `PRIVOXY_PORT`):** Enable and configure the Privoxy web proxy.
*   **Debugging & Network (`DEBUG`, `NAME_SERVERS`, `LAN_NETWORK`, `ADDITIONAL_PORTS`):** Advanced options for troubleshooting and network customization.

### Automated NZBGet Path Configuration:

The container's startup scripts automatically configure the following NZBGet paths in `nzbget.conf` to ensure they work correctly with the volume mounts and are stored appropriately:
*   `MainDir`: Set to `/downloads`
*   `DestDir`: Set to `/downloads/completed`
*   `InterDir`: Set to `/downloads/intermediate`
*   `ScriptDir`: Set to `/config/scripts` (standard for LSIO images)
*   `QueueDir`: Set to `/downloads/queue`
*   `TempDir`: Set to `/downloads/tmp`
*   `NzbDir`: Set to `/downloads/nzb`
*   `LogFile`: Set to `/config/nzbget.log`

You generally do not need to (and should not) override these path settings via environment variables unless you have a very specific custom setup.

## 🛠️ Building the Image Locally (Optional)

If you want to build the image yourself (e.g., for development):
```bash
# Clone the repository
git clone https://github.com/magicalyak/nzbgetvpn.git
cd nzbgetvpn

# Build (optionally pass VPN_USER and VPN_PASS as build ARGs if needed for testing)
docker build -t my-nzbgetvpn .
# docker build --build-arg VPN_USER="myuser" --build-arg VPN_PASS="mypass" -t my-nzbgetvpn .
```

## 🚦 Healthcheck Details

The container includes a healthcheck script (`/root/healthcheck.sh`) that verifies:
1.  **VPN Connectivity:** Checks if the `tun0` (OpenVPN) or a `wg` interface (WireGuard) exists.
2.  **NZBGet Responsiveness:** Attempts to connect to the NZBGet web interface locally.

## 🤝 Contributing

Contributions, issues, and feature requests are welcome! Please feel free to fork, submit a PR, or open an issue.

## 🙏 Acknowledgements

This project is inspired by the need for a secure, easy-to-use NZBGet setup with VPN support. Thanks to the `linuxserver/nzbget` team for their excellent base image and to the OpenVPN, WireGuard, and Privoxy communities for their contributions to open-source software.
Special thanks also to the maintainers of the [jshridha/docker-nzbgetvpn](https://github.com/jshridha/docker-nzbgetvpn) repository, from which this project drew initial inspiration and some foundational concepts.

## 📜 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.