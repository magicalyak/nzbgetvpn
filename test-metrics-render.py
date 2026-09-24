#!/usr/bin/env python3
"""Tests for the Prometheus exposition produced by root/monitoring-server.py.

The contract these pin down: nzbgetvpn_vpn_connected means traffic passes
through the tunnel, never merely that the interface has an address. An
interface that is up with an IP while the tunnel carries nothing is exactly
the state that hid a 38-hour outage in the transmissionvpn sibling image.

Run: python3 test-metrics-render.py
"""
import importlib.util
import os
import sys

sys.dont_write_bytecode = True

SRC = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'root', 'monitoring-server.py')

_passed = 0
_failed = 0


def check(name, got, want):
    global _passed, _failed
    if got == want:
        print(f"  ok   {name}")
        _passed += 1
    else:
        print(f"  FAIL {name}: got {got!r} want {want!r}")
        _failed += 1


def load():
    spec = importlib.util.spec_from_file_location("monitoring_server_under_test", SRC)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def status(overall='healthy', vpn_interface='up', vpn_connectivity='success',
           news_server='success', **response_times):
    return {
        'timestamp': '2026-09-24T12:00:00+00:00',
        'status': overall,
        'external_ip': '203.0.113.7',
        'checks': {
            'nzbget': 'success',
            'vpn_interface': vpn_interface,
            'vpn_connectivity': vpn_connectivity,
            'dns': 'success',
            'news_server': news_server,
            'ip_leak': 'stable',
            'dns_leak': 'stable',
        },
        'response_times': response_times or {'nzbget': 0.012, 'vpn_connectivity': 1.004,
                                             'dns': 0.03, 'news_server': 0.25},
    }


def series(text, name, labels=''):
    """Value of one sample, or None if absent. labels is the exact {...} body."""
    prefix = f'{name}{{{labels}}} ' if labels else f'{name} '
    for line in text.splitlines():
        if line.startswith(prefix):
            return line[len(prefix):]
    return None


def well_formed(mod, text, label):
    lines = text.splitlines()
    check(f"{label}: no blank lines", any(l.strip() == '' for l in lines), False)
    names = [l.split(' ')[2] for l in lines if l.startswith('# TYPE ')]
    check(f"{label}: every TYPE declared once", len(names), len(set(names)))
    bad = [l for l in lines if not l.startswith('#') and len(l.rsplit(' ', 1)) != 2]
    check(f"{label}: every sample is 'name value'", bad, [])
    undeclared = sorted({l.split('{')[0].split(' ')[0] for l in lines if not l.startswith('#')} - set(names))
    check(f"{label}: every sample has a TYPE", undeclared, [])
    for l in lines:
        if not l.startswith('#'):
            float(l.rsplit(' ', 1)[1])


