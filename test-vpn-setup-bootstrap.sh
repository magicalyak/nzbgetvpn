#!/bin/bash
# The single-quoted snippets in this file are code for the stubs, so their
# expansions are meant to happen there, not here.
# shellcheck disable=SC2016
# End-to-end test that vpn-setup.sh never opens the firewall, at boot or when the
# auto-restart watchdog reruns it in place while NZBGet keeps running.
#
# vpn-setup.sh used to reset every policy to ACCEPT and flush the chains before
# building the kill switch, and on a rerun "ip route add $LAN_NETWORK" failed with
# "File exists", which stopped the script (set -e) before the tunnel and the VPN
# servers were allowed, so the restart could never succeed.
#
# It also flushed the nat and mangle tables. On Docker user-defined networks
# (Compose's default) the nat table holds the rules that make Docker's embedded DNS
# server at 127.0.0.11 work, so hostname VPN servers could not be resolved there.
#
# This runs the shipped vpn-setup.sh from start to finish, then the OpenVPN s6 run
# script, with iptables, ip6tables, ip, openvpn, wg-quick and nslookup stubbed.
# After every change to OUTPUT the stub evaluates the chain for traffic that must
# never leave eth0, and nslookup only answers if the firewall lets the query out.
# It writes /etc/resolv.conf, /etc/openvpn and /tmp, so it only runs as root in a
# throwaway container:
#   kubectl run bootstrap-test --rm -i --restart=Never --image=bash:5 -- \
#     bash -c 'mkdir /src && tar xzf - -C /src && bash /src/test-vpn-setup-bootstrap.sh' \
#     < <(tar czf - root root_s6 test-vpn-setup-bootstrap.sh)
#   docker run --rm -v "$PWD":/src:ro bash:5 bash /src/test-vpn-setup-bootstrap.sh
#
# VPN_SETUP=path/to/vpn-setup.sh runs the same checks against another version.

set -e

if [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
    echo "Needs bash 4 or newer (this is $BASH_VERSION)."
    exit 1
fi
if [ "$(id -u)" -ne 0 ] || { [ ! -f /.dockerenv ] && [ ! -f /run/.containerenv ] && [ -z "$KUBERNETES_SERVICE_HOST" ]; }; then
    echo "Refusing to run: this test rewrites /etc/resolv.conf and /tmp state, so it only runs"
    echo "as root inside a throwaway container (see the top of this file)."
    exit 1
fi

# The up script vpn-setup.sh generates, and the stubs below, start with #!/bin/bash.
# The bash:5 image only has /usr/local/bin/bash.
[ -e /bin/bash ] || ln -s "$(command -v bash)" /bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

FAILED=false
log_pass() { echo -e "${GREEN}ok${NC}   $1"; }
log_fail() { echo -e "${RED}FAIL${NC} $1"; FAILED=true; }

expect_eq() {
    if [ "$1" = "$2" ]; then
        log_pass "$3"
    else
        log_fail "$3"
        echo "    expected: $(printf '%q' "$2")"
        echo "    actual:   $(printf '%q' "$1")"
    fi
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VPN_SETUP="${VPN_SETUP:-$SCRIPT_DIR/root/vpn-setup.sh}"
OPENVPN_RUN="$SCRIPT_DIR/root_s6/openvpn/run"
export VPN_REMOTES_LIB="$SCRIPT_DIR/root/vpn-remotes.sh"

echo "================================================"
echo "   vpn-setup.sh kill switch bootstrap tests"
echo "================================================"

WORK="$(mktemp -d)"
export FW="$WORK/fw"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin" "$FW"

# fweval DIR OUT_IF DST PROTO DPORT STATE CTDIR
# First-match evaluation of DIR/OUTPUT for one packet, as the kernel would.
# Prints "ACCEPT <rule>", "DROP <rule>" or "<policy> policy". A match it does not
# know is treated as matching, so a rule it cannot read is never assumed safe.
cat > "$WORK/bin/fweval" <<'EOF'
#!/bin/bash
dir=$1 out=$2 dst=$3 proto=$4 dport=$5 state=$6 ctdir=$7
ip2int() { local IFS=.; set -- $1; n=$(( ($1 << 24) + ($2 << 16) + ($3 << 8) + $4 )); }
in_net() {
    local net=${1%/*} bits=32 a b m
    [ "$net" != "$1" ] && bits=${1#*/}
    m=$(( bits == 0 ? 0 : (0xFFFFFFFF << (32 - bits)) & 0xFFFFFFFF ))
    ip2int "$dst"; a=$n; ip2int "$net"; b=$n
    [ $(( a & m )) -eq $(( b & m )) ]
}
tst() { if "$@"; then t=y; else t=n; fi; }
set -f
while IFS= read -r rule; do
    [ -n "$rule" ] || continue
    set -- $rule
    neg=false match=true target=""
    while [ $# -gt 0 ]; do
        case "$1" in
            !) neg=true; shift; continue ;;
            -o) tst [ "$2" = "$out" ] ;;
            -d) tst in_net "$2" ;;
            -p) tst [ "$2" = "$proto" ] ;;
            --dport) tst [ "$2" = "$dport" ] ;;
            --state|--ctstate) case ",$2," in *",$state,"*) t=y ;; *) t=n ;; esac ;;
            --ctdir) tst [ "$2" = "$ctdir" ] ;;
            -m|--comment|--limit) shift 2; continue ;;
            -j) target=$2; break ;;
            *) echo "fweval: unknown match '$1' in: $rule" >&2; t=y ;;
        esac
        if $neg; then [ "$t" = y ] && t=n || t=y; neg=false; fi
        [ "$t" = y ] || match=false
        shift 2
    done
    if $match; then
        case "$target" in
            ACCEPT) echo "ACCEPT $rule"; exit 0 ;;
            DROP|REJECT) echo "DROP $rule"; exit 0 ;;
        esac
    fi
