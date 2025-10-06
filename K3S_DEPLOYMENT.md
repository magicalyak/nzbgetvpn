# K3s Deployment Guide for NZBGet VPN

This guide covers deploying nzbgetvpn on K3s (Lightweight Kubernetes).

## Prerequisites

- K3s installed and running
- kubectl configured to access your cluster
- Storage provisioner (local-path by default in K3s)
- Host with `/dev/net/tun` device available

## Understanding K3s Deployment Requirements

### Security Context Requirements

NZBGet VPN requires specific privileges to create VPN tunnels:

1. **NET_ADMIN capability** - Required to create and manage network interfaces
2. **Access to /dev/net/tun** - Required for VPN tunnel creation
3. **Privileged mode** (optional) - Some VPN configurations may require this

### Node Preparation

Ensure your K3s nodes have the TUN/TAP kernel module loaded:

```bash
# Check if TUN module is loaded
lsmod | grep tun

# Load TUN module if needed
sudo modprobe tun

# Make it persistent across reboots
echo "tun" | sudo tee -a /etc/modules-load.d/tun.conf
```

## Deployment Options

### Option 1: Basic Deployment with ConfigMap

This approach uses Kubernetes ConfigMaps for configuration and Secrets for credentials.

#### 1. Create Namespace

```bash
kubectl create namespace nzbgetvpn
```

#### 2. Create VPN Configuration Secret

```bash
# Create a secret with your VPN config file
kubectl create secret generic vpn-config \
  --from-file=provider.ovpn=/path/to/your/vpn-config.ovpn \
  -n nzbgetvpn

# Create a secret for VPN credentials (OpenVPN)
kubectl create secret generic vpn-credentials \
  --from-literal=username=your_vpn_username \
  --from-literal=password=your_vpn_password \
  -n nzbgetvpn
```

#### 3. Create PersistentVolumeClaim for Data

```yaml
# pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: nzbgetvpn-config
  namespace: nzbgetvpn
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: local-path
  resources:
    requests:
      storage: 1Gi
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: nzbgetvpn-downloads
  namespace: nzbgetvpn
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: local-path
  resources:
    requests:
      storage: 100Gi
```

Apply the PVCs:
```bash
kubectl apply -f pvc.yaml
```

#### 4. Create Deployment

```yaml
# deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nzbgetvpn
  namespace: nzbgetvpn
  labels:
    app: nzbgetvpn
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nzbgetvpn
  template:
    metadata:
      labels:
        app: nzbgetvpn
    spec:
      containers:
      - name: nzbgetvpn
        image: magicalyak/nzbgetvpn:latest
        securityContext:
          capabilities:
            add:
              - NET_ADMIN
              - SYS_MODULE
          # privileged: true  # Uncomment if needed for your VPN
        env:
        - name: VPN_CLIENT
          value: "openvpn"
        - name: VPN_CONFIG
          value: "/config/openvpn/provider.ovpn"
        - name: VPN_USER
          valueFrom:
            secretKeyRef:
              name: vpn-credentials
              key: username
        - name: VPN_PASS
          valueFrom:
            secretKeyRef:
              name: vpn-credentials
              key: password
        - name: PUID
          value: "1000"
        - name: PGID
          value: "1000"
        - name: TZ
          value: "America/New_York"
        - name: ENABLE_MONITORING
          value: "yes"
        - name: MONITORING_PORT
          value: "8080"
        - name: DEBUG
          value: "false"
        ports:
        - name: http
          containerPort: 6789
          protocol: TCP
        - name: monitoring
          containerPort: 8080
          protocol: TCP
        volumeMounts:
        - name: config
          mountPath: /config
        - name: downloads
          mountPath: /downloads
        - name: vpn-config
          mountPath: /config/openvpn
          readOnly: true
        - name: dev-tun
          mountPath: /dev/net/tun
        resources:
          requests:
            memory: "256Mi"
            cpu: "100m"
          limits:
            memory: "1Gi"
            cpu: "1000m"
        livenessProbe:
          exec:
            command:
            - /bin/sh
            - -c
            - "curl -f http://localhost:8080/health || exit 1"
          initialDelaySeconds: 60
          periodSeconds: 30
          timeoutSeconds: 10
          failureThreshold: 3
        readinessProbe:
          exec:
            command:
            - /bin/sh
            - -c
            - "curl -f http://localhost:6789 && curl -f http://localhost:8080/health"
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
      volumes:
      - name: config
        persistentVolumeClaim:
          claimName: nzbgetvpn-config
      - name: downloads
        persistentVolumeClaim:
          claimName: nzbgetvpn-downloads
      - name: vpn-config
        secret:
          secretName: vpn-config
      - name: dev-tun
        hostPath:
          path: /dev/net/tun
          type: CharDevice
      nodeSelector:
        kubernetes.io/os: linux
      # Optional: Pin to specific node with VPN support
      # nodeSelector:
      #   vpn-capable: "true"
```

