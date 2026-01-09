#!/usr/bin/env python3
"""
Server & Network Monitoring Tool
A comprehensive monitoring solution for server and network engineers
"""

import psutil
import socket
import subprocess
import time
import json
import logging
from datetime import datetime
from typing import Dict, List, Optional
from dataclasses import dataclass, asdict
import argparse


@dataclass
class ServerHealth:
    """Represents server health metrics"""
    timestamp: str
    hostname: str
    cpu_percent: float
    memory_percent: float
    memory_used_gb: float
    memory_total_gb: float
    disk_percent: float
    disk_used_gb: float
    disk_total_gb: float
    network_sent_mb: float
    network_recv_mb: float
    boot_time: str
    uptime_hours: float


@dataclass
class ServiceCheck:
    """Represents a service availability check"""
    timestamp: str
    service_name: str
    host: str
    port: Optional[int]
    status: str
    response_time_ms: float
    message: str


class ServerMonitor:
    """Main server monitoring class"""

    def __init__(self, log_file: str = "server_monitor.log"):
        self.setup_logging(log_file)
        self.network_baseline = psutil.net_io_counters()

    def setup_logging(self, log_file: str):
        """Setup logging configuration"""
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler(log_file),
                logging.StreamHandler()
            ]
        )
        self.logger = logging.getLogger(__name__)

    def get_server_health(self) -> ServerHealth:
        """Collect comprehensive server health metrics"""
        # CPU
        cpu_percent = psutil.cpu_percent(interval=1)

        # Memory
        memory = psutil.virtual_memory()
        memory_percent = memory.percent
        memory_used_gb = memory.used / (1024**3)
        memory_total_gb = memory.total / (1024**3)

        # Disk
        disk = psutil.disk_usage('/')
        disk_percent = disk.percent
        disk_used_gb = disk.used / (1024**3)
        disk_total_gb = disk.total / (1024**3)

        # Network
        net = psutil.net_io_counters()
        network_sent_mb = net.bytes_sent / (1024**2)
        network_recv_mb = net.bytes_recv / (1024**2)

        # Uptime
        boot_time = datetime.fromtimestamp(psutil.boot_time())
        uptime = datetime.now() - boot_time
        uptime_hours = uptime.total_seconds() / 3600

        health = ServerHealth(
            timestamp=datetime.now().isoformat(),
            hostname=socket.gethostname(),
            cpu_percent=round(cpu_percent, 2),
            memory_percent=round(memory_percent, 2),
            memory_used_gb=round(memory_used_gb, 2),
            memory_total_gb=round(memory_total_gb, 2),
            disk_percent=round(disk_percent, 2),
            disk_used_gb=round(disk_used_gb, 2),
            disk_total_gb=round(disk_total_gb, 2),
            network_sent_mb=round(network_sent_mb, 2),
            network_recv_mb=round(network_recv_mb, 2),
            boot_time=boot_time.isoformat(),
            uptime_hours=round(uptime_hours, 2)
        )

        return health

    def check_thresholds(self, health: ServerHealth,
                        cpu_threshold: float = 80.0,
                        memory_threshold: float = 85.0,
                        disk_threshold: float = 90.0) -> List[str]:
        """Check if any metrics exceed thresholds"""
        alerts = []

        if health.cpu_percent > cpu_threshold:
            alerts.append(f"⚠️  CPU usage high: {health.cpu_percent}% (threshold: {cpu_threshold}%)")

        if health.memory_percent > memory_threshold:
            alerts.append(f"⚠️  Memory usage high: {health.memory_percent}% (threshold: {memory_threshold}%)")

        if health.disk_percent > disk_threshold:
            alerts.append(f"⚠️  Disk usage high: {health.disk_percent}% (threshold: {disk_threshold}%)")

        return alerts

    def ping_host(self, host: str, timeout: int = 2) -> ServiceCheck:
        """Ping a host to check connectivity"""
        start_time = time.time()

        try:
            # Use ping command (cross-platform)
            param = '-n' if socket.gethostname().startswith('WIN') else '-c'
            command = ['ping', param, '1', '-W', str(timeout), host]

            result = subprocess.run(
                command,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=timeout + 1
            )

            response_time = (time.time() - start_time) * 1000

            if result.returncode == 0:
                status = "UP"
                message = "Host is reachable"
            else:
                status = "DOWN"
                message = "Host is unreachable"

        except subprocess.TimeoutExpired:
            response_time = timeout * 1000
            status = "TIMEOUT"
            message = f"Ping timeout after {timeout}s"
        except Exception as e:
            response_time = (time.time() - start_time) * 1000
            status = "ERROR"
            message = f"Error: {str(e)}"

        return ServiceCheck(
            timestamp=datetime.now().isoformat(),
            service_name="PING",
            host=host,
            port=None,
            status=status,
            response_time_ms=round(response_time, 2),
            message=message
        )

    def check_port(self, host: str, port: int, timeout: int = 3) -> ServiceCheck:
        """Check if a port is open on a host"""
        start_time = time.time()

        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(timeout)
            result = sock.connect_ex((host, port))
            sock.close()

            response_time = (time.time() - start_time) * 1000

            if result == 0:
                status = "OPEN"
                message = f"Port {port} is open"
            else:
                status = "CLOSED"
                message = f"Port {port} is closed"

        except socket.timeout:
            response_time = timeout * 1000
            status = "TIMEOUT"
            message = f"Connection timeout after {timeout}s"
        except Exception as e:
            response_time = (time.time() - start_time) * 1000
            status = "ERROR"
            message = f"Error: {str(e)}"

        return ServiceCheck(
            timestamp=datetime.now().isoformat(),
            service_name=f"TCP/{port}",
            host=host,
            port=port,
            status=status,
            response_time_ms=round(response_time, 2),
            message=message
        )

    def check_http_service(self, url: str, timeout: int = 5) -> ServiceCheck:
        """Check HTTP/HTTPS service availability"""
        try:
            import urllib.request
            start_time = time.time()

            req = urllib.request.Request(url, method='GET')
            response = urllib.request.urlopen(req, timeout=timeout)
            response_time = (time.time() - start_time) * 1000

            status_code = response.getcode()

            if 200 <= status_code < 300:
                status = "UP"
                message = f"HTTP {status_code} OK"
            else:
                status = "WARNING"
                message = f"HTTP {status_code}"

        except urllib.error.URLError as e:
            response_time = (time.time() - start_time) * 1000
            status = "DOWN"
            message = f"Error: {str(e.reason)}"
        except Exception as e:
            response_time = (time.time() - start_time) * 1000
            status = "ERROR"
            message = f"Error: {str(e)}"

        return ServiceCheck(
            timestamp=datetime.now().isoformat(),
            service_name="HTTP",
            host=url,
            port=None,
            status=status,
            response_time_ms=round(response_time, 2),
            message=message
        )

    def print_health_report(self, health: ServerHealth):
        """Print a formatted health report"""
        print("\n" + "="*60)
        print(f"📊 SERVER HEALTH REPORT - {health.hostname}")
        print("="*60)
        print(f"Timestamp: {health.timestamp}")
        print(f"Uptime: {health.uptime_hours:.2f} hours")
        print("\n💻 SYSTEM RESOURCES:")
        print(f"  CPU Usage:    {health.cpu_percent}%")
        print(f"  Memory Usage: {health.memory_percent}% ({health.memory_used_gb:.2f}GB / {health.memory_total_gb:.2f}GB)")
        print(f"  Disk Usage:   {health.disk_percent}% ({health.disk_used_gb:.2f}GB / {health.disk_total_gb:.2f}GB)")
        print(f"\n🌐 NETWORK:")
        print(f"  Sent:     {health.network_sent_mb:.2f} MB")
        print(f"  Received: {health.network_recv_mb:.2f} MB")
        print("="*60 + "\n")

    def print_service_check(self, check: ServiceCheck):
        """Print a formatted service check result"""
        status_icon = {
            "UP": "✅",
            "OPEN": "✅",
            "DOWN": "❌",
            "CLOSED": "❌",
            "TIMEOUT": "⏱️",
            "WARNING": "⚠️",
            "ERROR": "❌"
        }.get(check.status, "❓")

        port_info = f":{check.port}" if check.port else ""
        print(f"{status_icon} [{check.service_name}] {check.host}{port_info} - {check.status} ({check.response_time_ms}ms) - {check.message}")


