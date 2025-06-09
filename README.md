# 🛡️ NZBGet VPN Docker 🚀

[![Docker Pulls](https://img.shields.io/docker/pulls/magicalyak/nzbgetvpn)](https://hub.docker.com/r/magicalyak/nzbgetvpn) [![Docker Stars](https://img.shields.io/docker/stars/magicalyak/nzbgetvpn)](https://hub.docker.com/r/magicalyak/nzbgetvpn) [![Build Status](https://github.com/magicalyak/nzbgetvpn/actions/workflows/build-and-publish.yml/badge.svg)](https://github.com/magicalyak/nzbgetvpn/actions/workflows/build-and-publish.yml) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Supercharge your NZBGet downloads with robust VPN security and an optional Privoxy web proxy! This Docker image bundles the latest NZBGet (from `linuxserver/nzbget`) with OpenVPN & WireGuard clients, all seamlessly managed by s6-overlay.

**➡️ Get it now from Docker Hub:**

```bash
docker pull magicalyak/nzbgetvpn:latest
```

## ✨ Core Features

* **🔒 Secure NZBGet:** Runs the latest NZBGet with all its traffic automatically routed through your chosen VPN.
  * 🔑 **Default Login:** Username: `nzbget`, Password: `tegbzn6789` (Change this in NZBGet settings after first login!).
* **⚙️ Automated News Server Setup:** Configure NZBGet's primary news server (Server1) directly through environment variables! No manual WebUI setup needed for your main server.
* **🛡️ VPN Freedom:** Supports both **OpenVPN** and **WireGuard** VPN clients. You choose!
* **📄 Simplified OpenVPN Credentials:**
  * Use environment variables (`VPN_USER`/`VPN_PASS`).
  * Or, simply place a `credentials.txt` file (username on line 1, password on L2) at `/config/openvpn/credentials.txt` inside the container. The script auto-detects it!
* **🌐 Optional Privoxy:** Includes Privoxy for HTTP proxying. If enabled, Privoxy's traffic also uses the VPN.
* **💻 Easy Host Access:** Access the NZBGet Web UI (port `6789`) and Privoxy (if enabled, default port `8118`) from your Docker host.
* **🗂️ Simple Volume Mounts:** Map `/config` for settings & VPN files, and `/downloads` for your media. NZBGet's internal paths (`MainDir`, `LogFile`, etc.) are automatically configured for compatibility.
* **🔧 Richly Configurable:** A comprehensive set of environment variables to tailor the container.
* **🚦 Healthcheck:** Built-in healthcheck to monitor NZBGet and VPN operational status.
* **📈 Prometheus Exporter:** Optional exporter to expose NZBGet metrics for Prometheus, InfluxDB, and Grafana.

## 💾 Volume Mapping: Your Data, Your Rules

Properly mapping volumes is crucial for data persistence and custom configurations.

* **`/config` (Required):** This is the heart of your persistent storage.
  * **NZBGet Configuration:** Stores `nzbget.conf` (modified by startup scripts for server/path setup), history, scripts, etc.
  * **VPN Configuration:**
    * Place OpenVPN files (`.ovpn`, certs, keys) in `your_host_config_dir/openvpn/`.
    * **OpenVPN Credentials (Optional File):** For file-based auth, put `credentials.txt` (user L1, pass L2) in `your_host_config_dir/openvpn/credentials.txt`.
    * Place WireGuard files (`.conf`) in `your_host_config_dir/wireguard/`.
* **`/downloads` (Required):** This is where NZBGet saves your completed downloads. Internal NZBGet directories like `completed`, `intermediate`, `tmp`, `queue`, and `nzb` are automatically configured by the startup script to reside within this volume (e.g., `/downloads/completed`, `/downloads/tmp`).

**Example Host Directory Structure 🌳:**

```text
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

* Host directory previously for `/data` (downloads) ➡️ Map to **`/downloads`**.
* Host directory previously for `/config` (NZBGet settings & VPN files) ➡️ Map to **`/config`**. Ensure VPN files are in `openvpn/` or `wireguard/` subfolders. For credentials, use `openvpn/credentials.txt`.

## 🚀 Quick Start Guide

This guide focuses on running the pre-built `magicalyak/nzbgetvpn` image from Docker Hub.

### 1. Prepare Your Docker Host System 🛠️

It's highly recommended to create your host directories *before* running the container. This ensures correct ownership and provides a clear place for your VPN configuration files.

* **Why pre-create directories?**
  * **Permissions:** Avoids `root`-owned directories if Docker auto-creates them, which can cause permission issues with NZBGet (running as `PUID`/`PGID`).
  * **VPN Config:** Your VPN files *must* be in place before the first start.
  * **Control:** You explicitly manage your data locations.

Example:

```bash
# Choose your base directory (e.g., /opt/nzbgetvpn_data or ~/nzbgetvpn_data)
HOST_DATA_DIR="/opt/nzbgetvpn_data" # CHANGEME

mkdir -p "${HOST_DATA_DIR}/config/openvpn"
mkdir -p "${HOST_DATA_DIR}/config/wireguard"
mkdir -p "${HOST_DATA_DIR}/downloads"

echo "Host directories created under ${HOST_DATA_DIR}"
# Ensure correct ownership for PUID/PGID if needed, matching what you'll use below.
```

Place your VPN configuration files (e.g., `your_provider.ovpn`, `wg0.conf`, and optionally `credentials.txt` for OpenVPN) into the appropriate subfolders on your host:

* OpenVPN: `${HOST_DATA_DIR}/config/openvpn/`
* WireGuard: `${HOST_DATA_DIR}/config/wireguard/`

**2. Running with `docker run` (Minimal Setup) 🐳**

This is the quickest way to get started. Adjust `HOST_DATA_DIR` to your path from Step 1. Remember to replace all `CHANGEME` placeholders with your actual values.

**Minimal OpenVPN Example (Direct Environment Variables):**

```bash
# Define your host data directory (must match Step 1)
HOST_DATA_DIR="/opt/nzbgetvpn_data" # CHANGEME

docker run -d \
  --name nzbgetvpn \
  --rm \
  --cap-add=NET_ADMIN \
  --device=/dev/net/tun \
  -p 6789:6789 \ # NZBGet WebUI
  -v "${HOST_DATA_DIR}/config:/config" \
  -v "${HOST_DATA_DIR}/downloads:/downloads" \
  -e VPN_CLIENT=openvpn \
  -e VPN_CONFIG=/config/openvpn/your_provider.ovpn \ # CHANGEME to your .ovpn file name
  # -e VPN_USER=your_vpn_username \ # CHANGEME (or use credentials.txt)
  # -e VPN_PASS=your_vpn_password \ # CHANGEME (or use credentials.txt)
  -e PUID=1000 \ # CHANGEME to your user's ID
  -e PGID=1000 \ # CHANGEME to your user's group ID
  -e TZ=America/New_York \ # CHANGEME to your timezone
  # ---- Optional: Pre-configure NZBGet's First News Server (Server1) ----
  # If you omit these, configure your news server in NZBGet WebUI after startup.
  # -e NZBGET_S1_NAME=MyNewsServer \ # CHANGEME (e.g., EasyNews)
  # -e NZBGET_S1_HOST=news.example.com \ # CHANGEME (news server address)
  # -e NZBGET_S1_PORT=563 \ # CHANGEME (563 for SSL, 119 for non-SSL)
  # -e NZBGET_S1_USER=server_username \ # CHANGEME
  # -e NZBGET_S1_PASS=server_password \ # CHANGEME
  # -e NZBGET_S1_CONN=10 \ # CHANGEME (number of connections)
  # -e NZBGET_S1_SSL=yes \ # CHANGEME ('yes' for SSL, 'no' otherwise)
  # -e NZBGET_S1_LEVEL=0 \ # Optional: Server level (priority)
  # Add other -e flags for more options (see "Environment Variables" section)
  magicalyak/nzbgetvpn:latest
```

* If your OpenVPN file uses `auth-user-pass /config/openvpn/credentials`, create `${HOST_DATA_DIR}/config/openvpn/credentials` (username on line 1, password on line 2) and you can omit/comment out the `VPN_USER`/`VPN_PASS` environment variables.

**Minimal WireGuard Example (Direct Environment Variables):**

```bash
# Define your host data directory (must match Step 1)
HOST_DATA_DIR="/opt/nzbgetvpn_data" # CHANGEME

docker run -d \
  --name nzbgetvpn \
  --rm \
  --cap-add=NET_ADMIN \
  --cap-add=SYS_MODULE \ # May be needed for WireGuard kernel module
  --sysctl="net.ipv4.conf.all.src_valid_mark=1" \ # Recommended for WireGuard
  # --sysctl="net.ipv6.conf.all.disable_ipv6=0" \ # Uncomment if using IPv6 with WireGuard
  --device=/dev/net/tun \
  -p 6789:6789 \ # NZBGet WebUI
  -v "${HOST_DATA_DIR}/config:/config" \
  -v "${HOST_DATA_DIR}/downloads:/downloads" \
  -e VPN_CLIENT=wireguard \
  -e VPN_CONFIG=/config/wireguard/wg0.conf \ # CHANGEME to your .conf file name
  -e PUID=1000 \ # CHANGEME
  -e PGID=1000 \ # CHANGEME
  -e TZ=America/New_York \ # CHANGEME
  # ---- Optional: Pre-configure NZBGet's First News Server (Server1) ----
  # If you omit these, configure your news server in NZBGet WebUI after startup.
  # -e NZBGET_S1_NAME=MyNewsServer \ # CHANGEME
  # -e NZBGET_S1_HOST=news.example.com \ # CHANGEME
  # -e NZBGET_S1_PORT=563 \ # CHANGEME
  # -e NZBGET_S1_USER=server_username \ # CHANGEME
  # -e NZBGET_S1_PASS=server_password \ # CHANGEME
  # -e NZBGET_S1_CONN=10 \ # CHANGEME
  # -e NZBGET_S1_SSL=yes \ # CHANGEME
  # -e NZBGET_S1_LEVEL=0 \
  # Add other -e flags for more options (see "Environment Variables" section)
  magicalyak/nzbgetvpn:latest
```

**3. Recommended: Using an `.env` File with `docker run` 📝**

For a cleaner `docker run` command, especially when using many environment variables, you can place them in an `.env` file.

1. Create an `.env` file in your `HOST_DATA_DIR` (e.g., `${HOST_DATA_DIR}/.env`).
2. Add your variables to this file (see `.env.sample` for all options or use the examples below). Remember to replace `CHANGEME` values.

**Example Minimal `.env` for OpenVPN:**

```ini
# ---- VPN Settings ----
VPN_CLIENT=openvpn
VPN_CONFIG=/config/openvpn/your_provider.ovpn # CHANGEME: Path *inside the container* to your .ovpn file
# VPN_USER=your_vpn_username # CHANGEME (or use credentials.txt)
# VPN_PASS=your_vpn_password # CHANGEME (or use credentials.txt)

# ---- System Settings ----
PUID=1000 # CHANGEME
PGID=1000 # CHANGEME
TZ=America/New_York # CHANGEME

# ---- NZBGet Server1 Settings (Example) ----
NZBGET_S1_NAME=MyNewsServer # CHANGEME
NZBGET_S1_HOST=news.example.com # CHANGEME
NZBGET_S1_PORT=563 # CHANGEME
NZBGET_S1_USER=server_username # CHANGEME
NZBGET_S1_PASS=server_password # CHANGEME
NZBGET_S1_CONN=10 # CHANGEME
NZBGET_S1_SSL=yes # CHANGEME ('yes' for SSL, 'no' otherwise)
# NZBGET_S1_LEVEL=0 # Optional
```

*(For WireGuard, set `VPN_CLIENT=wireguard` and `VPN_CONFIG=/config/wireguard/your_config.conf`)*

Then run the container using `--env-file`:

```bash
HOST_DATA_DIR="/opt/nzbgetvpn_data" # CHANGEME

docker run -d \
  --name nzbgetvpn \
  --rm \
  --cap-add=NET_ADMIN \
  # Add these for WireGuard if using it (based on .env), harmless for OpenVPN:
  --cap-add=SYS_MODULE \
  --sysctl="net.ipv4.conf.all.src_valid_mark=1" \
  # --sysctl="net.ipv6.conf.all.disable_ipv6=0" \
  --device=/dev/net/tun \
  -p 6789:6789 \
  # -p YOUR_HOST_PRIVOXY_PORT:8118 \ # Uncomment if ENABLE_PRIVOXY=yes in .env & set port
  -v "${HOST_DATA_DIR}/config:/config" \
  -v "${HOST_DATA_DIR}/downloads:/downloads" \
  --env-file "${HOST_DATA_DIR}/.env" \
  magicalyak/nzbgetvpn:latest
```

*Remember to also set `YOUR_HOST_PRIVOXY_PORT` in the command if you enable Privoxy in your `.env` file and want to map its port.*

### 4. Using Docker Compose ⚙️

A `docker-compose.yml` is provided in the repository. It's configured to use an `.env` file in the same directory by default.

1. Copy `docker-compose.yml` and `.env.sample` (rename to `.env`) to your project directory (e.g., `${HOST_DATA_DIR}`).
2. **Edit `docker-compose.yml` volume paths if needed.** The defaults (`./config:/config`, `./downloads:/downloads`) assume your `config` and `downloads` directories (from Step 1) are subdirectories of where your `docker-compose.yml` is located. If your `HOST_DATA_DIR` *is* where `docker-compose.yml` resides, and `config` and `downloads` are inside it, the defaults should work.
3. Configure your settings in the `.env` file (see example above or `.env.sample`).
4. Run from the directory containing `docker-compose.yml` and `.env`: `docker-compose up -d`

**Example `docker-compose.yml` snippet (paths are relative to `docker-compose.yml` location):**

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
      - "9452:9452" # Prometheus Exporter
      # - "YOUR_HOST_PRIVOXY_PORT:8118" # Uncomment if ENABLE_PRIVOXY=yes in .env & set port
    volumes:
      # ‼️ IMPORTANT: Adjust host paths if your structure differs.
      # These examples assume 'config' and 'downloads' folders are
      # in the same directory as this docker-compose.yml.
      - ./config:/config
      - ./downloads:/downloads
    cap_add:
      - NET_ADMIN
      - SYS_MODULE # Good to have for WireGuard, harmless for OpenVPN
    devices:
      - /dev/net/tun
    sysctls:
      - net.ipv4.conf.all.src_valid_mark=1
      # - net.ipv6.conf.all.disable_ipv6=0 # If using IPv6
    restart: unless-stopped
```

## 🔧 Environment Variables

This image uses environment variables for configuration. See `.env.sample` for a full list and descriptions. You can pass these using multiple `-e VARIABLE=value` flags in your `docker run` command, or by using an `.env` file with `docker run --env-file` or with `docker-compose`.

### Key Variable Groups

* **VPN Settings (`VPN_CLIENT`, `VPN_CONFIG`, etc.):** Configure your VPN client (OpenVPN or WireGuard), specify config files, credentials.
* **System Settings (`PUID`, `PGID`, `TZ`, `UMASK`):** Standard LinuxServer.io user/group mapping and timezone.
* **NZBGet News Server Configuration (Server1 - `NZBGET_S1_*`):**
  * These variables allow you to pre-configure the *first news server (Server1)* in NZBGet directly.
  * An internal script (`99-nzbget-news-server-override.sh`) applies these to `/config/nzbget.conf` on startup.
  * If `NZBGET_S1_NAME` and `NZBGET_S1_HOST` are set, the server will be configured and active.
  * **Available variables:**
    * `NZBGET_S1_NAME`: Recognizable name (e.g., `MyProvider`).
    * `NZBGET_S1_HOST`: News server hostname or IP.
    * `NZBGET_S1_PORT`: Port number (e.g., `563` for SSL, `119` for non-SSL).
    * `NZBGET_S1_USER`: Username for the news server.
    * `NZBGET_S1_PASS`: Password for the news server.
    * `NZBGET_S1_CONN`: Number of connections (e.g., `10`).
    * `NZBGET_S1_SSL`: Set to `yes` to enable SSL/TLS, `no` otherwise. This sets `Server1.Encryption` in `nzbget.conf`.
    * `NZBGET_S1_LEVEL`: Server priority level (integer, default `0`).
    * `NZBGET_S1_ENABLED`: Default `yes`. If you set `NZBGET_S1_NAME=""` (empty), Server1 effectively won't be configured by these env vars. The server is considered active if its core details (Name, Host) are provided.
* **Privoxy Settings (`ENABLE_PRIVOXY`, `PRIVOXY_PORT`):** Enable and configure the Privoxy web proxy.
* **Debugging & Network (`DEBUG`, `NAME_SERVERS`, `LAN_NETWORK`, `ADDITIONAL_PORTS`):** Advanced options for troubleshooting and network customization.

### Automated NZBGet Path Configuration

The container's startup scripts automatically configure the following NZBGet paths in `nzbget.conf` to ensure they work correctly with the volume mounts and are stored appropriately:

* `MainDir`: Set to `/downloads`
* `DestDir`: Set to `/downloads/completed`
* `InterDir`: Set to `/downloads/intermediate`
* `ScriptDir`: Set to `/config/scripts` (standard for LSIO images)
* `QueueDir`: Set to `/downloads/queue`
* `TempDir`: Set to `/downloads/tmp`
* `NzbDir`: Set to `/downloads/nzb`
* `LogFile`: Set to `/config/nzbget.log`

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

1. **VPN Connectivity:** Checks if the `tun0` (OpenVPN) or a `wg` interface (WireGuard) exists.
2. **NZBGet Responsiveness:** Attempts to connect to the NZBGet web interface locally.

## 📈 Monitoring with Prometheus & Grafana

This image includes the lightweight and efficient [`frebib/nzbget-exporter`](https://github.com/frebib/nzbget-exporter) to expose detailed NZBGet statistics for your favorite monitoring platforms.

### 1. Enabling the Exporter

To activate the exporter, you must:

1. **Set the environment variable:**
    * `ENABLE_EXPORTER=yes`
2. **Expose the exporter's port** by uncommenting the relevant line in your `docker-compose.yml` or adding the argument to your `docker run` command.

The exporter runs on port `9452` inside the container.

**`docker-compose.yml` Example:**

```yaml
services:
  nzbgetvpn:
    # ... other settings
    ports:
      - "6789:6789" # NZBGet Web UI
      # - "8118:8118" # Privoxy. Uncomment if you set ENABLE_PRIVOXY=yes
      - "9452:9452" # Prometheus Exporter. Uncomment if you set ENABLE_EXPORTER=yes
    # ... other settings
```

**`docker run` Example:**

```bash
docker run \
  # ... other arguments
  -e ENABLE_EXPORTER=yes \
  -p 9452:9452 \
  magicalyak/nzbgetvpn:latest
```

### 2. Prometheus Configuration

To get Prometheus to scrape the metrics, add the following job to your `prometheus.yml` configuration file. Replace `<your_docker_host_ip>` with the actual IP address of the machine running this Docker container.

```yaml
scrape_configs:
  - job_name: 'nzbgetvpn'
    static_configs:
      - targets: ['<your_docker_host_ip>:9452']
```

### 3. Grafana Dashboard & InfluxDB

* **Grafana:** The `frebib/nzbget-exporter` project provides an excellent starter Grafana dashboard. You can find the JSON model in their repository's `grafana` directory and import it into your Grafana instance for instant visualizations.
* **InfluxDB:** You can feed these metrics into InfluxDB by using the Telegraf `inputs.prometheus` plugin. Configure Telegraf to scrape the `http://<your_docker_host_ip>:9452/metrics` endpoint.

## 🤝 Contributing

Contributions, issues, and feature requests are welcome! Please feel free to fork, submit a PR, or open an issue.

## 🙏 Acknowledgements

This project is inspired by the need for a secure, easy-to-use NZBGet setup with VPN support. Thanks to the `linuxserver/nzbget` team for their excellent base image and to the OpenVPN, WireGuard, and Privoxy communities for their contributions to open-source software.
Special thanks also to the maintainers of the [jshridha/docker-nzbgetvpn](https://github.com/jshridha/docker-nzbgetvpn) repository, from which this project drew initial inspiration and some foundational concepts.

## 📜 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