Apply the deployment:
```bash
kubectl apply -f deployment.yaml
```

#### 5. Create Service

```yaml
# service.yaml
apiVersion: v1
kind: Service
metadata:
  name: nzbgetvpn
  namespace: nzbgetvpn
  labels:
    app: nzbgetvpn
spec:
  type: ClusterIP
  ports:
  - port: 6789
    targetPort: 6789
    protocol: TCP
    name: http
  - port: 8080
    targetPort: 8080
    protocol: TCP
    name: monitoring
  selector:
    app: nzbgetvpn
```

Apply the service:
```bash
kubectl apply -f service.yaml
```

#### 6. Create Ingress (Optional)

```yaml
# ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nzbgetvpn
  namespace: nzbgetvpn
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
    # traefik.ingress.kubernetes.io/router.middlewares: default-redirect-https@kubernetescrd
spec:
  ingressClassName: traefik
  rules:
  - host: nzbget.yourdomain.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: nzbgetvpn
            port:
              number: 6789
  tls:
  - hosts:
    - nzbget.yourdomain.com
    secretName: nzbgetvpn-tls
```

Apply the ingress:
```bash
kubectl apply -f ingress.yaml
```

### Option 2: Using Helm Chart (Recommended)

Create a Helm chart for easier management and upgrades.

#### 1. Create Helm Chart Structure

```bash
mkdir -p nzbgetvpn-chart/templates
cd nzbgetvpn-chart
```

#### 2. Create values.yaml

```yaml
# values.yaml
replicaCount: 1

image:
  repository: magicalyak/nzbgetvpn
  pullPolicy: IfNotPresent
  tag: "latest"

vpn:
  client: openvpn  # or wireguard
  config: provider.ovpn
  username: ""  # Set via --set or override
  password: ""  # Set via --set or override
  # Alternatively, use existing secret
  existingSecret: ""
  usernameKey: "username"
  passwordKey: "password"

environment:
  PUID: "1000"
  PGID: "1000"
  TZ: "America/New_York"
  ENABLE_MONITORING: "yes"
  MONITORING_PORT: "8080"
  DEBUG: "false"

service:
  type: ClusterIP
  port: 6789
  monitoringPort: 8080

ingress:
  enabled: false
  className: "traefik"
  annotations: {}
  hosts:
    - host: nzbget.local
      paths:
        - path: /
          pathType: Prefix
  tls: []

persistence:
  config:
    enabled: true
    storageClass: "local-path"
    accessMode: ReadWriteOnce
    size: 1Gi
  downloads:
    enabled: true
    storageClass: "local-path"
    accessMode: ReadWriteOnce
    size: 100Gi

resources:
  requests:
    memory: "256Mi"
    cpu: "100m"
  limits:
    memory: "1Gi"
    cpu: "1000m"

nodeSelector: {}
tolerations: []
affinity: {}

securityContext:
  capabilities:
    add:
      - NET_ADMIN
      - SYS_MODULE
  # privileged: true  # Uncomment if needed

monitoring:
  serviceMonitor:
    enabled: false
    interval: 30s
```

#### 3. Install with Helm

```bash
# Install from local chart
helm install nzbgetvpn ./nzbgetvpn-chart \
  --namespace nzbgetvpn \
  --create-namespace \
  --set vpn.username=your_vpn_username \
  --set vpn.password=your_vpn_password

# Or upgrade
helm upgrade --install nzbgetvpn ./nzbgetvpn-chart \
  --namespace nzbgetvpn \
  --values custom-values.yaml
```

### Option 3: Port-Forward for Local Access

If you don't want to expose via Ingress:

```bash
# Port-forward to access locally
kubectl port-forward -n nzbgetvpn service/nzbgetvpn 6789:6789 8080:8080

# Access at:
# NZBGet: http://localhost:6789
# Monitoring: http://localhost:8080/health
```

