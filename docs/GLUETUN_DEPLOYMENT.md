# NZBGet with Gluetun VPN Sidecar

This guide explains how to use nzbgetvpn with [Gluetun](https://github.com/qdm12/gluetun) as an external VPN container. This approach provides:

- Native support for 30+ VPN providers (NordVPN, ExpressVPN, Mullvad, ProtonVPN, etc.)
- Built-in kill switch and DNS leak protection
- Better stability and automatic reconnection
- Regular updates from an actively maintained project

## Docker Compose

See `docker-compose-gluetun.yml` in the repository root for a complete example.

### Basic Setup

```yaml
services:
  gluetun:
    image: qmcgaw/gluetun:latest
    cap_add:
      - NET_ADMIN
    devices:
      - /dev/net/tun
    environment:
      - VPN_SERVICE_PROVIDER=nordvpn
      - VPN_TYPE=openvpn
      - OPENVPN_USER=your_service_username
      - OPENVPN_PASSWORD=your_service_password
      - FIREWALL_VPN_INPUT_PORTS=6789
    ports:
      - "6789:6789"

  nzbgetvpn:
    image: magicalyak/nzbgetvpn:latest
    network_mode: "service:gluetun"
    depends_on:
      gluetun:
        condition: service_healthy
    environment:
      - VPN_CLIENT=external
      - PUID=1000
      - PGID=1000
    volumes:
      - ./config:/config
      - ./downloads:/downloads
```

## Kubernetes Deployment

In Kubernetes, both containers run in the same pod and share the network namespace automatically.

### Secret for VPN Credentials

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: vpn-credentials
  namespace: media
type: Opaque
stringData:
  username: your_service_username
  password: your_service_password
```

### Deployment with Gluetun Sidecar

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nzbget
  namespace: media
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nzbget
  template:
    metadata:
      labels:
        app: nzbget
    spec:
      containers:
      # Gluetun VPN sidecar
      - name: gluetun
        image: qmcgaw/gluetun:latest
        securityContext:
          capabilities:
            add:
            - NET_ADMIN
        env:
        - name: VPN_SERVICE_PROVIDER
          value: "nordvpn"
        - name: VPN_TYPE
          value: "openvpn"
        - name: OPENVPN_USER
          valueFrom:
            secretKeyRef:
              name: vpn-credentials
              key: username
        - name: OPENVPN_PASSWORD
          valueFrom:
            secretKeyRef:
              name: vpn-credentials
              key: password
        - name: SERVER_COUNTRIES
          value: "United States"
        - name: TZ
          value: "America/New_York"
        - name: FIREWALL_VPN_INPUT_PORTS
          value: "6789"
        volumeMounts:
        - name: dev-net-tun
          mountPath: /dev/net/tun
        resources:
          requests:
            cpu: "25m"
            memory: "64Mi"
          limits:
            cpu: "200m"
            memory: "256Mi"

      # NZBGet container
      - name: nzbget
        image: magicalyak/nzbgetvpn:latest
        ports:
        - containerPort: 6789
          name: web
        env:
        - name: VPN_CLIENT
          value: "external"
        - name: TZ
          value: "America/New_York"
        - name: PUID
          value: "1000"
        - name: PGID
          value: "1000"
        volumeMounts:
        - name: config
          mountPath: /config
        - name: downloads
          mountPath: /downloads
        resources:
          requests:
            cpu: "50m"
            memory: "128Mi"
          limits:
            cpu: "500m"
            memory: "512Mi"

      volumes:
      - name: config
        persistentVolumeClaim:
          claimName: nzbget-config
      - name: downloads
        persistentVolumeClaim:
          claimName: downloads
      - name: dev-net-tun
        hostPath:
          path: /dev/net/tun
          type: CharDevice
```

### Service

```yaml
apiVersion: v1
kind: Service
metadata:
  name: nzbget
  namespace: media
spec:
  selector:
    app: nzbget
  ports:
  - port: 6789
    targetPort: 6789
    name: web
```

## VPN Provider Configuration

### NordVPN

NordVPN requires **service credentials** (not your regular login):

1. Log in to your NordVPN account
2. Go to Services > NordVPN
3. Click "Set up NordVPN manually"
4. Copy your service credentials

```yaml
environment:
  - VPN_SERVICE_PROVIDER=nordvpn
  - VPN_TYPE=openvpn
  - OPENVPN_USER=service_username
  - OPENVPN_PASSWORD=service_password
  - SERVER_COUNTRIES=United States
```

### Mullvad

Mullvad supports both OpenVPN and WireGuard:

```yaml
# OpenVPN
environment:
  - VPN_SERVICE_PROVIDER=mullvad
  - VPN_TYPE=openvpn
  - OPENVPN_USER=your_account_number

# WireGuard
environment:
  - VPN_SERVICE_PROVIDER=mullvad
  - VPN_TYPE=wireguard
  - WIREGUARD_PRIVATE_KEY=your_private_key
  - WIREGUARD_ADDRESSES=10.x.x.x/32
```

### ProtonVPN

```yaml
environment:
  - VPN_SERVICE_PROVIDER=protonvpn
  - VPN_TYPE=openvpn
  - OPENVPN_USER=username+suffix
  - OPENVPN_PASSWORD=password
  - SERVER_COUNTRIES=United States
```

## Verifying VPN Connection

Check that traffic is routed through VPN:

```bash
# Docker
docker exec nzbgetvpn curl -s ifconfig.me

# Kubernetes
kubectl exec -n media deploy/nzbget -c nzbget -- curl -s ifconfig.me
```

The returned IP should be your VPN provider's IP, not your home IP.

## Troubleshooting

### Check Gluetun Logs

```bash
# Docker
docker logs gluetun

# Kubernetes
kubectl logs -n media deploy/nzbget -c gluetun
```

### Common Issues

1. **Authentication failed**: Ensure you're using service credentials, not your regular login
2. **Connection timeout**: Try a different server region or VPN type (OpenVPN vs WireGuard)
3. **NZBGet inaccessible**: Check that `FIREWALL_VPN_INPUT_PORTS=6789` is set

## Resources

- [Gluetun Wiki](https://github.com/qdm12/gluetun-wiki)
- [Supported VPN Providers](https://github.com/qdm12/gluetun-wiki/tree/main/setup/providers)
- [Gluetun GitHub](https://github.com/qdm12/gluetun)
