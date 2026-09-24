#!/bin/bash
# End-to-end check of the VPN health metrics and the restart watchdog against
# a real container.
#
# No VPN account is needed. A test double replaces 50-vpn-setup and creates
# "tun0" as an ipvlan child of eth0 with host routes for the probe targets, so
# traffic really does pass through it. The tunnel is then killed with
#
#   iptables -I OUTPUT -o tun0 -j DROP
#
# which leaves the interface up and addressed while nothing gets through:
# the failure mode that "interface has an IP" checks cannot see.
#
# Asserts:
#   1. Healthy tunnel: vpn_interface_up=1, vpn_connected=1, healthy=1, and
#      /metrics is valid Prometheus text.
#   2. Dead tunnel: vpn_interface_up=1, vpn_connected=0, healthy=0.
#   3. With auto-restart on, exhausting MAX_RESTART_ATTEMPTS on a dead tunnel
#      exits the container with a non-zero code.
#
# Usage: ./test-dead-tunnel.sh [image]   (default: nzbgetvpn:test)

set -uo pipefail

IMAGE="${1:-nzbgetvpn:test}"
NET=nzbgetvpn-test-net
SUBNET_PREFIX=172.30.99
C1=nzbgetvpn-test-metrics
C2=nzbgetvpn-test-exit
WORK=$(mktemp -d)
PASSED=0
FAILED=0

ok()   { echo "  ok   $1"; PASSED=$((PASSED + 1)); }
fail() { echo "  FAIL $1"; FAILED=$((FAILED + 1)); }
expect() { if [[ "$2" == "$3" ]]; then ok "$1"; else fail "$1: got '$2' want '$3'"; fi; }

cleanup() {
    docker rm -f "$C1" "$C2" >/dev/null 2>&1
    docker network rm "$NET" >/dev/null 2>&1
    rm -rf "$WORK"
}
trap cleanup EXIT
cleanup >/dev/null 2>&1
WORK=$(mktemp -d)

cat > "$WORK/50-vpn-setup" <<EOF
#!/bin/bash
# Test double for vpn-setup.sh
if ! ip link show tun0 >/dev/null 2>&1; then
    ip link add tun0 link eth0 type ipvlan mode l2
    last_octet=\$(ip -o -4 addr show dev eth0 | awk '{print \$4}' | cut -d/ -f1 | cut -d. -f4)
    ip addr add ${SUBNET_PREFIX}.\$((last_octet + 100))/24 dev tun0
    ip link set tun0 up
    ip route add 1.1.1.1 via ${SUBNET_PREFIX}.1 dev tun0
    ip route add 9.9.9.9 via ${SUBNET_PREFIX}.1 dev tun0
fi
echo tun0 > /tmp/vpn_interface_name
touch /tmp/vpn_setup_complete
EOF
chmod +x "$WORK/50-vpn-setup"

docker network create --subnet "${SUBNET_PREFIX}.0/24" "$NET" >/dev/null

run_container() {
    local name="$1" ip="$2"; shift 2
    docker run -d --name "$name" --network "$NET" --ip "$ip" \
        --cap-add NET_ADMIN \
        -e VPN_CLIENT=wireguard \
        -e HEALTH_CHECK_INTERVAL=10 \
        -e CHECK_NEWS_SERVER=false \
        -v "$WORK/50-vpn-setup:/etc/cont-init.d/50-vpn-setup:ro" \
        "$@" "$IMAGE" >/dev/null
}

metric() {
    docker exec "$1" curl -s --max-time 5 "http://localhost:8080/metrics" | awk -v n="$2" '$1 == n { print $2 }'
}

# Wait until a gauge reports the wanted value; prints the last value seen
wait_metric() {
    local container="$1" name="$2" want="$3" timeout="${4:-120}" value=""
    for _ in $(seq 1 "$timeout"); do
        value=$(metric "$container" "$name")
        [[ "$value" == "$want" ]] && break
        sleep 1
    done
    echo "$value"
}

echo "Starting $IMAGE with a working test tunnel"
run_container "$C1" "${SUBNET_PREFIX}.10"

