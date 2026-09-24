#!/usr/bin/env python3
"""
nzbgetvpn Monitoring Server

Provides HTTP endpoints for monitoring container health and metrics.
Endpoints:
- /metrics      - Prometheus exposition (text)
- /prometheus   - Same as /metrics, kept for existing scrape configs
- /health       - Current health status (JSON)
- /metrics.json - Historical health-check records and summary (JSON)
- /status       - Detailed status information (JSON)
- /logs         - Recent log entries (JSON)

A background thread runs /root/healthcheck.sh every HEALTH_CHECK_INTERVAL
seconds. Scrapes only read the cached result, so they never block on network
probes. Without this loop nothing ran the health check under Kubernetes,
which ignores the Dockerfile HEALTHCHECK, so the status file never existed.
"""

import collections
import datetime
import json
import logging
import os
import subprocess
import threading
import time
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs

# Configuration
MONITORING_PORT = int(os.environ.get('MONITORING_PORT', '8080'))
METRICS_FILE = '/config/metrics.json'
HEALTHCHECK_LOG = '/config/healthcheck.log'
MONITORING_LOG = '/config/monitoring.log'
STATUS_FILE = os.environ.get('STATUS_FILE', '/tmp/nzbgetvpn_status.json')
VPN_INTERFACE_FILE = '/tmp/vpn_interface_name'
HEALTHCHECK_SCRIPT = os.environ.get('HEALTHCHECK_SCRIPT', '/root/healthcheck.sh')
LOG_LEVEL = os.environ.get('MONITORING_LOG_LEVEL', 'INFO')
ENABLE_HEALTH_PROBE = os.environ.get('ENABLE_HEALTH_PROBE', 'true').lower() == 'true'
HEALTH_CHECK_INTERVAL = int(os.environ.get('HEALTH_CHECK_INTERVAL', '30'))
HEALTH_CHECK_RUN_TIMEOUT = int(os.environ.get('HEALTH_CHECK_RUN_TIMEOUT', '120'))
# A status older than this is treated as unhealthy: a probe that stopped
# running must not keep reporting its last good result.
HEALTH_STATUS_MAX_AGE = int(os.environ.get('HEALTH_STATUS_MAX_AGE', '180'))
# Number of recent probe runs nzbgetvpn_success_rate_percent is computed over
SUCCESS_RATE_WINDOW = int(os.environ.get('SUCCESS_RATE_WINDOW', '20'))

# Check results that count as passing / as not having run at all
PASSING = {'success', 'up', 'stable'}
NOT_RUN = {'skipped', 'unknown', ''}

logger = logging.getLogger('nzbgetvpn.monitoring')

# Per-check results of recent probe runs, newest last: {check: deque([1, 0, ...])}
_history = collections.defaultdict(lambda: collections.deque(maxlen=SUCCESS_RATE_WINDOW))
_history_lock = threading.Lock()


def read_status():
    """Return (status dict, age in seconds), or (None, None) if unavailable."""
    try:
        with open(STATUS_FILE, 'r') as f:
            data = json.load(f)
        return data, max(0.0, time.time() - os.path.getmtime(STATUS_FILE))
    except (OSError, ValueError):
        return None, None


def record_run(status):
    """Add one probe run to the success-rate history."""
    with _history_lock:
        for check, result in (status.get('checks') or {}).items():
            if result in NOT_RUN:
                continue
            _history[check].append(1 if result in PASSING else 0)


def history_snapshot():
    with _history_lock:
        return {check: list(runs) for check, runs in _history.items()}


def probe_loop():
    """Run the health check forever, recording each result."""
    logger.info(f"Health probe running {HEALTHCHECK_SCRIPT} every {HEALTH_CHECK_INTERVAL}s")
    while True:
        started = time.time()
        try:
            subprocess.run([HEALTHCHECK_SCRIPT], stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL, timeout=HEALTH_CHECK_RUN_TIMEOUT)
            status, age = read_status()
            if status is not None and age <= time.time() - started + 1:
                record_run(status)
            else:
                logger.warning("Health check finished without writing a fresh status file")
        except subprocess.TimeoutExpired:
            logger.error(f"Health check exceeded {HEALTH_CHECK_RUN_TIMEOUT}s and was killed")
        except Exception as e:
            logger.error(f"Health probe error: {e}")
        time.sleep(max(1, HEALTH_CHECK_INTERVAL - (time.time() - started)))


