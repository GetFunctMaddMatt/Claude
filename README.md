# Server & Network Monitoring Tools

A comprehensive suite of Python-based monitoring and scanning tools designed for server and network engineers.

## 🚀 Features

### Server Monitor (`server_monitor.py`)
- **Real-time system health monitoring**
  - CPU, Memory, Disk usage
  - Network statistics
  - System uptime

- **Service availability checks**
  - ICMP ping tests
  - TCP port scanning
  - HTTP/HTTPS endpoint monitoring

- **Alerting system**
  - Configurable thresholds
  - Automated alerts when limits exceeded
  - Detailed logging

- **Flexible output**
  - Human-readable reports
  - JSON output for integration
  - Continuous monitoring mode

### Network Scanner (`network_scanner.py`)
- **Network discovery**
  - Scan entire subnets (CIDR notation)
  - Identify active hosts
  - Resolve hostnames

- **Port scanning**
  - Fast concurrent scanning
  - Common service port detection
  - Custom port ranges

- **Performance**
  - Multi-threaded scanning
  - Configurable timeout and workers
  - Progress tracking

## 📋 Requirements

```bash
# Install required Python packages
pip install psutil
```

Python 3.7+ required (uses dataclasses)

## 🔧 Installation

1. Clone this repository
2. Make scripts executable:
```bash
chmod +x server_monitor.py network_scanner.py
```

3. Optionally add to PATH for system-wide access

## 💻 Usage

### Server Monitor

**Basic health check:**
```bash
./server_monitor.py --health
```

**Continuous monitoring (every 60 seconds):**
```bash
./server_monitor.py --monitor --interval 60
```

**Custom thresholds:**
```bash
./server_monitor.py --monitor --cpu-threshold 70 --memory-threshold 80
```

**Check network connectivity:**
```bash
./server_monitor.py --ping 8.8.8.8
```

**Check if a service port is open:**
```bash
./server_monitor.py --check-port 192.168.1.1:22
./server_monitor.py --check-port example.com:443
```

**Check HTTP/HTTPS endpoint:**
```bash
./server_monitor.py --check-http https://google.com
```

**JSON output for automation:**
```bash
./server_monitor.py --health --json
```

### Network Scanner

**Scan a subnet:**
```bash
./network_scanner.py 192.168.1.0/24
```

**Scan with specific ports:**
```bash
./network_scanner.py 192.168.1.0/24 -p 22,80,443
```

**Scan port range:**
```bash
./network_scanner.py 192.168.1.0/24 -p 1-1000
```

**Scan common service ports:**
```bash
./network_scanner.py 192.168.1.0/24 --common-ports
```

**Scan single host:**
```bash
./network_scanner.py 192.168.1.100
```

**Adjust performance:**
```bash
./network_scanner.py 192.168.1.0/24 --timeout 2 --workers 100
```

## 📊 Example Output

### Server Health Report
```
============================================================
📊 SERVER HEALTH REPORT - myserver
============================================================
Timestamp: 2026-01-09T19:00:00
Uptime: 72.50 hours

💻 SYSTEM RESOURCES:
  CPU Usage:    15.2%
  Memory Usage: 45.8% (3.66GB / 8.00GB)
  Disk Usage:   62.3% (124.60GB / 200.00GB)

🌐 NETWORK:
  Sent:     1234.56 MB
  Received: 5678.90 MB
============================================================
```

### Network Scan Results
```
================================================================================
ACTIVE HOSTS
================================================================================

✅ 192.168.1.1 (router.local)
   Response time: 2.34ms
   Open ports:
     - 22/tcp (SSH)
     - 80/tcp (HTTP)
     - 443/tcp (HTTPS)

✅ 192.168.1.100 (server.local)
   Response time: 1.23ms
   Open ports:
     - 22/tcp (SSH)
     - 3306/tcp (MySQL)
     - 8080/tcp (HTTP-Alt)

================================================================================
Total active hosts: 2
================================================================================
```

## 🎯 Use Cases

### For Server Engineers:
- Monitor production server health 24/7
- Set up automated alerts for resource issues
- Track system performance over time
- Validate service availability after deployments

### For Network Engineers:
- Quickly discover all active devices on a network
- Identify unauthorized services or open ports
- Map network topology
- Troubleshoot connectivity issues
- Verify firewall rules

### For DevOps/SRE:
- Integration with monitoring systems (JSON output)
- Automated health checks in CI/CD pipelines
- Infrastructure validation
- Incident response and diagnostics

## 📝 Configuration

Copy `config.example.json` to `config.json` and customize:
- Add your servers and services
- Set custom thresholds
- Configure alert methods
- Adjust scanning parameters

## 🔐 Security Notes

- **Permission requirements**: Network scanning may require elevated privileges
- **Use responsibly**: Only scan networks you own or have permission to scan
- **Firewall awareness**: Some scans may trigger IDS/IPS alerts
- **Rate limiting**: Adjust workers and timeout to avoid network congestion

## 📈 Advanced Features

### Logging
All monitoring activities are logged to `server_monitor.log` by default:
```bash
./server_monitor.py --monitor --log-file /var/log/custom.log
```

### Automation with Cron
Monitor every hour:
```cron
0 * * * * /path/to/server_monitor.py --health --json >> /var/log/health.log
```

### Integration with Scripts
```bash
# Get JSON output and process with jq
./server_monitor.py --health --json | jq '.cpu_percent'

# Alert if CPU > 80%
CPU=$(./server_monitor.py --health --json | jq -r '.cpu_percent')
if (( $(echo "$CPU > 80" | bc -l) )); then
    echo "High CPU alert: $CPU%"
fi
```

## 🛠️ Troubleshooting

**Import errors:**
```bash
pip install --upgrade psutil
```

**Permission denied for ping:**
```bash
sudo ./server_monitor.py --ping 8.8.8.8
# or
sudo setcap cap_net_raw+ep /usr/bin/python3
```

**Slow network scans:**
- Increase workers: `--workers 100`
- Decrease timeout: `--timeout 0.5`
- Scan smaller subnets

## 📜 License

Free to use for personal and commercial purposes.

## 🤝 Contributing

Feel free to extend these tools with additional features:
- Email/SMS alerting
- Database logging
- Web dashboard
- Additional protocol checks (FTP, SMTP, etc.)
- Performance graphing

---

**Made for IT professionals who need reliable monitoring and scanning tools.**