done < "$dir/OUTPUT"
echo "$(cat "$dir/policy.OUTPUT" 2>/dev/null || echo ACCEPT) policy"
EOF

# iptables with state: one file per chain, policies in $FW/<tool>/policy.CHAIN, and
# every policy change appended to $FW/policy-history. The filter table lives in
# $FW/<tool>, other tables in $FW/<tool>.<table>. Once OUTPUT's policy has been DROP
# (or $FW/armed exists), every change to filter OUTPUT is followed by the leak
# probes, and any ACCEPT goes to $FW/leaks.
cat > "$WORK/bin/iptables" <<'EOF'
#!/bin/bash
tool=$(basename "$0")
table=filter
if [ "$1" = "-t" ]; then
    table=$2
    shift 2
fi
dir="$FW/$tool"
[ "$table" = filter ] || dir="$FW/$tool.$table"
mkdir -p "$dir"
call="$tool -t $table $*"
op="$1" chain="$2"
shift 2
[ -n "$chain" ] && touch "$dir/$chain"
case "$op" in
    -P) echo "$1" > "$dir/policy.$chain"; echo "$tool $chain $1" >> "$FW/policy-history" ;;
    -F) if [ -z "$chain" ]; then
            for f in "$dir"/*; do case "$f" in */policy.*) ;; *) [ -f "$f" ] && : > "$f" ;; esac; done
        else
            : > "$dir/$chain"
        fi
        echo "$table ${chain:-all}" >> "$FW/flushes"
        if [ "$table" = filter ] && [ "$chain" = OUTPUT ] && [ ! -f "$FW/flag-at-flush" ]; then
            [ -f /tmp/vpn_setup_complete ] && echo present > "$FW/flag-at-flush" || echo absent > "$FW/flag-at-flush"
        fi ;;
    -A) echo "$*" >> "$dir/$chain" ;;
    -I) [[ "$1" =~ ^[0-9]+$ ]] && shift
        { echo "$*"; cat "$dir/$chain"; } > "$dir/$chain.new" && mv "$dir/$chain.new" "$dir/$chain" ;;
    -C) grep -qxF -- "$*" "$dir/$chain" ;;
    -D) grep -qxF -- "$*" "$dir/$chain" || exit 1
        grep -vxF -- "$*" "$dir/$chain" > "$dir/$chain.new"; mv "$dir/$chain.new" "$dir/$chain" ;;
    -S) sed "s/^/-A $chain /" "$dir/$chain" ;;
    -X|-N) ;;
    *) exit 1 ;;
esac
rc=$?
if [ "$tool" = iptables ] && [ "$table" = filter ] && [ "$chain" = OUTPUT ]; then
    [ "$op" = -P ] && [ "$1" = DROP ] && touch "$FW/armed"
    case "$op" in -P|-F|-A|-I|-D)
        if [ -f "$FW/armed" ]; then
            for probe in "new-https eth0 93.184.216.34 tcp 443 NEW ORIGINAL" \
                         "tunnel-conn-on-eth0 eth0 93.184.216.34 tcp 443 ESTABLISHED ORIGINAL" \
                         "dns-elsewhere eth0 9.9.9.9 udp 53 NEW ORIGINAL"; do
                set -- $probe
                verdict=$(fweval "$dir" "$2" "$3" "$4" "$5" "$6" "$7")
                case "$verdict" in
                    ACCEPT*) echo "$1 accepted after '$call': $verdict" >> "$FW/leaks" ;;
                esac
            done
        fi ;;
    esac