def vpn_interface_name():
    try:
        with open(VPN_INTERFACE_FILE, 'r') as f:
            name = f.read().strip()
            if name:
                return name
    except OSError:
        pass
    for name in ('wg0', 'tun0'):
        if os.path.exists(f'/sys/class/net/{name}'):
            return name
    return 'tun0'


def vpn_interface_state(name):
    """Local and cheap: is the interface administratively up with an address?

    This deliberately says nothing about whether traffic passes; that is what
    nzbgetvpn_vpn_connected is for.
    """
    try:
        with open(f'/sys/class/net/{name}/flags', 'r') as f:
            if not int(f.read().strip(), 16) & 0x1:  # IFF_UP
                return False
        result = subprocess.run(['ip', '-o', 'addr', 'show', 'dev', name],
                                capture_output=True, text=True, timeout=5)
        return result.returncode == 0 and (' inet ' in result.stdout or ' inet6 ' in result.stdout)
    except Exception:
        return False


def escape_label(value):
    return str(value).replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n')


def render_prometheus(status, status_age, history, interface_up, system=None,
                      start_time=None, max_age=HEALTH_STATUS_MAX_AGE):
    """Build the Prometheus exposition from already-collected inputs.

    Pure function, so the semantics can be tested without a container.
    """
    lines = []

    def gauge(name, help_text, samples):
        lines.append(f'# HELP {name} {help_text}')
        lines.append(f'# TYPE {name} gauge')
        for labels, value in samples:
            if labels:
                label_str = ','.join(f'{k}="{escape_label(v)}"' for k, v in labels.items())
                lines.append(f'{name}{{{label_str}}} {value}')
            else:
                lines.append(f'{name} {value}')

    fresh = status is not None and status_age is not None and status_age <= max_age
    checks = (status or {}).get('checks') or {}
    healthy = 1 if fresh and status.get('status') == 'healthy' else 0

    gauge('nzbgetvpn_healthy',
          'Overall health: 1 only when the latest health check is fresh and every critical check passed',
          [({}, healthy)])
    gauge('nzbgetvpn_health_check',
          'Deprecated alias of nzbgetvpn_healthy',
          [({}, healthy)])
    gauge('nzbgetvpn_vpn_interface_up',
          'VPN interface exists, is up and has an address. Does not mean traffic passes; see nzbgetvpn_vpn_connected',
          [({}, 1 if interface_up else 0)])

    # Omitted, not zero, when the probe is disabled: "not measured" must not
    # read as either connected or disconnected.
    connectivity = checks.get('vpn_connectivity')
    if connectivity != 'skipped':
        connected = 1 if fresh and connectivity == 'success' else 0
        gauge('nzbgetvpn_vpn_connected',
              'Traffic passes through the VPN tunnel (ICMP probe bound to the VPN interface)',
              [({}, connected)])

    if status is not None:
        gauge('nzbgetvpn_health_check_timestamp_seconds',
              'Unix time the latest health check finished',
              [({}, round(time.time() - status_age, 3))])

    check_samples = [({'check': name}, 1 if fresh and result in PASSING else 0)
                     for name, result in sorted(checks.items()) if result not in NOT_RUN]
    if check_samples:
        gauge('nzbgetvpn_check', 'Result of each health check in the latest run (1=pass, 0=fail)',
              check_samples)

    response_times = (status or {}).get('response_times') or {}
    rt_samples = [({'check': name}, value) for name, value in sorted(response_times.items())
                  if name in checks and checks[name] not in NOT_RUN]
    if rt_samples:
        gauge('nzbgetvpn_response_time_seconds',
              'Duration of each check in the latest health check run',
              rt_samples)

    rate_samples = [({'check': name}, round(100.0 * sum(runs) / len(runs), 2))
                    for name, runs in sorted(history.items()) if runs]
    if rate_samples:
        gauge('nzbgetvpn_success_rate_percent',
              f'Percentage of the last {SUCCESS_RATE_WINDOW} health check runs in which each check passed',
              rate_samples)

    system = system or {}
    if system.get('memory_percent') is not None:
        gauge('nzbgetvpn_memory_usage_percent', 'Memory usage percentage',
              [({}, system['memory_percent'])])
    if system.get('load_1min') is not None:
        gauge('nzbgetvpn_load_average', 'System load average (1 minute)',
              [({}, system['load_1min'])])
    if system.get('cpu_percent') is not None:
        gauge('nzbgetvpn_cpu_usage_percent', 'CPU usage percentage',
              [({}, system['cpu_percent'])])
    if start_time is not None:
        gauge('nzbgetvpn_start_time', 'Container start time (Unix timestamp)',
              [({}, start_time)])

    external_ip = (status or {}).get('external_ip')
    if external_ip and external_ip != 'unknown':
        gauge('nzbgetvpn_external_ip_info', 'External IP address seen by the latest health check',
              [({'ip': external_ip}, 1)])

    return '\n'.join(lines) + '\n'


