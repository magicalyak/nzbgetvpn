#!/usr/bin/env python3
"""
nzbgetvpn Monitoring Server

Provides HTTP endpoints for monitoring container health and metrics.
Endpoints:
- /health - Current health status (JSON)
- /metrics - Historical metrics (JSON)
- /status - Detailed status information (JSON)
- /logs - Recent log entries (JSON)
- /prometheus - Prometheus-compatible metrics (text)
"""

import json
import os
import time
import datetime
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs
import threading
import subprocess
import logging

# Configuration
MONITORING_PORT = int(os.environ.get('MONITORING_PORT', '8080'))
METRICS_FILE = '/config/metrics.json'
HEALTHCHECK_LOG = '/config/healthcheck.log'
STATUS_FILE = '/tmp/nzbgetvpn_status.json'
LOG_LEVEL = os.environ.get('MONITORING_LOG_LEVEL', 'INFO')

# Setup logging
logging.basicConfig(
    level=getattr(logging, LOG_LEVEL),
    format='%(asctime)s [%(levelname)s] %(message)s',
    handlers=[
        logging.FileHandler('/config/monitoring.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

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
            elif path == '/metrics':
                self.handle_metrics()
            elif path == '/status':
                self.handle_status()
            elif path == '/logs':
                self.handle_logs(query)
            elif path == '/prometheus':
                self.handle_prometheus()
            elif path == '/':
                self.handle_index()
            else:
                self.send_error(404)
        except Exception as e:
            logger.error(f"Error handling request {self.path}: {e}")
            self.send_error(500)
    
    def send_json_response(self, data, status_code=200):
        """Send JSON response"""
        response = json.dumps(data, indent=2)
        self.send_response(status_code)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(response)))
        self.send_header('Cache-Control', 'no-cache')
        self.end_headers()
        self.wfile.write(response.encode())
    
    def send_text_response(self, text, status_code=200, content_type='text/plain'):
        """Send text response"""
        self.send_response(status_code)
        self.send_header('Content-Type', content_type)
        self.send_header('Content-Length', str(len(text)))
        self.send_header('Cache-Control', 'no-cache')
        self.end_headers()
        self.wfile.write(text.encode())
    
    def handle_health(self):
        """Health check endpoint"""
        try:
            if os.path.exists(STATUS_FILE):
                with open(STATUS_FILE, 'r') as f:
                    status_data = json.load(f)
                
                # Determine HTTP status code based on health
                http_status = 200
                if status_data.get('status') in ['unhealthy', 'degraded']:
                    http_status = 503
                elif status_data.get('status') == 'warning':
                    http_status = 200  # Warning is still OK for load balancers
                
                self.send_json_response(status_data, http_status)
            else:
                self.send_json_response({
                    'status': 'unknown',
                    'message': 'Status file not found'
                }, 503)
        except Exception as e:
            logger.error(f"Error reading health status: {e}")
            self.send_json_response({
                'status': 'error',
                'message': str(e)
            }, 500)
    
    def handle_metrics(self):
        """Metrics endpoint"""
        try:
            if os.path.exists(METRICS_FILE):
                with open(METRICS_FILE, 'r') as f:
                    metrics_data = json.load(f)
                
                # Add summary statistics
                summary = self.calculate_metrics_summary(metrics_data)
                
                response = {
                    'summary': summary,
                    'metrics': metrics_data
                }
                self.send_json_response(response)
            else:
                self.send_json_response({
                    'summary': {},
                    'metrics': []
                })
        except Exception as e:
            logger.error(f"Error reading metrics: {e}")
            self.send_json_response({
                'error': str(e)
            }, 500)
    
    def handle_status(self):
        """Detailed status endpoint"""
        try:
            status = self.get_detailed_status()
            self.send_json_response(status)
        except Exception as e:
            logger.error(f"Error getting detailed status: {e}")
            self.send_json_response({
                'error': str(e)
            }, 500)
    
    def handle_logs(self, query):
        """Logs endpoint"""
        try:
            lines = int(query.get('lines', ['50'])[0])
            level = query.get('level', [''])[0].upper()
            
            logs = self.get_recent_logs(lines, level)
            self.send_json_response({
                'logs': logs,
                'total_lines': len(logs)
            })
        except Exception as e:
            logger.error(f"Error reading logs: {e}")
            self.send_json_response({
                'error': str(e)
            }, 500)
    
    def handle_prometheus(self):
        """Prometheus metrics endpoint"""
        try:
            metrics = self.get_prometheus_metrics()
            self.send_text_response(metrics, content_type='text/plain; version=0.0.4')
        except Exception as e:
            logger.error(f"Error generating Prometheus metrics: {e}")
            self.send_text_response(f"# Error: {e}")
    
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
                <a href="/health">/health</a>
                <div class="description">Current health status (JSON)</div>
            </div>
            <div class="endpoint">
                <a href="/metrics">/metrics</a>
                <div class="description">Historical metrics and summary (JSON)</div>
            </div>
            <div class="endpoint">
                <a href="/status">/status</a>
                <div class="description">Detailed status information (JSON)</div>
            </div>
            <div class="endpoint">
                <a href="/logs?lines=100">/logs</a>
                <div class="description">Recent log entries (JSON) - ?lines=N&level=LEVEL</div>
            </div>
            <div class="endpoint">
                <a href="/prometheus">/prometheus</a>
                <div class="description">Prometheus-compatible metrics (text)</div>
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
            
            # Calculate statistics
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
    
    def get_detailed_status(self):
        """Get detailed system status"""
        status = {
            'timestamp': datetime.datetime.now().isoformat(),
            'uptime': self.get_uptime(),
            'system': self.get_system_info(),
            'vpn': self.get_vpn_info(),
            'nzbget': self.get_nzbget_info(),
            'network': self.get_network_info()
        }
        
        # Include basic health status if available
        if os.path.exists(STATUS_FILE):
            try:
                with open(STATUS_FILE, 'r') as f:
                    health_status = json.load(f)
                status['health'] = health_status
            except:
                pass
        
        return status
    
    def get_uptime(self):
        """Get container uptime"""
        try:
            with open('/proc/uptime', 'r') as f:
                uptime_seconds = float(f.read().split()[0])
            return {
                'seconds': uptime_seconds,
                'human': str(datetime.timedelta(seconds=int(uptime_seconds)))
            }
        except:
            return {'seconds': 0, 'human': 'unknown'}
    
    def get_system_info(self):
        """Get system information"""
        try:
            # Memory info
            with open('/proc/meminfo', 'r') as f:
                meminfo = f.read()
            
            mem_total = 0
            mem_available = 0
            for line in meminfo.split('\n'):
                if line.startswith('MemTotal:'):
                    mem_total = int(line.split()[1]) * 1024  # Convert to bytes
                elif line.startswith('MemAvailable:'):
                    mem_available = int(line.split()[1]) * 1024
            
            # Load average
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
        except:
            return {}
    
    def get_vpn_info(self):
        """Get VPN interface information"""
        try:
            vpn_info = {}
            
            # Check for VPN interfaces
            for interface in ['tun0', 'wg0']:
                try:
                    result = subprocess.run(['ip', 'addr', 'show', interface], 
                                          capture_output=True, text=True, timeout=5)
                    if result.returncode == 0:
                        vpn_info[interface] = {
                            'exists': True,
                            'up': 'UP' in result.stdout,
                            'details': result.stdout.strip()
                        }
                except:
                    vpn_info[interface] = {'exists': False}
            
            return vpn_info
        except:
            return {}
    
    def get_nzbget_info(self):
        """Get NZBGet information"""
        try:
            # Simple connectivity check
            result = subprocess.run(['curl', '-sSf', '--max-time', '5', 'http://localhost:6789'], 
                                  capture_output=True, timeout=10)
            return {
                'responsive': result.returncode == 0,
                'port': 6789
            }
        except:
            return {'responsive': False, 'port': 6789}
    
    def get_network_info(self):
        """Get network information"""
        try:
            # External IP
            external_ip = 'unknown'
            try:
                result = subprocess.run(['curl', '-s', '--max-time', '5', 'ifconfig.me'], 
                                      capture_output=True, text=True, timeout=10)
                if result.returncode == 0:
                    external_ip = result.stdout.strip()
            except:
                pass
            
            return {
                'external_ip': external_ip
            }
        except:
            return {}
    
    def get_recent_logs(self, lines, level_filter):
        """Get recent log entries"""
        logs = []
        try:
            if os.path.exists(HEALTHCHECK_LOG):
                with open(HEALTHCHECK_LOG, 'r') as f:
                    log_lines = f.readlines()
                
                # Filter by level if specified
                if level_filter:
                    log_lines = [line for line in log_lines if f'[{level_filter}]' in line]
                
                # Get last N lines
                recent_lines = log_lines[-lines:] if len(log_lines) > lines else log_lines
                
                for line in recent_lines:
                    logs.append(line.strip())
        except:
            pass
        
        return logs
    
    def get_prometheus_metrics(self):
        """Generate Prometheus-compatible metrics"""
        metrics_lines = [
            '# HELP nzbgetvpn_health_check Health check status (1=healthy, 0=unhealthy)',
            '# TYPE nzbgetvpn_health_check gauge',
        ]
        
        try:
            # Read current status
            if os.path.exists(STATUS_FILE):
                with open(STATUS_FILE, 'r') as f:
                    status_data = json.load(f)
                
                # Overall health
                health_value = 1 if status_data.get('status') == 'healthy' else 0
                metrics_lines.append(f'nzbgetvpn_health_check {health_value}')
                
                # Individual check metrics
                checks = status_data.get('checks', {})
                for check_name, check_status in checks.items():
                    check_value = 1 if check_status == 'success' else 0
                    metrics_lines.append(f'nzbgetvpn_check{{check="{check_name}"}} {check_value}')
            
            # Read metrics file for response times
            if os.path.exists(METRICS_FILE):
                with open(METRICS_FILE, 'r') as f:
                    metrics_data = json.load(f)
                
                summary = self.calculate_metrics_summary(metrics_data)
                
                metrics_lines.extend([
                    '',
                    '# HELP nzbgetvpn_response_time_seconds Response time for health checks',
                    '# TYPE nzbgetvpn_response_time_seconds gauge',
                ])
                
                for check_type, stats in summary.items():
                    avg_time = stats.get('avg_response_time', 0)
                    max_time = stats.get('max_response_time', 0)
                    success_rate = stats.get('success_rate', 0)
                    
                    metrics_lines.extend([
                        f'nzbgetvpn_response_time_seconds{{check="{check_type}",stat="average"}} {avg_time}',
                        f'nzbgetvpn_response_time_seconds{{check="{check_type}",stat="maximum"}} {max_time}',
                        f'nzbgetvpn_success_rate_percent{{check="{check_type}"}} {success_rate}',
                    ])
        
        except Exception as e:
            metrics_lines.append(f'# Error: {e}')
        
        return '\n'.join(metrics_lines) + '\n'

def run_server():
    """Run the monitoring server"""
    server_address = ('', MONITORING_PORT)
    httpd = HTTPServer(server_address, MonitoringHandler)
    
    logger.info(f"Starting monitoring server on port {MONITORING_PORT}")
    logger.info(f"Available endpoints: /health, /metrics, /status, /logs, /prometheus")
    
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        logger.info("Monitoring server stopped")
    finally:
        httpd.server_close()

if __name__ == '__main__':
    run_server() 