def main():
    mod = load()
    history_ok = {'nzbget': [1, 1, 1, 1], 'vpn_connectivity': [1, 1, 1, 1], 'news_server': [1, 1, 0, 1]}

    print("Healthy tunnel")
    text = mod.render_prometheus(status(), 5, history_ok, interface_up=True,
                                 system={'memory_percent': 40.1, 'load_1min': 0.5, 'cpu_percent': 3.2},
                                 start_time=1790000000.0)
    well_formed(mod, text, "healthy")
    check("vpn_interface_up is 1", series(text, 'nzbgetvpn_vpn_interface_up'), '1')
    check("vpn_connected is 1", series(text, 'nzbgetvpn_vpn_connected'), '1')
    check("healthy is 1", series(text, 'nzbgetvpn_healthy'), '1')
    check("response_time_seconds{check=nzbget}",
          series(text, 'nzbgetvpn_response_time_seconds', 'check="nzbget"'), '0.012')
    check("success_rate_percent{check=news_server}",
          series(text, 'nzbgetvpn_success_rate_percent', 'check="news_server"'), '75.0')
    check("success_rate_percent{check=vpn_connectivity}",
          series(text, 'nzbgetvpn_success_rate_percent', 'check="vpn_connectivity"'), '100.0')
    check("check{check=vpn_connectivity}", series(text, 'nzbgetvpn_check', 'check="vpn_connectivity"'), '1')
    check("external_ip_info kept", series(text, 'nzbgetvpn_external_ip_info', 'ip="203.0.113.7"'), '1')
    for name in ('nzbgetvpn_memory_usage_percent', 'nzbgetvpn_load_average',
                 'nzbgetvpn_cpu_usage_percent', 'nzbgetvpn_start_time'):
        check(f"{name} still emitted", series(text, name) is not None, True)

    print("\nDead tunnel: interface up with an address, no traffic passes")
    dead = mod.render_prometheus(status(overall='degraded', vpn_connectivity='failed', news_server='failed'),
                                 5, {'vpn_connectivity': [1, 1, 0, 0]}, interface_up=True)
    well_formed(mod, dead, "dead")
    check("vpn_interface_up stays 1", series(dead, 'nzbgetvpn_vpn_interface_up'), '1')
    check("vpn_connected is 0 despite the interface having an IP",
          series(dead, 'nzbgetvpn_vpn_connected'), '0')
    check("healthy is 0", series(dead, 'nzbgetvpn_healthy'), '0')
    check("success_rate reflects the failures",
          series(dead, 'nzbgetvpn_success_rate_percent', 'check="vpn_connectivity"'), '50.0')

    print("\nInterface gone")
    gone = mod.render_prometheus(status(overall='unhealthy', vpn_interface='missing', vpn_connectivity='failed'),
                                 5, {}, interface_up=False)
    check("vpn_interface_up is 0", series(gone, 'nzbgetvpn_vpn_interface_up'), '0')
    check("vpn_connected is 0", series(gone, 'nzbgetvpn_vpn_connected'), '0')
    check("healthy is 0", series(gone, 'nzbgetvpn_healthy'), '0')

    print("\nStale status: the probe stopped running after a good result")
    stale = mod.render_prometheus(status(), 600, history_ok, interface_up=True, max_age=180)
    check("vpn_connected is 0 when stale", series(stale, 'nzbgetvpn_vpn_connected'), '0')
    check("healthy is 0 when stale", series(stale, 'nzbgetvpn_healthy'), '0')
    check("timestamp still exported so staleness is visible",
          series(stale, 'nzbgetvpn_health_check_timestamp_seconds') is not None, True)

    print("\nNo status file at all")
    none = mod.render_prometheus(None, None, {}, interface_up=True)
    well_formed(mod, none, "none")
    check("vpn_connected is 0, not absent", series(none, 'nzbgetvpn_vpn_connected'), '0')
    check("healthy is 0", series(none, 'nzbgetvpn_healthy'), '0')

    print("\nConnectivity probe disabled")
    off = mod.render_prometheus(status(vpn_connectivity='skipped', news_server='skipped'), 5, {}, interface_up=True)
    check("vpn_connected omitted rather than guessed", series(off, 'nzbgetvpn_vpn_connected'), None)
    check("skipped news_server has no check sample",
          series(off, 'nzbgetvpn_check', 'check="news_server"'), None)

    print("\nHistory is recorded per run, skipping checks that did not run")
    mod._history.clear()
    mod.record_run(status())
    mod.record_run(status(vpn_connectivity='failed', news_server='skipped'))
    hist = mod.history_snapshot()
    check("vpn_connectivity history", hist.get('vpn_connectivity'), [1, 0])
    check("skipped run not counted for news_server", hist.get('news_server'), [1])

    print("\nLabel values are escaped")
    odd = status()
    odd['external_ip'] = 'a"b\\c'
    esc = mod.render_prometheus(odd, 5, {}, interface_up=True)
    check("quote and backslash escaped", 'ip="a\\"b\\\\c"' in esc, True)

    print("\n" + "=" * 48)
    print(f"passed={_passed} failed={_failed}")
    return 1 if _failed else 0


if __name__ == '__main__':
    sys.exit(main())