def get_uptime():
    try:
        with open('/proc/uptime', 'r') as f:
            uptime_seconds = float(f.read().split()[0])
        return {'seconds': uptime_seconds,
                'human': str(datetime.timedelta(seconds=int(uptime_seconds)))}
    except Exception:
        return {'seconds': 0, 'human': 'unknown'}


def get_system_info():
    try:
        mem_total = mem_available = 0
        with open('/proc/meminfo', 'r') as f:
            for line in f:
                if line.startswith('MemTotal:'):
                    mem_total = int(line.split()[1]) * 1024
                elif line.startswith('MemAvailable:'):
                    mem_available = int(line.split()[1]) * 1024
        with open('/proc/loadavg', 'r') as f:
            loadavg = f.read().strip().split()[:3]
        return {
            'memory': {
                'total': mem_total,
                'available': mem_available,
                'used': mem_total - mem_available,
                'usage_percent': round(((mem_total - mem_available) / mem_total) * 100, 2) if mem_total > 0 else 0
            },
            'load_average': {
                '1min': float(loadavg[0]) if len(loadavg) > 0 else 0,
                '5min': float(loadavg[1]) if len(loadavg) > 1 else 0,
                '15min': float(loadavg[2]) if len(loadavg) > 2 else 0
            }
        }
    except Exception:
        return {}


def get_cpu_percent():
    try:
        with open('/proc/stat', 'r') as f:
            cpu_times = [int(x) for x in f.readline().split()[1:]]
        total_time = sum(cpu_times)
        return round((1 - cpu_times[3] / total_time) * 100, 2) if total_time > 0 else 0
    except Exception:
        return None


def collect_prometheus():
    status, age = read_status()
    system_info = get_system_info()
    system = {
        'memory_percent': system_info.get('memory', {}).get('usage_percent'),
        'load_1min': system_info.get('load_average', {}).get('1min'),
        'cpu_percent': get_cpu_percent(),
    }
    return render_prometheus(
        status, age, history_snapshot(),
        interface_up=vpn_interface_state(vpn_interface_name()),
        system=system,
        start_time=time.time() - get_uptime().get('seconds', 0),
    )


class MonitoringHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        """Override to use our logger"""
        logger.debug(format % args)

    def do_GET(self):
        """Handle GET requests"""
        try:
            parsed_path = urlparse(self.path)
            path = parsed_path.path
            query = parse_qs(parsed_path.query)

            if path == '/health':
                self.handle_health()
            elif path in ('/metrics', '/prometheus'):
                if query.get('format', [''])[0] == 'json':
                    self.handle_metrics_json()
                else:
                    self.handle_prometheus()
            elif path == '/metrics.json':
                self.handle_metrics_json()
            elif path == '/status':
                self.handle_status()
            elif path == '/logs':
                self.handle_logs(query)
            elif path == '/':
                self.handle_index()
            else:
                self.send_error(404)
        except Exception as e:
            logger.error(f"Error handling request {self.path}: {e}")
            self.send_error(500)

    def send_json_response(self, data, status_code=200):
        self.send_text_response(json.dumps(data, indent=2), status_code, 'application/json')

    def send_text_response(self, text, status_code=200, content_type='text/plain'):
        body = text.encode('utf-8')
        self.send_response(status_code)
        self.send_header('Content-Type', content_type)
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Cache-Control', 'no-cache')
        self.end_headers()
        self.wfile.write(body)

    def handle_health(self):
        """Health check endpoint"""
        status, age = read_status()
        if status is None:
            self.send_json_response({'status': 'unknown', 'message': 'Status file not found'}, 503)
            return
        status['age_seconds'] = round(age, 1)
        http_status = 200
        if age > HEALTH_STATUS_MAX_AGE:
            status['status'] = 'stale'
            http_status = 503
        elif status.get('status') in ['unhealthy', 'degraded']:
            http_status = 503
        self.send_json_response(status, http_status)

    def handle_metrics_json(self):
        """Historical health-check records (JSON, requires METRICS_ENABLED=true)"""
        try:
            if os.path.exists(METRICS_FILE):
                with open(METRICS_FILE, 'r') as f:
                    metrics_data = json.load(f)
                self.send_json_response({
                    'summary': self.calculate_metrics_summary(metrics_data),
                    'metrics': metrics_data
                })
            else:
                self.send_json_response({'summary': {}, 'metrics': []})
        except Exception as e:
            logger.error(f"Error reading metrics: {e}")
            self.send_json_response({'error': str(e)}, 500)

    def handle_status(self):
        """Detailed status endpoint"""
        try:
            status, _ = read_status()
            detailed = {
                'timestamp': datetime.datetime.now().isoformat(),
                'uptime': get_uptime(),
                'system': get_system_info(),
                'vpn': self.get_vpn_info(),
                'nzbget': {'responsive': (status or {}).get('checks', {}).get('nzbget') == 'success',
                           'port': 6789},
                'network': {'external_ip': (status or {}).get('external_ip', 'unknown')},
            }
            if status is not None:
                detailed['health'] = status
            self.send_json_response(detailed)
        except Exception as e:
            logger.error(f"Error getting detailed status: {e}")
            self.send_json_response({'error': str(e)}, 500)

    def handle_logs(self, query):
        """Logs endpoint"""
        try:
            lines = int(query.get('lines', ['50'])[0])
            level = query.get('level', [''])[0].upper()
            logs = self.get_recent_logs(lines, level)
            self.send_json_response({'logs': logs, 'total_lines': len(logs)})
        except Exception as e:
            logger.error(f"Error reading logs: {e}")
            self.send_json_response({'error': str(e)}, 500)

    def handle_prometheus(self):
        """Prometheus metrics endpoint"""
        try:
            self.send_text_response(collect_prometheus(), content_type='text/plain; version=0.0.4; charset=utf-8')
        except Exception as e:
            logger.error(f"Error generating Prometheus metrics: {e}")
            self.send_text_response(f"# Error: {e}\n", 500)

    def handle_index(self):
        """Index page with available endpoints"""
        html = """
        <!DOCTYPE html>
        <html>
        <head>
            <title>nzbgetvpn Monitoring</title>
            <style>
                body { font-family: Arial, sans-serif; margin: 40px; }
                .endpoint { margin: 10px 0; }
                .endpoint a { text-decoration: none; color: #0066cc; }
                .endpoint a:hover { text-decoration: underline; }
                .description { color: #666; margin-left: 20px; }
            </style>
        </head>
        <body>
            <h1>nzbgetvpn Monitoring</h1>
            <h2>Available Endpoints:</h2>
            <div class="endpoint">
                <a href="/metrics">/metrics</a>
                <div class="description">Prometheus metrics (text); also served at /prometheus</div>
            </div>
            <div class="endpoint">
                <a href="/health">/health</a>
                <div class="description">Current health status (JSON)</div>
            </div>
            <div class="endpoint">
                <a href="/metrics.json">/metrics.json</a>
                <div class="description">Historical health-check records and summary (JSON)</div>
            </div>
            <div class="endpoint">
                <a href="/status">/status</a>
                <div class="description">Detailed status information (JSON)</div>
            </div>
            <div class="endpoint">
                <a href="/logs?lines=100">/logs</a>
                <div class="description">Recent log entries (JSON) - ?lines=N&level=LEVEL</div>
            </div>
            <div style="margin-top: 30px; color: #888;">
                Generated at: """ + datetime.datetime.now().isoformat() + """
            </div>
        </body>
        </html>
        """
        self.send_text_response(html, content_type='text/html')

    def calculate_metrics_summary(self, metrics_data):
        """Calculate summary statistics from metrics"""
        if not metrics_data:
            return {}

        summary = {}
        check_types = set(metric.get('check') for metric in metrics_data)

        for check_type in check_types:
            if not check_type:
                continue

            type_metrics = [m for m in metrics_data if m.get('check') == check_type]
            if not type_metrics:
                continue

            response_times = [float(m.get('response_time', 0)) for m in type_metrics]
            successes = len([m for m in type_metrics if m.get('status') == 'success'])
            total = len(type_metrics)

            summary[check_type] = {
                'success_rate': round((successes / total) * 100, 2) if total > 0 else 0,
                'total_checks': total,
                'avg_response_time': round(sum(response_times) / len(response_times), 3) if response_times else 0,
                'max_response_time': round(max(response_times), 3) if response_times else 0,
                'last_status': type_metrics[-1].get('status') if type_metrics else 'unknown'
            }

        return summary

    def get_vpn_info(self):
        """Get VPN interface information"""
        vpn_info = {}
        for interface in ['tun0', 'wg0']:
            try:
                result = subprocess.run(['ip', 'addr', 'show', interface],
                                        capture_output=True, text=True, timeout=5)
                if result.returncode == 0:
                    vpn_info[interface] = {
                        'exists': True,
                        'up': vpn_interface_state(interface),
                        'details': result.stdout.strip()
                    }
            except Exception:
                vpn_info[interface] = {'exists': False}
        return vpn_info

    def get_recent_logs(self, lines, level_filter):
        """Get recent log entries"""
        logs = []
        try:
            if os.path.exists(HEALTHCHECK_LOG):
                with open(HEALTHCHECK_LOG, 'r') as f:
                    log_lines = f.readlines()
                if level_filter:
                    log_lines = [line for line in log_lines if f'[{level_filter}]' in line]
                for line in log_lines[-lines:]:
                    logs.append(line.strip())
        except Exception:
            pass
        return logs


def setup_logging():
    handlers = [logging.StreamHandler()]
    try:
        handlers.append(logging.FileHandler(MONITORING_LOG))
    except OSError:
        pass
    logging.basicConfig(
        level=getattr(logging, LOG_LEVEL, logging.INFO),
        format='%(asctime)s [%(levelname)s] %(message)s',
        handlers=handlers
    )


def run_server():
    """Run the monitoring server"""
    setup_logging()

    if ENABLE_HEALTH_PROBE:
        threading.Thread(target=probe_loop, name='health-probe', daemon=True).start()
    else:
        logger.info("Health probe disabled (ENABLE_HEALTH_PROBE=false); relying on external runs of healthcheck.sh")

    httpd = ThreadingHTTPServer(('', MONITORING_PORT), MonitoringHandler)
    logger.info(f"Starting monitoring server on port {MONITORING_PORT}")
    logger.info("Available endpoints: /metrics (Prometheus), /prometheus, /health, /metrics.json, /status, /logs")

    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        logger.info("Monitoring server stopped")
    finally:
        httpd.server_close()


if __name__ == '__main__':
    run_server()