def main():
    parser = argparse.ArgumentParser(
        description='Server & Network Monitoring Tool',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s --health                           # Show server health
  %(prog)s --ping 8.8.8.8                     # Ping Google DNS
  %(prog)s --check-port 192.168.1.1:22       # Check SSH port
  %(prog)s --check-http https://google.com   # Check website
  %(prog)s --monitor --interval 60           # Continuous monitoring
        """
    )

    parser.add_argument('--health', action='store_true',
                       help='Display server health metrics')
    parser.add_argument('--ping', type=str, metavar='HOST',
                       help='Ping a host')
    parser.add_argument('--check-port', type=str, metavar='HOST:PORT',
                       help='Check if a port is open (format: host:port)')
    parser.add_argument('--check-http', type=str, metavar='URL',
                       help='Check HTTP/HTTPS service')
    parser.add_argument('--monitor', action='store_true',
                       help='Continuous monitoring mode')
    parser.add_argument('--interval', type=int, default=60,
                       help='Monitoring interval in seconds (default: 60)')
    parser.add_argument('--cpu-threshold', type=float, default=80.0,
                       help='CPU usage threshold percentage (default: 80)')
    parser.add_argument('--memory-threshold', type=float, default=85.0,
                       help='Memory usage threshold percentage (default: 85)')
    parser.add_argument('--disk-threshold', type=float, default=90.0,
                       help='Disk usage threshold percentage (default: 90)')
    parser.add_argument('--log-file', type=str, default='server_monitor.log',
                       help='Log file path (default: server_monitor.log)')
    parser.add_argument('--json', action='store_true',
                       help='Output in JSON format')

    args = parser.parse_args()

    monitor = ServerMonitor(log_file=args.log_file)

    # If no arguments, show health by default
    if not any([args.health, args.ping, args.check_port, args.check_http, args.monitor]):
        args.health = True

    try:
        if args.monitor:
            print(f"🔄 Starting continuous monitoring (interval: {args.interval}s)")
            print("Press Ctrl+C to stop\n")

            while True:
                health = monitor.get_server_health()

                if args.json:
                    print(json.dumps(asdict(health), indent=2))
                else:
                    monitor.print_health_report(health)

                    # Check thresholds
                    alerts = monitor.check_thresholds(
                        health,
                        cpu_threshold=args.cpu_threshold,
                        memory_threshold=args.memory_threshold,
                        disk_threshold=args.disk_threshold
                    )

                    if alerts:
                        print("🚨 ALERTS:")
                        for alert in alerts:
                            print(f"  {alert}")
                            monitor.logger.warning(alert)

                time.sleep(args.interval)

        if args.health:
            health = monitor.get_server_health()

            if args.json:
                print(json.dumps(asdict(health), indent=2))
            else:
                monitor.print_health_report(health)

                # Check thresholds
                alerts = monitor.check_thresholds(
                    health,
                    cpu_threshold=args.cpu_threshold,
                    memory_threshold=args.memory_threshold,
                    disk_threshold=args.disk_threshold
                )

                if alerts:
                    print("🚨 ALERTS:")
                    for alert in alerts:
                        print(f"  {alert}")

        if args.ping:
            check = monitor.ping_host(args.ping)
            if args.json:
                print(json.dumps(asdict(check), indent=2))
            else:
                monitor.print_service_check(check)

        if args.check_port:
            try:
                host, port = args.check_port.rsplit(':', 1)
                port = int(port)
                check = monitor.check_port(host, port)
                if args.json:
                    print(json.dumps(asdict(check), indent=2))
                else:
                    monitor.print_service_check(check)
            except ValueError:
                print("❌ Error: Invalid format. Use HOST:PORT (e.g., 192.168.1.1:22)")

        if args.check_http:
            check = monitor.check_http_service(args.check_http)
            if args.json:
                print(json.dumps(asdict(check), indent=2))
            else:
                monitor.print_service_check(check)

    except KeyboardInterrupt:
        print("\n\n👋 Monitoring stopped by user")
    except Exception as e:
        print(f"\n❌ Error: {str(e)}")
        monitor.logger.error(f"Error: {str(e)}")


if __name__ == "__main__":
    main()
