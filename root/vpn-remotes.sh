#!/bin/bash
# shellcheck shell=bash
# VPN server parsing and kill switch exceptions, sourced by vpn-setup.sh.
# Ported from transmissionvpn so both images handle servers the same way.
#
# Callers may define remote_log before sourcing this file to route messages into
# their own log format.

if ! declare -F remote_log >/dev/null; then
    remote_log() { echo "[VPN-REMOTES] $*"; }
fi

vpn_is_ipv4() {
    [[ "$1" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]
}

# Print one "host port proto" line per remote directive in CONFIG.
# A remote line is "remote HOST [PORT] [PROTO]". Missing fields come from the
# global port/proto directives, then OpenVPN's defaults (1194, udp). OpenVPN
# accepts udp4, udp6, tcp-client, tcp4 and so on; iptables wants udp or tcp.
vpn_list_remotes() {
    local config="$1" default_port default_proto host port proto

    [ -r "$config" ] || return 1
    default_port=$(tr -d '\r' < "$config" | awk '$1 == "port" { print $2; exit }')
    default_proto=$(tr -d '\r' < "$config" | awk '$1 == "proto" { print $2; exit }')
    default_port="${default_port:-1194}"
    default_proto="${default_proto:-udp}"

    while read -r _ host port proto _; do
        [ -n "$host" ] || continue
        port="${port:-$default_port}"
        proto="${proto:-$default_proto}"
        case "${proto,,}" in
            tcp*) proto="tcp" ;;
            *) proto="udp" ;;
        esac
        echo "$host $port $proto"
    done < <(tr -d '\r' < "$config" | grep -E '^[[:space:]]*remote[[:space:]]')
}

# Print every IPv4 address HOST resolves to, one per line. OpenVPN may connect to
# any of them, so all of them need an exception.
vpn_resolve_ipv4() {
    local host="$1" ips

    if vpn_is_ipv4 "$host"; then
        echo "$host"
        return 0
    fi
    # The server lines in nslookup output end in #53 or :53 and are filtered out here.
    ips=$(nslookup "$host" 2>/dev/null | awk '/^Address:/ { print $2 }' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | sort -u || true)
    if [ -z "$ips" ]; then
        ips=$({ getent ahostsv4 "$host" 2>/dev/null || getent hosts "$host" 2>/dev/null; } | awk '{ print $1 }' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | sort -u || true)
    fi
    [ -n "$ips" ] || return 1
    echo "$ips"
}

# Add an OUTPUT rule unless an identical one is already there.
# Returns 0 when added, 1 when already present, 2 when iptables refused it.
vpn_ensure_output_rule() {
    local mode="$1"
    shift
    iptables -C OUTPUT "$@" 2>/dev/null && return 1
    if [ "$mode" = "insert" ]; then
        iptables -I OUTPUT 1 "$@" || return 2
    else
        iptables -A OUTPUT "$@" || return 2
    fi
}

# Allow OpenVPN to reach every address of every remote in CONFIG over eth0.
# MODE is "append" (building a chain) or "insert" (a live chain that already ends
# in DROP). Any further arguments are added to each rule, e.g. a comment match.
# Without any remote directive, OpenVPN's default port 1194 is allowed on udp and
# tcp so a config that sets its server some other way still connects.
# Sets VPN_REMOTE_COUNT and VPN_EXCEPTION_COUNT for the caller.
vpn_allow_remotes() {
    local config="$1" mode="${2:-append}" host port proto ips ip rc
    shift 2 || shift $#

    VPN_REMOTE_COUNT=0
    VPN_EXCEPTION_COUNT=0

    while read -r host port proto; do
        VPN_REMOTE_COUNT=$((VPN_REMOTE_COUNT + 1))
        case "$port" in
            '' | *[!0-9]*)
                remote_log "WARN: Skipping VPN remote $host: invalid port '$port'"
                continue
                ;;
        esac
        if ! ips=$(vpn_resolve_ipv4 "$host"); then
            remote_log "WARN: Could not resolve VPN remote $host. OpenVPN will not be able to use this remote."
            continue
        fi
        for ip in $ips; do
            rc=0
            vpn_ensure_output_rule "$mode" -o eth0 -d "$ip" -p "$proto" --dport "$port" "$@" -j ACCEPT || rc=$?
            case "$rc" in
                0)
                    remote_log "Kill switch exception for VPN remote $host: $ip:$port ($proto)"
                    VPN_EXCEPTION_COUNT=$((VPN_EXCEPTION_COUNT + 1))
                    ;;
                2) remote_log "WARN: Failed to add kill switch exception for $ip:$port ($proto)" ;;
            esac
        done
    done < <(vpn_list_remotes "$config")

    if [ "$VPN_REMOTE_COUNT" -eq 0 ]; then
        remote_log "WARN: No remote directive found in $config. Allowing OpenVPN's default port 1194 (udp and tcp)."
        for proto in udp tcp; do
            if vpn_ensure_output_rule "$mode" -o eth0 -p "$proto" --dport 1194 "$@" -j ACCEPT; then
                VPN_EXCEPTION_COUNT=$((VPN_EXCEPTION_COUNT + 1))
            fi
        done
        return 0
    fi

    remote_log "Added $VPN_EXCEPTION_COUNT kill switch exception(s) for $VPN_REMOTE_COUNT OpenVPN remote(s)"
}