echo
echo "Healthy tunnel"
expect "nzbgetvpn_vpn_connected" "$(wait_metric "$C1" nzbgetvpn_vpn_connected 1 180)" 1
expect "nzbgetvpn_healthy" "$(wait_metric "$C1" nzbgetvpn_healthy 1 60)" 1
expect "nzbgetvpn_vpn_interface_up" "$(metric "$C1" nzbgetvpn_vpn_interface_up)" 1

docker exec "$C1" curl -s -D "/tmp/headers" -o /tmp/metrics.txt http://localhost:8080/metrics
docker cp "$C1:/tmp/metrics.txt" "$WORK/metrics.txt" >/dev/null
docker cp "$C1:/tmp/headers" "$WORK/headers" >/dev/null
expect "Content-Type is Prometheus text" \
    "$(grep -i '^content-type:' "$WORK/headers" | tr -d '\r' | awk '{print $2}')" "text/plain;"
bad=$(awk '!/^#/ && NF != 2' "$WORK/metrics.txt" | head -3)
expect "every sample line is 'name value'" "$bad" ""
if command -v promtool >/dev/null 2>&1; then
    promtool check metrics < "$WORK/metrics.txt" >/dev/null 2>&1 && ok "promtool check metrics" || fail "promtool check metrics"
fi
for name in nzbgetvpn_response_time_seconds nzbgetvpn_success_rate_percent; do
    if grep -q "^${name}{check=\"nzbget\"}" "$WORK/metrics.txt"; then ok "$name emitted"; else fail "$name missing"; fi
done
expect "/prometheus serves the same exposition" \
    "$(docker exec "$C1" curl -s http://localhost:8080/prometheus | grep -c '^# TYPE nzbgetvpn_vpn_connected')" 1

echo
echo "Dead tunnel: iptables -I OUTPUT -o tun0 -j DROP"
docker exec "$C1" iptables -I OUTPUT -o tun0 -j DROP
expect "nzbgetvpn_vpn_connected" "$(wait_metric "$C1" nzbgetvpn_vpn_connected 0 90)" 0
expect "nzbgetvpn_healthy" "$(metric "$C1" nzbgetvpn_healthy)" 0
expect "nzbgetvpn_vpn_interface_up still 1 (interface has an address)" \
    "$(metric "$C1" nzbgetvpn_vpn_interface_up)" 1
expect "tun0 still has its address" \
    "$(docker exec "$C1" ip -o -4 addr show dev tun0 | grep -c inet)" 1

echo
echo "Tunnel restored"
docker exec "$C1" iptables -D OUTPUT -o tun0 -j DROP
expect "nzbgetvpn_vpn_connected" "$(wait_metric "$C1" nzbgetvpn_vpn_connected 1 90)" 1
expect "nzbgetvpn_healthy" "$(wait_metric "$C1" nzbgetvpn_healthy 1 60)" 1
cp "$WORK/metrics.txt" "${METRICS_SAMPLE_OUT:-/dev/null}" 2>/dev/null
docker rm -f "$C1" >/dev/null

echo
echo "Watchdog exits the container after MAX_RESTART_ATTEMPTS"
run_container "$C2" "${SUBNET_PREFIX}.11" \
    -e ENABLE_AUTO_RESTART=true \
    -e MAX_RESTART_ATTEMPTS=1 \
    -e RESTART_COOLDOWN_SECONDS=0 \
    -e RESTART_FAILURE_THRESHOLD=1 \
    -e AUTO_RESTART_CHECK_INTERVAL=5 \
    -e AUTO_RESTART_STARTUP_GRACE=10
expect "tunnel healthy before the fault" "$(wait_metric "$C2" nzbgetvpn_vpn_connected 1 180)" 1
docker exec "$C2" iptables -I OUTPUT -o tun0 -j DROP
exit_code=timeout
for _ in $(seq 1 300); do
    if [[ "$(docker inspect -f '{{.State.Running}}' "$C2")" == "false" ]]; then
        exit_code=$(docker inspect -f '{{.State.ExitCode}}' "$C2")
        break
    fi
    sleep 1
done
expect "container exited non-zero" "$exit_code" 1
if docker logs "$C2" 2>&1 | grep -q 'Maximum VPN restart attempts (1) exceeded'; then
    ok "log explains the exit"
else
    fail "log explains the exit"
fi

echo
echo "================================================"
echo "passed=$PASSED failed=$FAILED"
[[ $FAILED -eq 0 ]]
