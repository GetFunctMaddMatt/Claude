#!/usr/bin/env python3
"""
Network Scanner Tool
Scan network ranges for active hosts and open ports
"""

import socket
import subprocess
import ipaddress
import concurrent.futures
import time
from typing import List, Tuple, Dict
from dataclasses import dataclass
import argparse


@dataclass
class HostScan:
    """Represents a scanned host"""
    ip: str
    hostname: str
    status: str
    response_time_ms: float
    open_ports: List[int]


class NetworkScanner:
    """Network scanning functionality"""

    COMMON_PORTS = {
        20: "FTP-DATA",
        21: "FTP",
        22: "SSH",
        23: "Telnet",
        25: "SMTP",
        53: "DNS",
        80: "HTTP",
        110: "POP3",
        143: "IMAP",
        443: "HTTPS",
        445: "SMB",
        3306: "MySQL",
        3389: "RDP",
        5432: "PostgreSQL",
        5900: "VNC",
        6379: "Redis",
        8080: "HTTP-Alt",
        8443: "HTTPS-Alt",
        27017: "MongoDB"
    }

    def __init__(self, timeout: int = 1, max_workers: int = 50):
        self.timeout = timeout
        self.max_workers = max_workers

    def ping_host(self, ip: str) -> Tuple[str, bool, float]:
        """Ping a single host"""
        start_time = time.time()

        try:
            param = '-n' if socket.gethostname().startswith('WIN') else '-c'
            command = ['ping', param, '1', '-W', str(self.timeout), ip]

            result = subprocess.run(
                command,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=self.timeout + 1
            )

            response_time = (time.time() - start_time) * 1000
            return (ip, result.returncode == 0, response_time)

        except Exception:
            return (ip, False, 0)

    def get_hostname(self, ip: str) -> str:
        """Get hostname for an IP address"""
        try:
            hostname = socket.gethostbyaddr(ip)[0]
            return hostname
        except Exception:
            return "N/A"

    def scan_port(self, ip: str, port: int) -> Tuple[int, bool]:
        """Scan a single port on a host"""
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(self.timeout)
            result = sock.connect_ex((ip, port))
            sock.close()
            return (port, result == 0)
        except Exception:
            return (port, False)

    def scan_host_ports(self, ip: str, ports: List[int]) -> List[int]:
        """Scan multiple ports on a single host"""
        open_ports = []

        with concurrent.futures.ThreadPoolExecutor(max_workers=min(50, len(ports))) as executor:
            future_to_port = {executor.submit(self.scan_port, ip, port): port for port in ports}

            for future in concurrent.futures.as_completed(future_to_port):
                port, is_open = future.result()
                if is_open:
                    open_ports.append(port)

        return sorted(open_ports)

    def scan_network(self, network: str, port_scan: bool = False,
                     ports: List[int] = None) -> List[HostScan]:
        """Scan a network range for active hosts"""

        try:
            net = ipaddress.ip_network(network, strict=False)
        except ValueError as e:
            print(f"❌ Invalid network address: {e}")
            return []

        hosts = list(net.hosts()) if net.num_addresses > 2 else [net.network_address]
        total_hosts = len(hosts)

        print(f"🔍 Scanning {total_hosts} hosts in {network}...")

        active_hosts = []

        # Ping scan
        with concurrent.futures.ThreadPoolExecutor(max_workers=self.max_workers) as executor:
            future_to_ip = {executor.submit(self.ping_host, str(ip)): str(ip) for ip in hosts}

            completed = 0
            for future in concurrent.futures.as_completed(future_to_ip):
                ip, is_up, response_time = future.result()
                completed += 1

                if completed % 10 == 0 or completed == total_hosts:
                    print(f"  Progress: {completed}/{total_hosts} hosts scanned", end='\r')

                if is_up:
                    hostname = self.get_hostname(ip)
                    open_ports = []

                    if port_scan and ports:
                        print(f"\n  🔎 Scanning ports on {ip}...")
                        open_ports = self.scan_host_ports(ip, ports)

                    host_scan = HostScan(
                        ip=ip,
                        hostname=hostname,
                        status="UP",
                        response_time_ms=round(response_time, 2),
                        open_ports=open_ports
                    )
                    active_hosts.append(host_scan)

        print(f"\n✅ Scan complete! Found {len(active_hosts)} active hosts")
        return active_hosts

    def print_results(self, hosts: List[HostScan]):
        """Print scan results in a formatted table"""
        if not hosts:
            print("No active hosts found")
            return

        print("\n" + "="*80)
        print("ACTIVE HOSTS")
        print("="*80)

        for host in hosts:
            hostname_str = f"({host.hostname})" if host.hostname != "N/A" else ""
            print(f"\n✅ {host.ip} {hostname_str}")
            print(f"   Response time: {host.response_time_ms}ms")

            if host.open_ports:
                print(f"   Open ports:")
                for port in host.open_ports:
                    service = self.COMMON_PORTS.get(port, "Unknown")
                    print(f"     - {port}/tcp ({service})")

        print("\n" + "="*80)
        print(f"Total active hosts: {len(hosts)}")
        print("="*80 + "\n")


def parse_port_range(port_string: str) -> List[int]:
    """Parse port specification (e.g., '22,80,443' or '20-25')"""
    ports = []

    for part in port_string.split(','):
        if '-' in part:
            start, end = part.split('-')
            ports.extend(range(int(start), int(end) + 1))
        else:
            ports.append(int(part))

    return sorted(set(ports))


def main():
    parser = argparse.ArgumentParser(
        description='Network Scanner Tool',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s 192.168.1.0/24                    # Scan network for active hosts
  %(prog)s 192.168.1.0/24 -p 22,80,443      # Scan with specific ports
  %(prog)s 192.168.1.0/24 -p 1-1000         # Scan port range
  %(prog)s 192.168.1.0/24 --common-ports    # Scan common service ports
  %(prog)s 10.0.0.1                          # Scan single host
        """
    )

    parser.add_argument('network', type=str,
                       help='Network to scan (CIDR notation, e.g., 192.168.1.0/24)')
    parser.add_argument('-p', '--ports', type=str,
                       help='Ports to scan (e.g., 22,80,443 or 1-1000)')
    parser.add_argument('--common-ports', action='store_true',
                       help='Scan common service ports')
    parser.add_argument('--timeout', type=int, default=1,
                       help='Timeout in seconds (default: 1)')
    parser.add_argument('--workers', type=int, default=50,
                       help='Max concurrent workers (default: 50)')

    args = parser.parse_args()

    scanner = NetworkScanner(timeout=args.timeout, max_workers=args.workers)

    port_scan = False
    ports = []

    if args.ports:
        port_scan = True
        ports = parse_port_range(args.ports)
    elif args.common_ports:
        port_scan = True
        ports = sorted(NetworkScanner.COMMON_PORTS.keys())

    start_time = time.time()
    results = scanner.scan_network(args.network, port_scan=port_scan, ports=ports)
    elapsed_time = time.time() - start_time

    scanner.print_results(results)
    print(f"⏱️  Scan completed in {elapsed_time:.2f} seconds\n")


if __name__ == "__main__":
    main()