fi
exit $rc
EOF
cp "$WORK/bin/iptables" "$WORK/bin/ip6tables"

# ip with a routing table in $FW/routes, so a rerun finds its own LAN route. The
# first call comes right after the VPN client is prepared (or, for WireGuard,
# started), so it records the firewall as the bootstrap left it.
cat > "$WORK/bin/ip" <<'EOF'
#!/bin/bash
routes="$FW/routes"
touch "$routes"
if [ ! -d "$FW/at-bootstrap" ]; then
    mkdir -p "$FW/at-bootstrap" && cp "$FW"/iptables/* "$FW/at-bootstrap"/ 2>/dev/null
fi
args="$*"
case "$args" in
    "link show "*) echo "5: ${args##* }: <POINTOPOINT,UP,LOWER_UP> mtu 1420 state UNKNOWN" ;;
    "-4 addr show dev eth0"|"addr show eth0") echo "    inet 10.42.1.50/24 brd 10.42.1.255 scope global eth0" ;;
    "-4 addr show "*) echo "    inet 10.2.0.2/32 scope global ${args##* }" ;;
    "route"|"route show"|"route show dev eth0") echo "default via 10.42.1.1 dev eth0"; cat "$routes" ;;
    "rule "*|"route "*" table "*) ;;
    "route add "*)
        if grep -q "^$3 " "$routes"; then echo "RTNETLINK answers: File exists" >&2; exit 2; fi
        echo "${args#route add }" >> "$routes" ;;
    "route replace "*)
        [ -f "$FW/fail-route-replace" ] && { echo "RTNETLINK answers: Network is unreachable" >&2; exit 2; }
        grep -v "^$3 " "$routes" > "$routes.new"; echo "${args#route replace }" >> "$routes.new"; mv "$routes.new" "$routes" ;;
esac
exit 0
EOF

cat > "$WORK/bin/snapshot" <<'EOF'
#!/bin/bash
out="$FW/at-launch"
rm -rf "$out"; mkdir -p "$out"
cp "$FW"/iptables/* "$out"/ 2>/dev/null || true
[ -f /tmp/vpn_setup_complete ] && echo present > "$out/flag" || echo absent > "$out/flag"
EOF

# Launched by the OpenVPN s6 run script.
cat > "$WORK/bin/openvpn" <<'EOF'
#!/bin/bash
snapshot
echo "$*" > "$FW/openvpn-args"
EOF

cat > "$WORK/bin/wg-quick" <<'EOF'
#!/bin/bash
snapshot
[ "$1" = up ] && basename "$2" .conf > "$FW/tunnel-up"
exit 0
EOF

# Answers only if the firewall lets the query out: to the first nameserver, over
# eth0 for a cluster (10/8) nameserver or before the tunnel exists.
# Docker's embedded DNS server (127.0.0.11) only answers while Docker's nat rules
# are in place: OUTPUT jumps to DOCKER_OUTPUT, which DNATs port 53 to the port the
# server listens on, over lo. It forwards to the first "# ExtServers:" entry, from
# the host's namespace for host(...), from this one (eth0) otherwise.
cat > "$WORK/bin/nslookup" <<'EOF'
#!/bin/bash
blocked() {
    echo "$1" >> "$FW/dns-blocked"
    echo ";; connection timed out; no servers could be reached"; exit 1
}
ns=$(awk '$1 == "nameserver" { print $2; exit }' /etc/resolv.conf)
out=eth0 dport=53
if [ "$ns" = 127.0.0.11 ]; then
    nat="$FW/iptables.nat"
    grep -qxE -- '-d 127\.0\.0\.11(/32)? -j DOCKER_OUTPUT' "$nat/OUTPUT" 2>/dev/null ||
        blocked "$1 via $ns: nat OUTPUT has no jump to DOCKER_OUTPUT"
    dport=$(sed -n 's/.*-p udp .*--dport 53 -j DNAT --to-destination 127\.0\.0\.11:\([0-9]*\)$/\1/p' "$nat/DOCKER_OUTPUT" 2>/dev/null | head -1)
    [ -n "$dport" ] || blocked "$1 via $ns: DOCKER_OUTPUT has no DNAT for udp/53"
    out=lo
elif [ -f "$FW/tunnel-up" ] && [ "${ns#10.}" = "$ns" ]; then
    out=$(cat "$FW/tunnel-up")
fi
verdict=$(fweval "$FW/iptables" "$out" "$ns" udp "$dport" NEW ORIGINAL)
case "$verdict" in
    ACCEPT*) ;;
    *) blocked "$1 via $ns on $out: $verdict" ;;
esac
if [ "$ns" = 127.0.0.11 ]; then
    up=$(sed -n 's/^# ExtServers: \[\([^] ]*\).*/\1/p' /etc/resolv.conf)
    case "$up" in
        host\(*|"") ;;
        *) verdict=$(fweval "$FW/iptables" eth0 "$up" udp 53 NEW ORIGINAL)
           case "$verdict" in ACCEPT*) ;; *) blocked "$1 via $ns, forwarded to $up on eth0: $verdict" ;; esac ;;
    esac
