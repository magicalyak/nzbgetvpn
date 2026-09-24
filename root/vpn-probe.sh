#!/bin/bash
# shellcheck shell=bash
# Shared tunnel reachability probe, sourced by /root/healthcheck.sh.
#
# This is the single definition of "the tunnel carries traffic". It sends ICMP
# out of the VPN interface itself, so it fails when the tunnel is dead even if
# the interface still exists and holds an address. An address on tun0/wg0 only
# proves the client configured the interface; it says nothing about whether
# packets make it through.
#
# Ported from the transmissionvpn sibling image so both report the same thing.

# Primary target. Cloudflare answers ICMP reliably; avoid Google anycast IPs,
# which rate-limit ICMP from VPN exit addresses and cause false failures.
VPN_PROBE_HOST=${VPN_PROBE_HOST:-1.1.1.1}
# Fallback target. A failure is only reported when both targets fail, so one
# host filtering ICMP cannot mark the tunnel as down. Set empty to disable.
VPN_PROBE_HOST_FALLBACK=${VPN_PROBE_HOST_FALLBACK-9.9.9.9}

if ! declare -F probe_warn >/dev/null; then
    probe_warn() { echo "[VPN-PROBE] WARN: $*" >&2; }
fi

# A private address is not routed through the tunnel, so probing it says
# nothing about the tunnel. Substitute a public target and say so.
override_lan_probe_target() {
    case "$VPN_PROBE_HOST" in
        10.*|192.168.*|127.*|169.254.*|\
        172.1[6-9].*|172.2[0-9].*|172.3[01].*)
            probe_warn "VPN_PROBE_HOST ($VPN_PROBE_HOST) is a private address and is not routed through the VPN. Using 1.1.1.1 instead."
            VPN_PROBE_HOST="1.1.1.1"
            ;;
    esac
}

# Three packets so a single dropped reply is not a failure; ping exits 0 if
# any reply arrives.
ping_host_via_vpn() {
    local vpn_if="$1"
    local host="$2"
    ping -c 3 -i 0.5 -W 3 -I "$vpn_if" "$host" > /dev/null 2>&1
}

# Returns 0 and prints the answering host if either target replies through
# <vpn_if>; returns 1 only when both fail. Worst case is about 8 seconds.
vpn_probe_tunnel() {
    local vpn_if="$1"

    if ping_host_via_vpn "$vpn_if" "$VPN_PROBE_HOST"; then
        echo "$VPN_PROBE_HOST"
        return 0
    fi
    if [ -n "$VPN_PROBE_HOST_FALLBACK" ] && ping_host_via_vpn "$vpn_if" "$VPN_PROBE_HOST_FALLBACK"; then
        echo "$VPN_PROBE_HOST_FALLBACK"
        return 0
    fi
    return 1
}
