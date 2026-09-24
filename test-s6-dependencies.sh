#!/bin/bash
# Checks that the services the kill switch protects start only after the cont-init
# scripts (vpn-setup is 50-vpn-setup) have finished, and that the s6-rc service
# database still compiles with those dependencies. Run it inside the image:
#
#   docker run --rm --entrypoint bash -v "$PWD:/src:ro" nzbgetvpn:test /src/test-s6-dependencies.sh

set -uo pipefail

for S6_SOURCES in /package/admin/s6-overlay*/etc/s6-rc/sources; do break; done
DB="$(mktemp -d)/compiled"
FAILED=0

if ! /command/s6-rc-compile "$DB" "$S6_SOURCES" /etc/s6-overlay/s6-rc.d; then
    echo "  FAIL s6-rc-compile rejected the service definitions"
    exit 1
fi
echo "  ok   s6-rc service database compiles"

for svc in svc-nzbget svc-cron privoxy monitoring auto-restart openvpn; do
    if /command/s6-rc-db -c "$DB" all-dependencies "$svc" | grep -qx legacy-cont-init; then
        echo "  ok   $svc starts after cont-init"
    else
        echo "  FAIL $svc can start before cont-init (and the kill switch)"
        FAILED=$((FAILED + 1))
    fi
done

[[ $FAILED -eq 0 ]]
