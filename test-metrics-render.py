#!/usr/bin/env python3
"""Tests for the Prometheus exposition produced by root/monitoring-server.py.

The contract these pin down: nzbgetvpn_vpn_connected means traffic passes
through the tunnel, never merely that the interface has an address. An
interface that is up with an IP while the tunnel carries nothing is exactly
the state that hid a 38-hour outage in the transmissionvpn sibling image.

The nzbgetvpn_nzbget_* series follow the same rule from the other side: a
paused NZBGet must read as paused, and an API that did not answer must leave
the series out instead of reporting 0. NZBGet once sat paused for 13 hours
after a config error at start while every other signal stayed green.
test-nzbget-status.sh checks the same series against a real NZBGet.

Run: python3 test-metrics-render.py
"""
import http.server
import importlib.util
import json
import os
import sys
import tempfile
import threading

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


NZBGET_SERIES = ('nzbgetvpn_nzbget_download_paused', 'nzbgetvpn_nzbget_post_paused',
                 'nzbgetvpn_nzbget_scan_paused', 'nzbgetvpn_nzbget_download_rate_bytes',
                 'nzbgetvpn_nzbget_remaining_bytes', 'nzbgetvpn_nzbget_server_standby')


def nzbget_status(**overrides):
    """A trimmed JSON-RPC `status` result: downloading 5 GiB at 30 MB/s."""
    result = {
        'RemainingSizeLo': 1073741824, 'RemainingSizeHi': 1, 'RemainingSizeMB': 5120,
        'DownloadRate': 30000000, 'ServerPaused': False, 'DownloadPaused': False,
        'Download2Paused': False, 'ServerStandBy': False, 'PostPaused': False,
        'ScanPaused': False,
    }
    result.update(overrides)
    return result


def write_log(directory, name, lines, mtime):
    path = os.path.join(directory, name)
    with open(path, 'w') as f:
        f.write(''.join(f'Sun Nov 15 00:19:56 2026\t{line}\n' for line in lines))
    os.utime(path, (mtime, mtime))
    return path


