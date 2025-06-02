# 🛡️ NZBGet VPN Docker 🚀

[![Docker Pulls](https://img.shields.io/docker/pulls/magicalyak/nzbgetvpn)](https://hub.docker.com/r/magicalyak/nzbgetvpn) [![Docker Stars](https://img.shields.io/docker/stars/magicalyak/nzbgetvpn)](https://hub.docker.com/r/magicalyak/nzbgetvpn) [![Build Status](https://github.com/magicalyak/nzbgetvpn/actions/workflows/build-and-publish.yml/badge.svg)](https://github.com/magicalyak/nzbgetvpn/actions/workflows/build-and-publish.yml) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Supercharge your NZBGet downloads with robust VPN security and an optional Privoxy web proxy! This Docker image bundles the latest NZBGet (from `linuxserver/nzbget`) with OpenVPN & WireGuard clients, all seamlessly managed by s6-overlay.

**➡️ Get it now from Docker Hub:**
```bash
docker pull magicalyak/nzbgetvpn:latest
```

## ✨ Core Features

*   **🔒 Secure NZBGet:** Runs the latest NZBGet with all its traffic automatically routed through your chosen VPN.
    *   🔑 **Default Login:** Username: `nzbget`, Password: `tegbzn6789` (Don't forget to change this in NZBGet settings!)
*   **🛡️ VPN Freedom:** Supports both **OpenVPN** and **WireGuard** VPN clients. You choose!
*   **📄 Simplified OpenVPN Credentials:**
    *   Use environment variables (`VPN_USER`/`VPN_PASS`).
    *   Or, simply place a `credentials.txt` file (username on line 1, password on L2) at `/config/openvpn/credentials.txt` inside the container. The script auto-detects it!
*   **🌐 Optional Privoxy:** Includes Privoxy for HTTP proxying. If enabled, Privoxy's traffic also uses the VPN.
*   **💻 Easy Host Access:** Access the NZBGet Web UI (port `6789`) and Privoxy (if enabled, default port `8118`) from your Docker host as if they were local services.
*   **🗂️ Simple Volume Mounts:** Just map `/config` for NZBGet data & all VPN configurations, and `/downloads` for your completed media.
*   **⚙️ Highly Configurable:** A rich set of environment variables to perfectly tailor the container to your needs.
*   **🚦 Healthcheck:** Built-in healthcheck to monitor NZBGet and VPN operational status.

## 💾 Volume Mapping: Your Data, Your Rules

Properly mapping volumes is crucial for data persistence and custom configurations.

*   **`/config` (Required):** This is the heart of your persistent storage.
    *   **NZBGet Configuration:** Stores all NZBGet settings, history, scripts, and queue files (managed by the `linuxserver/nzbget` base).
    *   **VPN Configuration:**
        *   Place OpenVPN files (`.ovpn`, certs, keys) in `your_host_config_dir/openvpn/`.
        *   **OpenVPN Credentials (Optional File):** For file-based auth, put `credentials.txt` (user L1, pass L2) in `your_host_config_dir/openvpn/credentials.txt`. It's used if `VPN_USER`/`VPN_PASS` are unset.
        *   Place WireGuard files (`.conf`) in `your_host_config_dir/wireguard/`.
*   **`/downloads` (Required):** This is where NZBGet saves your completed downloads. Subdirectories (`intermediate`, `completed`, `nzb`, etc.) are managed by NZBGet's settings within this volume.

**Example Host Directory Structure 🌳:**
```
/opt/nzbgetvpn_data/      # Your chosen base directory on the host
├── config/                # Maps to /config in container
│   ├── nzbget.conf        # (NZBGet will create/manage this)
│   ├── openvpn/           # For OpenVPN files
│   │   └── your_provider.ovpn
│   │   └── credentials.txt  # Optional: user on L1, pass on L2
│   │   └── ca.crt         # And any other certs/keys
│   │   └── wg0.conf
└── downloads/             # Maps to /downloads in container
    ├── movies/            # (NZBGet might create these, or you can)
    └── tv/
```

**🔄 Migrating from `jshridha/docker-nzbgetvpn` or similar?**
*   Host directory previously for `/data` (downloads) ➡️ Map to **`/downloads`**.
*   Host directory previously for `/config` (NZBGet settings & VPN files) ➡️ Map to **`/config`**. Ensure VPN files are in `openvpn/` or `wireguard/` subfolders. For credentials, use `openvpn/credentials.txt`.

## 🚀 Quick Start Guide

This guide focuses on running the pre-built `magicalyak/nzbgetvpn` image from Docker Hub.

**1. Prepare Your Docker Host System 🛠️**

Before running the container for the first time, it's highly recommended to create the necessary directory structure on your Docker host. While Docker *can* sometimes create missing host paths for volume mounts, doing so manually ensures correct ownership and provides a clear place for your essential VPN configuration files.

*   **Why pre-create directories?**
    *   **Permissions:** If Docker auto-creates directories, they are owned by `root`. This often causes permission issues when NZBGet (running with `PUID`/`PGID` from your `.env` file) tries to write data. Creating them yourself allows you to set the correct ownership, which the container will then respect via `PUID`/`PGID`.
    *   **VPN Configuration:** Your VPN client configuration files (`.ovpn`, `credentials.txt`, `.conf`) *must* exist in the designated subfolders (`config/openvpn/` or `config/wireguard/`) *before* the container starts so they can be mounted correctly.
    *   **Control:** You have explicit control over your data storage locations.

Create your base configuration and downloads directories. Example:
```bash
# Choose your base directory on the host (e.g., /opt/nzbgetvpn_data or ~/nzbgetvpn_data)
HOST_DATA_DIR="/opt/nzbgetvpn_data"

# Create the main config and downloads directories
mkdir -p "${HOST_DATA_DIR}/config"
mkdir -p "${HOST_DATA_DIR}/downloads"

# Create subdirectories for VPN configurations
mkdir -p "${HOST_DATA_DIR}/config/openvpn"
mkdir -p "${HOST_DATA_DIR}/config/wireguard"

echo "Host directories created under ${HOST_DATA_DIR}"
# Important: Ensure the user/group that will run the 'docker run' command (or Docker daemon user)
# has appropriate permissions for these directories, or adjust PUID/PGID in your .env file accordingly.
```

Place your VPN configuration files into the appropriate subfolders on your host:
*   OpenVPN Config & Credentials: e.g., `${HOST_DATA_DIR}/config/openvpn/your_provider.ovpn` and optionally `${HOST_DATA_DIR}/config/openvpn/credentials.txt`.
*   WireGuard Config: e.g., `${HOST_DATA_DIR}/config/wireguard/wg0.conf`.

**2. Create Your `.env` Configuration File 📝**

Create a file named `.env` (e.g., `${HOST_DATA_DIR}/.env`). Refer to `.env.sample` for all options.

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
TZ=America/New_York # Set to your timezone!
```

**Minimal `.env` for OpenVPN (using `/config/openvpn/credentials.txt`):**
```ini
# ---- VPN Settings ----
VPN_CLIENT=openvpn
VPN_CONFIG=/config/openvpn/your_provider.ovpn # Path *inside the container*
# Ensure your_host_config_dir/openvpn/credentials.txt exists.
# VPN_USER and VPN_PASS must be empty or commented out.
# VPN_USER=
# VPN_PASS=

# ---- System Settings ----
PUID=1000
PGID=1000
TZ=America/New_York # Set to your timezone!
```

**Minimal `.env` for WireGuard:**
```ini
# ---- VPN Settings ----
VPN_CLIENT=wireguard
VPN_CONFIG=/config/wireguard/wg0.conf # Path *inside the container*

# ---- System Settings ----
PUID=1000
PGID=1000
TZ=America/New_York # Set to your timezone!
```

**❗️ Important Notes for `.env`:**
*   `VPN_CONFIG` path is **always the *container's internal path***.
*   If using `credentials.txt`, ensure `VPN_USER`/`VPN_PASS` are unset/empty.
*   Set `PUID`, `PGID`, and `TZ` to match your system and preferences.
*   Consult `.env.sample` for all available environment variables.

**3. Running with `docker run` 🐳**

Choose the example that best fits your needs. Remember to adjust `HOST_DATA_DIR` to your actual host path where your `.env` file, VPN configurations, and downloads will reside.

**Minimal OpenVPN Example:**

This example assumes your `.env` file is configured for OpenVPN (e.g., `VPN_CLIENT=openvpn` and `VPN_CONFIG`, `VPN_USER`, `VPN_PASS` are set).

```bash
# Define your host data directory (must match where you put config and downloads)
HOST_DATA_DIR="/opt/nzbgetvpn_data" # Or your preferred path, e.g., "$(pwd)/data"

docker run -d \
  --name nzbgetvpn \
  --rm \
  --cap-add=NET_ADMIN \
  --device=/dev/net/tun \
  -p 6789:6789 \
  -v "${HOST_DATA_DIR}/config:/config" \
  -v "${HOST_DATA_DIR}/downloads:/downloads" \
  --env-file "${HOST_DATA_DIR}/.env" \
  magicalyak/nzbgetvpn:latest
```

**Minimal WireGuard Example:**

This example assumes your `.env` file is configured for WireGuard (e.g., `VPN_CLIENT=wireguard` and `VPN_CONFIG` is set to your WireGuard config file like `/config/wireguard/wg0.conf`).

```bash
# Define your host data directory
HOST_DATA_DIR="/opt/nzbgetvpn_data" # Or your preferred path

docker run -d \
  --name nzbgetvpn \
  --rm \
  --cap-add=NET_ADMIN \
  --cap-add=SYS_MODULE \ # May be needed for WireGuard kernel module
  --sysctl="net.ipv4.conf.all.src_valid_mark=1" \ # Recommended for WireGuard
  # --sysctl="net.ipv6.conf.all.disable_ipv6=0" \ # Uncomment if using IPv6 with WireGuard
  --device=/dev/net/tun \
  -p 6789:6789 \
  -v "${HOST_DATA_DIR}/config:/config" \
  -v "${HOST_DATA_DIR}/downloads:/downloads" \
  --env-file "${HOST_DATA_DIR}/.env" \
  magicalyak/nzbgetvpn:latest
```

**Recommended OpenVPN Example:**

This includes common settings like `PUID`/`PGID` (set in your `.env` file), `TZ`, and mapping the Privoxy port (if you intend to use it).

```bash
# Define your host data directory
HOST_DATA_DIR="/opt/nzbgetvpn_data" # Or your preferred path

docker run -d \
  --name nzbgetvpn \
  --rm \
  --cap-add=NET_ADMIN \
  --device=/dev/net/tun \
  -p 6789:6789 \
  # -p YOUR_HOST_PRIVOXY_PORT:8118 \ # Uncomment and set host port if ENABLE_PRIVOXY=yes in .env
  -v "${HOST_DATA_DIR}/config:/config" \
  -v "${HOST_DATA_DIR}/downloads:/downloads" \
  --env-file "${HOST_DATA_DIR}/.env" \
  # Ensure PUID, PGID, and TZ are set in your .env file
  magicalyak/nzbgetvpn:latest
```
*For `YOUR_HOST_PRIVOXY_PORT`, choose an available port on your Docker host, e.g., `8118`.*

**Recommended WireGuard Example:**

Similar to the recommended OpenVPN example, but with WireGuard-specific capabilities and sysctl settings.

```bash
# Define your host data directory
HOST_DATA_DIR="/opt/nzbgetvpn_data" # Or your preferred path

docker run -d \
  --name nzbgetvpn \
  --rm \
  --cap-add=NET_ADMIN \
  --cap-add=SYS_MODULE \
  --sysctl="net.ipv4.conf.all.src_valid_mark=1" \
  # --sysctl="net.ipv6.conf.all.disable_ipv6=0" \
  --device=/dev/net/tun \
  -p 6789:6789 \
  # -p YOUR_HOST_PRIVOXY_PORT:8118 \ # Uncomment and set host port if ENABLE_PRIVOXY=yes in .env
  -v "${HOST_DATA_DIR}/config:/config" \
  -v "${HOST_DATA_DIR}/downloads:/downloads" \
  --env-file "${HOST_DATA_DIR}/.env" \
  # Ensure PUID, PGID, and TZ are set in your .env file
  magicalyak/nzbgetvpn:latest
```
*For `YOUR_HOST_PRIVOXY_PORT`, choose an available port on your Docker host, e.g., `8118`.*

**4. Running with Docker Compose 🐳**

For a more declarative approach, a `docker-compose.yml` file is provided in the root of this repository. It's configured to use the `.env` file in the same directory for all environment-specific settings.

**Steps:**

1.  **Ensure `docker-compose.yml` is present:** If you cloned the repository, it's already there. Otherwise, you can copy its content from the repository into a file named `docker-compose.yml` in your chosen project directory.
2.  **Customize Volume Paths (Crucial!):**
    Open the `docker-compose.yml` file and **edit the `volumes` section**. The default paths are examples (`./data/config:/config` and `./data/downloads:/downloads`). You **must** change the host parts (left side of the colon) to the actual absolute paths on your Docker host where you want to store persistent configuration and downloads. For example:
    ```yaml
    volumes:
      - /opt/nzbgetvpn_data/config:/config
      - /opt/nzbgetvpn_data/downloads:/downloads
    ```
    These paths should correspond to the directories you prepared in Step 1 ("Prepare Your Docker Host System").
3.  **Verify `.env` File:** Make sure your `.env` file (in the same directory as `docker-compose.yml`) is correctly configured with your `PUID`, `PGID`, `TZ`, VPN settings, etc., as described in Step 2 ("Create Your `.env` Configuration File"). The `docker-compose.yml` relies entirely on this `.env` file.
4.  **Start the Container:**
    Navigate to the directory containing your `docker-compose.yml` and `.env` file, then run:
    ```bash
docker-compose up -d
    ```
    Or, if you're using a newer Docker version with the Compose plugin integrated:
    ```bash
docker compose up -d
    ```

**To Stop and Remove:**
```bash
docker-compose down # or docker compose down
```

*(The provided `Makefile` also offers `make run` and `make run-wireguard` targets, which essentially use `docker run` commands similar to the examples above. It can be a convenient alternative for some users or for development purposes.)*

## 🖥️ Accessing Services

*   **NZBGet Web UI:** `http://localhost:6789`
    *   🔑 **Default Login:** Username: `nzbget`, Password: `tegbzn6789`
    *   *(Remember to change the password in NZBGet settings after your first login!)*
*   **🌐 Privoxy HTTP Proxy:** If `ENABLE_PRIVOXY=yes`, server: `localhost`, port: `PRIVOXY_PORT` (default `8118`).

## ⚙️ Environment Variables

| Variable                 | Purpose                                                                    | Example                                  | Default                     |
|--------------------------|----------------------------------------------------------------------------|------------------------------------------|-----------------------------|
| `VPN_CLIENT`             | `openvpn` or `wireguard`                                                   | `openvpn`                                | `openvpn`                   |
| `VPN_CONFIG`             | Path to VPN config file **inside container** (`.ovpn` for OpenVPN, `.conf` for WireGuard). Auto-detects first file if unset. | `/config/openvpn/your.ovpn` or `/config/wireguard/wg0.conf` | (auto-detect)   |
| `VPN_USER`               | OpenVPN username. Used if set with `VPN_PASS`. Overrides `credentials.txt`. | `myuser`                                 |                             |
| `VPN_PASS`               | OpenVPN password. Used if set with `VPN_USER`. Overrides `credentials.txt`. | `mypassword`                             |                             |
| `ENABLE_PRIVOXY`         | Enable Privoxy (`yes`/`no`)                                                | `no`                                     | `no`                        |
| `PRIVOXY_PORT`           | Internal port for Privoxy service                                          | `8118`                                   | `8118`                      |
| `PUID`                   | User ID for NZBGet process.                                                | `1000`                                   | (from base image)           |
| `PGID`                   | Group ID for NZBGet process.                                               | `1000`                                   | (from base image)           |
| `TZ`                     | Your local timezone.                                                       | `America/New_York`                       | `Etc/UTC`                   |
| `LAN_NETWORK`            | Your LAN CIDR to bypass VPN for local NZBGet access.                     | `192.168.1.0/24`                         |                             |
| `NAME_SERVERS`           | Custom DNS servers (comma-separated).                                      | `1.1.1.1,8.8.8.8`                        | (VPN/defaults)              |
| `DEBUG`                  | Enable verbose script logging (`true`/`false`).                            | `false`                                  | `false`                     |
| `VPN_OPTIONS`            | Additional OpenVPN client command-line options.                            | `--inactive 3600 --ping-restart 60`      |                             |
| `UMASK`                  | File creation mask for NZBGet.                                             | `022`                                    | (from base image)           |
| `ADDITIONAL_PORTS`       | Comma-separated TCP/UDP ports for outbound allow via iptables.             | `9090,53/udp`                          |                             |
| `NZBGET_S1_NAME`         | Name for NZBGet Server1.                                                   | `Newshosting`                            | `Newshosting`               |
| `NZBGET_S1_HOST`         | Hostname for NZBGet Server1.                                               | `news.newshosting.com`                   |                             |
| `NZBGET_S1_PORT`         | Port for NZBGet Server1.                                                   | `563`                                    | `563`                       |
| `NZBGET_S1_USER`         | Username for NZBGet Server1.                                               | `your_user`                              |                             |
| `NZBGET_S1_PASS`         | Password for NZBGet Server1.                                               | `your_pass`                              |                             |
| `NZBGET_S1_CONN`         | Number of connections for NZBGet Server1.                                  | `15`                                     | `15`                        |
| `NZBGET_S1_SSL`          | Enable SSL for NZBGet Server1 (`yes`/`no`).                                  | `yes`                                    | `yes`                       |
| `NZBGET_S1_LEVEL`        | Priority level for NZBGet Server1.                                         | `0`                                      | `0`                         |
| `NZBGET_S1_ENABLED`      | Enable NZBGet Server1 (`yes`/`no`).                                        | `yes`                                    | `yes`                       |

**🔑 OpenVPN Credential Priority:**
1.  If `VPN_USER` and `VPN_PASS` are both set, they will be used.
2.  Else, if `/config/openvpn/credentials.txt` exists and is valid, it's used.
3.  If neither, and your `.ovpn` needs auth, connection may fail.
4.  **Provide credentials** via `VPN_USER`/`VPN_PASS` or `credentials.txt` if needed.
This gives you full control over the exact configuration used.

**💡 A Note on `VPN_PROV` (from other images):**
This image prioritizes flexibility. It doesn't use `VPN_PROV` for auto-provider setup. Instead, you:
1.  **Download** your provider's `.ovpn` or `.conf` file.
2.  **Place it** in `your_host_config_dir/openvpn/` or `your_host_config_dir/wireguard/`.
3.  **Set `VPN_CONFIG`** to its path inside the container (e.g., `/config/openvpn/your_file.ovpn`). Or let it auto-detect if it's the only one.
4.  **Provide credentials** via `VPN_USER`/`VPN_PASS` or `credentials.txt` if needed.
This gives you full control over the exact configuration used.

### ⚙️ NZBGet News Server Configuration (via Environment Variables)

You can pre-configure the first news server (Server1) in NZBGet using environment variables. This is useful for automating your setup or when you prefer not to manually edit `nzbget.conf` inside the container after deployment. An init script (`02-nzbget-news-server.sh`) runs on container startup and applies these settings to `/config/nzbget.conf`. If a setting for Server1 already exists in the file, it will be updated; otherwise, it will be added.

See the environment variable table above (or `.env.sample`) for the `NZBGET_S1_*` variables. Here's a quick rundown:

*   `NZBGET_S1_NAME`: A display name (e.g., "My News Provider").
*   `NZBGET_S1_HOST`: Server address (e.g., `news.example.com`).
*   `NZBGET_S1_PORT`: Port (e.g., `563` for SSL, `119` for non-SSL).
*   `NZBGET_S1_USER`: Your Usenet username.
*   `NZBGET_S1_PASS`: Your Usenet password.
*   `NZBGET_S1_CONN`: Number of connections (e.g., `20`).
*   `NZBGET_S1_SSL`: Set to `yes` to use SSL, `no` otherwise.
*   `NZBGET_S1_LEVEL`: Server priority (e.g., `0` for primary, `1` for backup).
*   `NZBGET_S1_ENABLED`: Set to `yes` to enable this server, `no` to disable it.

If you don't set these, NZBGet will use its default Server1 configuration (if any) or you can configure it via the Web UI.

## 🤔 Troubleshooting Tips

*   **Container Exits or VPN Not Connecting?**
    *   `docker logs nzbgetvpn` for clues.
    *   Check `VPN_CONFIG` path in `.env` (must be container path, e.g., `/config/...`).
    *   Verify credentials (in `.env` or `credentials.txt`) and `.ovpn`/`.conf` file contents.
*   **NZBGet UI / Privoxy Not Accessible?**
    1.  `docker ps` - is it running?
    2.  `docker logs nzbgetvpn` - any errors from NZBGet, Privoxy, or VPN setup?
    3.  Verify `-p` port mappings in your `docker run` command.
*   **File Permission Issues?**
    *   Ensure `PUID`/`PGID` in `.env` match the owner of your host data directories (`config/` and `downloads/`).

## 🩺 Healthcheck

Verifies NZBGet UI and VPN tunnel interface activity. If the container is unhealthy, check logs!

## 🧑‍💻 For Developers / Building from Source

Want to tinker or build it yourself?
1.  **Clone:** `git clone https://github.com/magicalyak/nzbgetvpn.git && cd nzbgetvpn`
2.  **Customize `.env`:** `cp .env.sample .env && nano .env`
3.  **Build & Run via Makefile:** Explore `make build`, `make run`, `make shell`, etc. The `Makefile` provides convenient targets.
    *   You can also build directly with `docker build -t yourname/nzbgetvpn .`

*(The GitHub Container Registry `ghcr.io/magicalyak/nzbgetvpn` is also available if you prefer it over Docker Hub for development builds or specific versions.)*

## 📄 License

This project is licensed under the MIT License. See the `LICENSE` file for details.
Base image (`linuxserver/nzbget`) and bundled software (OpenVPN, WireGuard, Privoxy, NZBGet) have their own respective licenses.

## 🙏 Acknowledgements
This project is inspired by the need for a secure, easy-to-use NZBGet setup with VPN support. Thanks to the `linuxserver/nzbget` team for their excellent base image and to the OpenVPN, WireGuard, and Privoxy communities for their contributions to open-source software.
Special thanks also to the maintainers of the [jshridha/docker-nzbgetvpn](https://github.com/jshridha/docker-nzbgetvpn) repository, from which this project drew initial inspiration and some foundational concepts.