## WireGuard Configuration

For WireGuard instead of OpenVPN:

```yaml
# Update deployment.yaml environment
env:
- name: VPN_CLIENT
  value: "wireguard"
- name: VPN_CONFIG
  value: "/config/wireguard/wg0.conf"
# Remove VPN_USER and VPN_PASS (not needed for WireGuard)
```

Create WireGuard secret:
```bash
kubectl create secret generic vpn-config \
  --from-file=wg0.conf=/path/to/your/wireguard.conf \
  -n nzbgetvpn
```

Update volumeMount in deployment:
```yaml
volumeMounts:
- name: vpn-config
  mountPath: /config/wireguard
  readOnly: true
```

## Monitoring with Prometheus

If you have Prometheus Operator installed:

```yaml
# servicemonitor.yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: nzbgetvpn
  namespace: nzbgetvpn
  labels:
    app: nzbgetvpn
spec:
  selector:
    matchLabels:
      app: nzbgetvpn
  endpoints:
  - port: monitoring
    path: /prometheus
    interval: 30s
```

Apply:
```bash
kubectl apply -f servicemonitor.yaml
```

## Troubleshooting

### Check Pod Status

```bash
# Get pod status
kubectl get pods -n nzbgetvpn

# View logs
kubectl logs -n nzbgetvpn deployment/nzbgetvpn -f

# Describe pod for events
kubectl describe pod -n nzbgetvpn -l app=nzbgetvpn
```

### Verify VPN Connection

```bash
# Exec into pod
kubectl exec -it -n nzbgetvpn deployment/nzbgetvpn -- /bin/sh

# Check VPN interface
ip addr show tun0  # or wg0 for WireGuard

# Check external IP (should be VPN IP)
curl ifconfig.me

# Check VPN process
ps aux | grep -E 'openvpn|wireguard'
```

### Common Issues

**Pod stuck in ContainerCreating:**
- Check if /dev/net/tun exists on the node
- Verify security context capabilities are allowed

**VPN not connecting:**
- Check logs: `kubectl logs -n nzbgetvpn deployment/nzbgetvpn`
- Verify VPN config secret is mounted correctly
- Check credentials are correct

**Permission denied on /dev/net/tun:**
- Ensure NET_ADMIN capability is added
- Try adding privileged: true to securityContext

**Downloads not working:**
- Verify PVC is bound: `kubectl get pvc -n nzbgetvpn`
- Check directory permissions (PUID/PGID)

## Upgrading

```bash
# Update image version
kubectl set image deployment/nzbgetvpn \
  nzbgetvpn=magicalyak/nzbgetvpn:v25.3.4 \
  -n nzbgetvpn

# Or edit deployment
kubectl edit deployment nzbgetvpn -n nzbgetvpn

# Rollback if needed
kubectl rollout undo deployment/nzbgetvpn -n nzbgetvpn
```

## Resource Management

### Horizontal Pod Autoscaling

Note: NZBGet VPN is typically not suitable for horizontal scaling due to VPN and state requirements. Stick with a single replica.

### Backup Configuration

```bash
# Backup PVC data
kubectl exec -n nzbgetvpn deployment/nzbgetvpn -- \
  tar czf - /config | gzip > nzbgetvpn-config-backup.tar.gz

# Restore
cat nzbgetvpn-config-backup.tar.gz | \
  kubectl exec -i -n nzbgetvpn deployment/nzbgetvpn -- \
  tar xzf - -C /
```

## Security Best Practices

1. **Use Secrets for Credentials** - Never hardcode VPN credentials
2. **Limit Capabilities** - Only add NET_ADMIN, avoid privileged when possible
3. **Network Policies** - Restrict pod network access
4. **RBAC** - Use proper service accounts with minimal permissions
5. **Pod Security Standards** - Use restricted profile where possible

## Example Complete Deployment

See the `k8s/` directory for a complete example with all manifests organized:

```
k8s/
├── namespace.yaml
├── secrets.yaml
├── pvc.yaml
├── deployment.yaml
├── service.yaml
└── ingress.yaml
```

Deploy everything:
```bash
kubectl apply -f k8s/
```

## Additional Resources

- [K3s Documentation](https://docs.k3s.io/)
- [Kubernetes Capabilities](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/)
- [Main README](README.md)
- [Troubleshooting Guide](TROUBLESHOOTING.md)