def serve_rpc(body, code=200):
    """One-thread HTTP server answering every POST with body. Returns (url, seen, stop)."""
    seen = {}

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_POST(self):
            seen['auth'] = self.headers.get('Authorization')
            seen['body'] = self.rfile.read(int(self.headers.get('Content-Length', 0)))
            self.send_response(code)
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *args):
            pass

    server = http.server.HTTPServer(('127.0.0.1', 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return f'http://127.0.0.1:{server.server_address[1]}/jsonrpc', seen, server.shutdown


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

    print("\nNZBGet downloading")
    busy = mod.render_prometheus(status(), 5, history_ok, interface_up=True,
                                 nzbget=nzbget_status(), config_error=False)
    well_formed(mod, busy, "nzbget busy")
    check("download_paused is 0", series(busy, 'nzbgetvpn_nzbget_download_paused'), '0')
    check("post_paused is 0", series(busy, 'nzbgetvpn_nzbget_post_paused'), '0')
    check("scan_paused is 0", series(busy, 'nzbgetvpn_nzbget_scan_paused'), '0')
    check("server_standby is 0", series(busy, 'nzbgetvpn_nzbget_server_standby'), '0')
    check("download_rate_bytes", series(busy, 'nzbgetvpn_nzbget_download_rate_bytes'), '30000000')
    check("remaining_bytes combines Hi and Lo", series(busy, 'nzbgetvpn_nzbget_remaining_bytes'),
          str((1 << 32) + 1073741824))
    check("config_error is 0", series(busy, 'nzbgetvpn_nzbget_config_error'), '0')

    print("\nNZBGet paused itself with a queue: healthy by every other signal")
    paused = mod.render_prometheus(
        status(), 5, history_ok, interface_up=True, config_error=True,
        nzbget=nzbget_status(DownloadPaused=True, PostPaused=True, ScanPaused=True,
                             ServerStandBy=True, DownloadRate=0))
    well_formed(mod, paused, "nzbget paused")
    check("healthy is still 1", series(paused, 'nzbgetvpn_healthy'), '1')
    check("check{check=nzbget} is still 1", series(paused, 'nzbgetvpn_check', 'check="nzbget"'), '1')
    check("download_paused is 1", series(paused, 'nzbgetvpn_nzbget_download_paused'), '1')
    check("post_paused is 1", series(paused, 'nzbgetvpn_nzbget_post_paused'), '1')
    check("scan_paused is 1", series(paused, 'nzbgetvpn_nzbget_scan_paused'), '1')
    check("server_standby is 1", series(paused, 'nzbgetvpn_nzbget_server_standby'), '1')
    check("download_rate_bytes is 0", series(paused, 'nzbgetvpn_nzbget_download_rate_bytes'), '0')
    check("remaining_bytes still shows the queue",
          series(paused, 'nzbgetvpn_nzbget_remaining_bytes'), str((1 << 32) + 1073741824))
    check("config_error is 1", series(paused, 'nzbgetvpn_nzbget_config_error'), '1')

    print("\nNZBGet API did not answer")
    for name in NZBGET_SERIES + ('nzbgetvpn_nzbget_config_error',):
        check(f"{name} omitted, not 0", series(none, name), None)
        check(f"{name} has no TYPE line either", f'# TYPE {name} ' in none, False)

    print("\nPartial or odd status replies")
    only_mb = nzbget_status(RemainingSizeMB=3)
    del only_mb['RemainingSizeLo'], only_mb['RemainingSizeHi']
    check("remaining_bytes falls back to RemainingSizeMB",
          series(mod.render_prometheus(status(), 5, {}, interface_up=True, nzbget=only_mb),
                 'nzbgetvpn_nzbget_remaining_bytes'), str(3 * 1048576))
    odd_reply = mod.render_prometheus(status(), 5, {}, interface_up=True,
                                      nzbget={'DownloadPaused': 'yes', 'DownloadRate': None, 'PostPaused': True})
    well_formed(mod, odd_reply, "odd reply")
    check("non-boolean DownloadPaused omitted", series(odd_reply, 'nzbgetvpn_nzbget_download_paused'), None)
    check("null DownloadRate omitted", series(odd_reply, 'nzbgetvpn_nzbget_download_rate_bytes'), None)
    check("missing remaining size omitted", series(odd_reply, 'nzbgetvpn_nzbget_remaining_bytes'), None)
    check("fields that are present still export", series(odd_reply, 'nzbgetvpn_nzbget_post_paused'), '1')

    print("\nStatus fetch over HTTP")
    for var in ('NZBGET_USER', 'NZBGET_PASS'):
        os.environ.pop(var, None)
    url, seen, stop = serve_rpc(json.dumps({'version': '1.1', 'result': nzbget_status(DownloadPaused=True)}).encode())
    mod.NZBGET_RPC_URL = url
    got = mod.fetch_nzbget_status()
    check("result returned", (got or {}).get('DownloadPaused'), True)
    check("status method requested", json.loads(seen['body']).get('method'), 'status')
    check("no Authorization header without NZBGET_USER/PASS", seen['auth'], None)
    os.environ['NZBGET_USER'], os.environ['NZBGET_PASS'] = 'nzbget', 'secret'
    mod.fetch_nzbget_status()
    check("basic auth sent when both are set", seen['auth'], 'Basic bnpiZ2V0OnNlY3JldA==')
    for var in ('NZBGET_USER', 'NZBGET_PASS'):
        os.environ.pop(var)
    stop()
    check("refused connection gives None", mod.fetch_nzbget_status(), None)
    for label, body, code in (("HTTP 401", b'', 401), ("not JSON", b'<html>', 200),
                              ("error reply without result", b'{"error": {"code": 1}}', 200),
                              ("result is not an object", b'{"result": true}', 200)):
        mod.NZBGET_RPC_URL, _, stop = serve_rpc(body, code)
        check(f"{label} gives None", mod.fetch_nzbget_status(), None)
        stop()

    print("\nConfig error at the latest start (log lines as NZBGet 26.3 writes them)")
    error_start = ['ERROR\tnzbget.conf(32): Invalid value for option "DestDir" (/downloads/completed): '
                   'could not read information for directory /downloads/completed: errno 116, Stale file handle',
                   'INFO\tPausing all activities due to errors in configuration',
                   'ERROR\t[Paths][MainDir]: Failed to check "/downloads": Stale file handle',
                   'INFO\tnzbget 26.3 server-mode']
    clean_start = ['INFO\tnzbget 26.3 server-mode']
    work = ['INFO\tAdding collection Some.Release.nzb to queue', 'INFO\tCollection Some.Release added to queue']
    with tempfile.TemporaryDirectory() as tmp:
        old = write_log(tmp, 'nzbget-2026-11-14.log', clean_start + work, 1000)
        new = write_log(tmp, 'nzbget-2026-11-15.log', work + error_start + work, 2000)
        check("pause message before the latest start line", mod.nzbget_config_error([new, old]), True)
        new = write_log(tmp, 'nzbget-2026-11-15.log', error_start + work + clean_start + work, 2000)
        check("clean restart after an error start", mod.nzbget_config_error([new, old]), False)
        new = write_log(tmp, 'nzbget-2026-11-15.log', work + ['INFO\tnzbget 26.3 daemon-mode'], 2000)
        check("daemon-mode counts as a start line", mod.nzbget_config_error([new, old]), False)
        old = write_log(tmp, 'nzbget-2026-11-14.log', error_start + work, 1000)
        new = write_log(tmp, 'nzbget-2026-11-15.log', work, 2000)
        check("start line found in an older file", mod.nzbget_config_error([new, old]), True)
        check("no start line left is unknown, not 0", mod.nzbget_config_error([new]), None)
        check("no log files is unknown", mod.nzbget_config_error([]), None)
        check("unreadable file is skipped", mod.nzbget_config_error([os.path.join(tmp, 'gone.log'), old]), True)

        conf = os.path.join(tmp, 'nzbget.conf')
        with open(conf, 'w') as f:
            f.write(f'# LogFile=/elsewhere/x.log\nMainDir={tmp}\nLogFile=${{MainDir}}/nzbget.log\nWriteLog=rotate\n')
        check("rotated logs found from LogFile, newest first", mod.nzbget_log_files(conf), [new, old])
        plain = write_log(tmp, 'nzbget.log', clean_start, 3000)
        check("unrotated LogFile included", mod.nzbget_log_files(conf), [plain, new, old])
        check("missing nzbget.conf gives no files", mod.nzbget_log_files(os.path.join(tmp, 'none.conf')), [])

    print("\n" + "=" * 48)
    print(f"passed={_passed} failed={_failed}")
    return 1 if _failed else 0


if __name__ == '__main__':
    sys.exit(main())