fi
case "$1" in
    vpn.example.net) echo "Server: $ns"; echo "Address: $ns#53"; echo "Name: vpn.example.net"
                     echo "Address: 198.51.100.20"; echo "Address: 198.51.100.21" ;;
    *) exit 1 ;;
esac
EOF

# In a pod, BusyBox cp cannot overwrite the bind-mounted /etc/resolv.conf ("File
# exists"). The image ships coreutils cp, which can, so behave like it.
cat > "$WORK/bin/cp" <<'EOF'
#!/bin/bash
if [ $# -eq 2 ] && [ "$2" = /etc/resolv.conf ]; then cat "$1" > "$2"; else exec /bin/cp "$@"; fi
EOF

# Never let a real resolver answer.
printf '#!/bin/sh\nexit 2\n' > "$WORK/bin/getent"
chmod +x "$WORK"/bin/*
export PATH="$WORK/bin:$PATH"

reset_state() {
    rm -rf "$FW" && mkdir -p "$FW"
    rm -f /tmp/vpn_setup_complete /tmp/openvpn_up_complete /tmp/resolv.conf.backup \
          /tmp/vpn_interface_name /tmp/config.ovpn /tmp/vpn-credentials
    echo "nameserver 10.43.0.10" > /etc/resolv.conf
}

# Forget what the previous run recorded, but keep its firewall and routes, as an
# in-place rerun finds them.
start_rerun() {
    rm -rf "$FW/at-bootstrap" "$FW/at-launch" "$FW/leaks" "$FW/policy-history" \
           "$FW/flag-at-flush" "$FW/dns-blocked" "$FW/tunnel-up"
}

run_setup() {
    local rc=0
    env "$@" bash "$VPN_SETUP" > "$WORK/setup.out" 2>&1 || rc=$?
    expect_eq "$rc" "0" "vpn-setup.sh exits 0"
    if [ "$rc" -ne 0 ]; then
        tail -15 /tmp/vpn-setup.log | sed 's/^/    | /'
    fi
}

# What s6 does once the setup flag exists.
launch_openvpn() {
    env VPN_CLIENT=openvpn timeout 10 bash "$OPENVPN_RUN" > "$WORK/openvpn-run.out" 2>&1 || true
    if [ ! -d "$FW/at-launch" ]; then
        log_fail "the OpenVPN service launched the client"
        tail -5 "$WORK/openvpn-run.out" | sed 's/^/    | /'
    fi
}

verdict() { fweval "$1" eth0 "$2" "$3" "$4" NEW ORIGINAL | cut -d' ' -f1; }

# Nothing at the bootstrap point beyond loopback, replies, and per-server (or
# per-nameserver DNS) exceptions, all tagged.
check_bootstrap() {
    expect_eq "$(grep -vc -e '^-o lo -m comment --comment vpn-bootstrap -j ACCEPT$' \
        -e '^-o eth0 -m conntrack --ctstate RELATED,ESTABLISHED --ctdir REPLY -m comment --comment vpn-bootstrap -j ACCEPT$' \
        -e '^-o eth0 -d [0-9.]* -p [a-z]* --dport [0-9]* -m comment --comment vpn-bootstrap -j ACCEPT$' \
        "$FW/at-bootstrap/OUTPUT" || true)" "0" \
        "while bootstrapping, OUTPUT holds nothing beyond loopback, replies and per-server exceptions"
}

check_common() {
    expect_eq "$(grep -c ACCEPT "$FW/policy-history" || true)" "0" "no policy is ever set to ACCEPT (iptables or ip6tables)"
    expect_eq "$(head -3 "$FW/leaks" 2>/dev/null)" "" "no internet traffic can leave eth0 at any point"
    expect_eq "$(cat "$FW/flag-at-flush" 2>/dev/null)" "absent" "the setup flag is gone before the chains are flushed"
    expect_eq "$(cat "$FW/dns-blocked" 2>/dev/null)" "" "every VPN server lookup got through"
    expect_eq "$(cat "$FW"/iptables/INPUT "$FW"/iptables/OUTPUT | grep -c 'vpn-bootstrap' || true)" "0" \
        "no bootstrap rule survives into the kill switch"
    expect_eq "$(cat "$FW"/iptables/OUTPUT "$FW"/ip6tables/OUTPUT | grep ESTABLISHED | grep -v -e '^! -o eth0 ' -e '--ctdir REPLY' || true)" "" \
        "no interface-blind ESTABLISHED accept on OUTPUT (IPv4 or IPv6)"
    expect_eq "$(tail -1 "$FW/iptables/OUTPUT")" "-o eth0 -j DROP" "the kill switch still ends in an eth0 DROP"
    expect_eq "$(cat "$FW/iptables/policy.OUTPUT") $(cat "$FW/ip6tables/policy.OUTPUT")" "DROP DROP" "OUTPUT policy is DROP at the end (IPv4 and IPv6)"
    if [ -f /tmp/vpn_setup_complete ]; then
        log_pass "setup completion flag written"
    else
        log_fail "setup completion flag missing"
    fi
}

LEAK_CHECK_DESC="an internet connection, an established tunnel connection and outside DNS are dropped"
check_launch_closed() {
    expect_eq "$(verdict "$FW/at-launch" 93.184.216.34 tcp 443) $(fweval "$FW/at-launch" eth0 93.184.216.34 tcp 443 ESTABLISHED ORIGINAL | cut -d' ' -f1) $(verdict "$FW/at-launch" 9.9.9.9 udp 53)" \
        "DROP DROP DROP" "at launch, $LEAK_CHECK_DESC"
}

# ---------------------------------------------------------------------------
echo ""
echo "--- OpenVPN, three IP remotes and LAN_NETWORK (prod): boot ---"
reset_state
cat > "$WORK/prod.ovpn" <<'EOF'
client
dev tun
proto udp
remote 151.240.205.136 8080
remote 191.96.227.80 8080
remote 191.96.227.43 8080
EOF
# shellcheck disable=SC2054 # NAME_SERVERS is one comma-separated value
PROD_ENV=(VPN_CLIENT=openvpn VPN_CONFIG="$WORK/prod.ovpn" VPN_USER=u VPN_PASS=p LAN_NETWORK=10.0.0.0/8
          NAME_SERVERS=8.8.8.8,1.1.1.1 ENABLE_PRIVOXY=yes)
run_setup "${PROD_ENV[@]}"
check_common
check_bootstrap
expect_eq "$(grep -c -- '-o eth0 -d [0-9.]* -p udp --dport 8080 -m comment --comment vpn-bootstrap -j ACCEPT' "$FW/at-bootstrap/OUTPUT")" "3" \
    "while bootstrapping, every remote is reachable"
expect_eq "$(grep -c 'dport 53' "$FW/at-bootstrap/OUTPUT" || true)" "0" "no DNS is opened when every remote is an IP"
launch_openvpn
check_launch_closed
expect_eq "$(verdict "$FW/at-launch" 151.240.205.136 udp 8080) $(verdict "$FW/at-launch" 191.96.227.80 udp 8080) $(verdict "$FW/at-launch" 191.96.227.43 udp 8080)" \
    "ACCEPT ACCEPT ACCEPT" "at launch, every remote is reachable"
expect_eq "$(verdict "$FW/at-launch" 10.43.0.10 tcp 8989)" "ACCEPT" "at launch, the LAN is reachable"
expect_eq "$(grep -c '^10.0.0.0/8 ' "$FW/routes")" "1" "LAN route added"

echo ""
echo "--- The same container, rerun in place by the watchdog ---"
start_rerun
run_setup "${PROD_ENV[@]}"
check_common
check_bootstrap
expect_eq "$(grep -c '^10.0.0.0/8 ' "$FW/routes")" "1" "the existing LAN route is replaced, not added twice"
expect_eq "$(grep -c -- '^-o tun0 -j ACCEPT$' "$FW/iptables/OUTPUT")" "1" "the tunnel is allowed again"
launch_openvpn
check_launch_closed
expect_eq "$(verdict "$FW/at-launch" 151.240.205.136 udp 8080) $(verdict "$FW/at-launch" 191.96.227.80 udp 8080) $(verdict "$FW/at-launch" 191.96.227.43 udp 8080)" \
    "ACCEPT ACCEPT ACCEPT" "at relaunch, every remote is reachable"

# ---------------------------------------------------------------------------
echo ""
echo "--- OpenVPN, hostname remote ---"
reset_state
cat > "$WORK/host.ovpn" <<'EOF'
client
proto udp
remote vpn.example.net 1198
remote-random-hostname
EOF
run_setup VPN_CLIENT=openvpn VPN_CONFIG="$WORK/host.ovpn" VPN_USER=u VPN_PASS=p NAME_SERVERS=1.1.1.1
check_common
check_bootstrap
expect_eq "$(grep 'dport 53' "$FW/at-bootstrap/OUTPUT" | sort)" "-o eth0 -d 10.43.0.10 -p tcp --dport 53 -m comment --comment vpn-bootstrap -j ACCEPT
-o eth0 -d 10.43.0.10 -p udp --dport 53 -m comment --comment vpn-bootstrap -j ACCEPT" \
    "while bootstrapping, DNS is open only to the configured nameserver"
expect_eq "$(grep -E '^remote' /tmp/config.ovpn)" "remote 198.51.100.20 1198
remote 198.51.100.21 1198" "the hostname is pinned to its addresses in the OpenVPN config"
launch_openvpn
check_launch_closed
expect_eq "$(verdict "$FW/at-launch" 10.43.0.10 udp 53)" "DROP" "at launch, DNS on eth0 is closed again"
expect_eq "$(verdict "$FW/at-launch" 198.51.100.20 udp 1198) $(verdict "$FW/at-launch" 198.51.100.21 udp 1198)" \
    "ACCEPT ACCEPT" "at launch, every address of the remote is reachable"

# ---------------------------------------------------------------------------
echo ""
echo "--- WireGuard, hostname endpoint ---"
reset_state
cat > "$WORK/wg0.conf" <<'EOF'
[Interface]
PrivateKey = x
Address = 10.2.0.2/32

[Peer]
PublicKey = y
AllowedIPs = 0.0.0.0/0
Endpoint = vpn.example.net:51820
EOF
run_setup VPN_CLIENT=wireguard VPN_CONFIG="$WORK/wg0.conf" NAME_SERVERS=1.1.1.1
check_common
expect_eq "$(grep -vc -e '^-o lo -m comment --comment vpn-bootstrap -j ACCEPT$' \
    -e '^-o eth0 -m conntrack --ctstate RELATED,ESTABLISHED --ctdir REPLY -m comment --comment vpn-bootstrap -j ACCEPT$' \
    -e '^-o eth0 -d [0-9.]* -p [a-z]* --dport [0-9]* -m comment --comment vpn-bootstrap -j ACCEPT$' \
    "$FW/at-launch/OUTPUT" || true)" "0" \
    "when wg-quick runs, OUTPUT holds nothing beyond loopback, replies and per-server exceptions"
check_launch_closed
expect_eq "$(grep -c -- '-o eth0 -d 198.51.100.2[01] -p udp --dport 51820 -m comment --comment vpn-bootstrap -j ACCEPT' "$FW/at-launch/OUTPUT")" "2" \
    "when wg-quick runs, every endpoint address is reachable"
expect_eq "$(verdict "$FW/iptables" 198.51.100.20 udp 51820) $(verdict "$FW/iptables" 198.51.100.21 udp 51820)" \
    "ACCEPT ACCEPT" "the kill switch keeps every endpoint address"

# ---------------------------------------------------------------------------
# Docker user-defined networks (Compose's default): resolv.conf points at Docker's
# embedded DNS server, which works through nat rules Docker adds in the container.
# The rules and resolv.conf are as Docker Engine writes them (libnetwork
# resolver_unix.go setupIptablesNAT, internal/resolvconf).
DOCKER_UDP_PORT=52981
seed_docker_dns() {
    local nat="$FW/iptables.nat"
    mkdir -p "$nat" "$FW/iptables.mangle"
    echo "-d 127.0.0.11/32 -j DOCKER_OUTPUT" > "$nat/OUTPUT"
    echo "-d 127.0.0.11/32 -j DOCKER_POSTROUTING" > "$nat/POSTROUTING"
    printf '%s\n' "-d 127.0.0.11/32 -p tcp -m tcp --dport 53 -j DNAT --to-destination 127.0.0.11:41365" \
        "-d 127.0.0.11/32 -p udp -m udp --dport 53 -j DNAT --to-destination 127.0.0.11:$DOCKER_UDP_PORT" > "$nat/DOCKER_OUTPUT"
    printf '%s\n' "-s 127.0.0.11/32 -p tcp -m tcp --sport 41365 -j SNAT --to-source :53" \
        "-s 127.0.0.11/32 -p udp -m udp --sport $DOCKER_UDP_PORT -j SNAT --to-source :53" > "$nat/DOCKER_POSTROUTING"
    rm -rf "$WORK/docker-nat" && cp -R "$nat" "$WORK/docker-nat"
    # A mangle rule vpn-setup.sh does not own, like the ones wg-quick adds.
    echo '-p udp -m comment --comment "wg-quick(8) rule for wg0" -j CONNMARK --restore-mark --nfmask 0xffffffff --ctmask 0xffffffff' \
        > "$FW/iptables.mangle/PREROUTING"
}

# docker_resolv EXTSERVERS, e.g. "host(192.168.65.7)" or "1.1.1.1" (--dns 1.1.1.1).
docker_resolv() {
    cat > /etc/resolv.conf <<EOF
# Generated by Docker Engine.
# This file can be edited; Docker Engine will not make further changes once it
# has been modified.

nameserver 127.0.0.11
options ndots:0

# Based on host file: '/etc/resolv.conf' (internal resolver)
# ExtServers: [$1]
# Overrides: []
# Option ndots from: internal
EOF
}

check_docker_rules() {
    expect_eq "$(diff -r "$WORK/docker-nat" "$FW/iptables.nat" 2>&1)" "" "Docker's nat rules for 127.0.0.11 are untouched"
    expect_eq "$(grep -v '^filter ' "$FW/flushes" 2>/dev/null || true)" "" "no chain outside the filter table is flushed"
    expect_eq "$(grep -c 'wg-quick(8)' "$FW/iptables.mangle/PREROUTING" || true)" "1" "a mangle rule vpn-setup.sh does not own is kept"
    expect_eq "$(cat "$FW"/iptables.mangle/PREROUTING "$FW"/iptables.mangle/OUTPUT | grep -c -- '--comment vpn-setup ' || true)" "4" \
        "vpn-setup.sh's own mangle rules are there once (NZBGet and monitoring)"
}

docker_dns_verdict() { fweval "$1" lo 127.0.0.11 udp "$DOCKER_UDP_PORT" NEW ORIGINAL | cut -d' ' -f1; }

echo ""
echo "--- OpenVPN, hostname remote, Docker embedded DNS: boot ---"
reset_state
seed_docker_dns
docker_resolv "host(192.168.65.7)"
run_setup VPN_CLIENT=openvpn VPN_CONFIG="$WORK/host.ovpn" VPN_USER=u VPN_PASS=p
check_common
check_bootstrap
check_docker_rules
expect_eq "$(grep -c 'dport 53' "$FW/at-bootstrap/OUTPUT" || true)" "0" \
    "while bootstrapping, no DNS is opened on eth0 (the host's nameserver is queried from the host)"
expect_eq "$(grep -E '^remote' /tmp/config.ovpn)" "remote 198.51.100.20 1198
remote 198.51.100.21 1198" "the hostname is resolved through 127.0.0.11 and pinned"
launch_openvpn
check_launch_closed
expect_eq "$(docker_dns_verdict "$FW/at-launch")" "DROP" \
    "at launch, Docker's DNS server is closed (it forwards from the host's namespace)"
env -u NAME_SERVERS bash /etc/openvpn/update-resolv.sh > /dev/null 2>&1
expect_eq "$(awk '$1 == "nameserver" { print $2 }' /etc/resolv.conf | tr '\n' ' ')" "1.1.1.1 8.8.8.8 " \
    "once the tunnel is up, resolv.conf no longer points at 127.0.0.11"

echo ""
echo "--- The same container, rerun in place by the watchdog ---"
start_rerun
docker_resolv "host(192.168.65.7)" # restored by the OpenVPN down script
run_setup VPN_CLIENT=openvpn VPN_CONFIG="$WORK/host.ovpn" VPN_USER=u VPN_PASS=p
check_common
check_bootstrap
check_docker_rules
launch_openvpn
check_launch_closed
expect_eq "$(docker_dns_verdict "$FW/at-launch")" "DROP" "at relaunch, Docker's DNS server is closed"

echo ""
echo "--- OpenVPN, hostname remote, Docker embedded DNS with --dns 1.1.1.1 ---"
reset_state
seed_docker_dns
docker_resolv "1.1.1.1"
run_setup VPN_CLIENT=openvpn VPN_CONFIG="$WORK/host.ovpn" VPN_USER=u VPN_PASS=p
check_common
check_bootstrap
check_docker_rules
expect_eq "$(grep 'dport 53' "$FW/at-bootstrap/OUTPUT" | sort)" "-o eth0 -d 1.1.1.1 -p tcp --dport 53 -m comment --comment vpn-bootstrap -j ACCEPT
-o eth0 -d 1.1.1.1 -p udp --dport 53 -m comment --comment vpn-bootstrap -j ACCEPT" \
    "while bootstrapping, DNS on eth0 is open only to the --dns server Docker forwards to"
launch_openvpn
check_launch_closed

echo ""
echo "--- WireGuard, hostname endpoint, Docker embedded DNS, no DNS configured ---"
reset_state
seed_docker_dns
docker_resolv "host(192.168.65.7)"
run_setup VPN_CLIENT=wireguard VPN_CONFIG="$WORK/wg0.conf"
check_common
check_docker_rules
check_launch_closed
expect_eq "$(grep -c -- '-o eth0 -d 198.51.100.2[01] -p udp --dport 51820 -m comment --comment vpn-bootstrap -j ACCEPT' "$FW/at-launch/OUTPUT")" "2" \
    "when wg-quick runs, every endpoint address is reachable"
expect_eq "$(docker_dns_verdict "$FW/iptables")" "DROP" "Docker's DNS server is closed once the kill switch is built"
expect_eq "$(awk '$1 == "nameserver" { print $2 }' /etc/resolv.conf | tr '\n' ' ')" "1.1.1.1 8.8.8.8 " \
    "resolv.conf no longer points at 127.0.0.11"

# ---------------------------------------------------------------------------
echo ""
echo "--- A setup that fails part way leaves the firewall closed ---"
reset_state
touch "$FW/armed"
rc=0
env VPN_CLIENT=openvpn VPN_CONFIG="$WORK/prod.ovpn" LAN_NETWORK=10.0.0.0/8 bash "$VPN_SETUP" > "$WORK/setup.out" 2>&1 || rc=$?
expect_eq "$rc" "1" "vpn-setup.sh fails without credentials"
expect_eq "$(grep -c ACCEPT "$FW/policy-history" || true)" "0" "no policy is set to ACCEPT"
expect_eq "$(verdict "$FW/iptables" 93.184.216.34 tcp 443) $(verdict "$FW/iptables" 9.9.9.9 udp 53)" "DROP DROP" \
    "internet traffic and outside DNS are dropped after the failure"
check_failed_closed() {
    expect_eq "$(head -3 "$FW/leaks" 2>/dev/null)" "" "no internet traffic could leave eth0 at any point"
    expect_eq "$(cat "$FW/iptables/OUTPUT")" "-o lo -d 127.0.0.11 -j DROP
-o lo -j ACCEPT" "after the failure, OUTPUT allows loopback only, without Docker's DNS server"
    expect_eq "$(cat "$FW/iptables/INPUT")" "-i lo -j ACCEPT" "after the failure, INPUT allows loopback only"
    expect_eq "$(cat "$FW/iptables/policy.OUTPUT") $(cat "$FW/ip6tables/policy.OUTPUT")" "DROP DROP" \
        "after the failure, the OUTPUT policies are DROP (IPv4 and IPv6)"
    if [ -f /tmp/vpn_setup_complete ]; then log_fail "no setup completion flag after the failure"; else log_pass "no setup completion flag after the failure"; fi
}
check_failed_closed

echo ""
echo "--- A setup that fails after the bootstrap DNS was opened, Docker embedded DNS ---"
reset_state
seed_docker_dns
docker_resolv "1.1.1.1"
touch "$FW/fail-route-replace"
rc=0
env VPN_CLIENT=openvpn VPN_CONFIG="$WORK/host.ovpn" VPN_USER=u VPN_PASS=p LAN_NETWORK=10.0.0.0/8 bash "$VPN_SETUP" > "$WORK/setup.out" 2>&1 || rc=$?
expect_eq "$rc" "2" "vpn-setup.sh fails with the error that stopped it"
expect_eq "$(grep -c 'dport 53' "$FW/at-bootstrap/OUTPUT" || true)" "2" "the bootstrap had opened DNS on eth0 to the --dns server"
check_failed_closed
expect_eq "$(verdict "$FW/iptables" 1.1.1.1 udp 53) $(verdict "$FW/iptables" 198.51.100.20 udp 1198) $(docker_dns_verdict "$FW/iptables")" \
    "DROP DROP DROP" "after the failure, the --dns server, the VPN server and Docker's DNS server are closed"
expect_eq "$(diff -r "$WORK/docker-nat" "$FW/iptables.nat" 2>&1)" "" "Docker's nat rules for 127.0.0.11 are untouched"

echo ""
if [ "$FAILED" = true ]; then
    echo -e "${RED}Some tests failed${NC}"
    exit 1
fi
echo -e "${GREEN}All tests passed${NC}"