# Succeed if any remote in CONFIG is a hostname, i.e. OpenVPN needs DNS to reach it.
vpn_remotes_need_dns() {
    local host
    while read -r host _; do
        vpn_is_ipv4 "$host" || return 0
    done < <(vpn_list_remotes "$1")
    return 1
}

# Print one "host port" line per WireGuard peer Endpoint in CONFIG. IPv6 endpoints
# are skipped: IPv6 is dropped outright by the kill switch.
vpn_list_wg_endpoints() {
    local config="$1" endpoint
    [ -r "$config" ] || return 1
    while read -r endpoint; do
        case "$endpoint" in
            \[*) continue ;;
            *:*) echo "${endpoint%:*} ${endpoint##*:}" ;;
        esac
    done < <(tr -d '\r' < "$config" | awk -F= 'tolower($1) ~ /^[[:space:]]*endpoint[[:space:]]*$/ { gsub(/[[:space:]]/, "", $2); print $2 }')
}

# Succeed if any WireGuard endpoint in CONFIG is a hostname.
vpn_wg_endpoints_need_dns() {
    local host
    while read -r host _; do
        vpn_is_ipv4 "$host" || return 0
    done < <(vpn_list_wg_endpoints "$1")
    return 1
}

# Allow WireGuard to reach every peer endpoint in CONFIG over eth0 (udp).
# MODE and any further arguments work as for vpn_allow_remotes.
vpn_allow_wg_endpoints() {
    local config="$1" mode="${2:-append}" host port ips ip rc
    shift 2 || shift $#
    while read -r host port; do
        case "$port" in
            '' | *[!0-9]*)
                remote_log "WARN: Skipping WireGuard endpoint $host: invalid port '$port'"
                continue
                ;;
        esac
        if ! ips=$(vpn_resolve_ipv4 "$host"); then
            remote_log "WARN: Could not resolve WireGuard endpoint $host."
            continue
        fi
        for ip in $ips; do
            rc=0
            vpn_ensure_output_rule "$mode" -o eth0 -d "$ip" -p udp --dport "$port" "$@" -j ACCEPT || rc=$?
            case "$rc" in
                0) remote_log "Kill switch exception for WireGuard endpoint $host: $ip:$port (udp)" ;;
                2) remote_log "WARN: Failed to add kill switch exception for $ip:$port (udp)" ;;
            esac
        done
    done < <(vpn_list_wg_endpoints "$config")
}

# Replace each hostname remote in CONFIG with one remote line per IPv4 address it
# resolves to now, keeping the rest of the line (port, proto). vpn-setup.sh only
# allows DNS on eth0 while it builds the kill switch, and the kill switch only
# allows the addresses resolved here, so OpenVPN, which the s6 service starts
# afterwards, must not look the names up again when it starts or reconnects.
# A remote that does not resolve is left as it is.
vpn_pin_remotes() {
    local config="$1" tmp="$1.pinned" line host rest ips ip
    : > "$tmp"
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%$'\r'}"
        if [[ "$line" =~ ^[[:space:]]*remote[[:space:]]+([^[:space:]]+)(.*)$ ]]; then
            host="${BASH_REMATCH[1]}"
            rest="${BASH_REMATCH[2]}"
            if ! vpn_is_ipv4 "$host" && ips=$(vpn_resolve_ipv4 "$host"); then
                remote_log "Pinned VPN remote $host to" $ips
                for ip in $ips; do
                    echo "remote $ip$rest" >> "$tmp"
                done
                continue
            fi
        fi
        echo "$line" >> "$tmp"
    done < "$config"
    # It would prepend random labels to what are now IP addresses.
    if grep -q '^[[:space:]]*remote-random-hostname' "$tmp"; then
        remote_log "Removed remote-random-hostname: the remotes are pinned to IP addresses."
        sed -i '/^[[:space:]]*remote-random-hostname/d' "$tmp"
    fi
    mv "$tmp" "$config"
}
