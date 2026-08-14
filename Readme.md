# Checkmk Monitoring Stack

A Docker Compose stack that runs [Checkmk](https://checkmk.com/) Raw Edition for infrastructure monitoring, fronted by [Traefik](https://traefik.io/traefik/) `v3.7.10` as the reverse proxy for HTTP/HTTPS, TCP, and UDP traffic.

## Architecture

```text
                 +-------------------------------------------------------------+
                 |                           Traefik                           |
                 |                        Reverse Proxy                        |
                 +-------------------------------------------------------------+
  HTTPS (443)    |  Host(`in-ot-monitoring.avgol.com`) -> checkmk:5000 (Web UI)|
  HTTP  (80)     |  HTTP redirects automatically to HTTPS (443)                |
  UI    (8080)   |  Host(`in-ot-proxy.avgol.com`)      -> Traefik Dashboard   |
  TCP   (8000)   |  Agent Receiver                     -> checkmk:8000 (TCP)   |
  UDP   (162)    |  SNMP Trap Receiver                 -> checkmk:162  (UDP)   |
  UDP   (514)    |  Syslog Receiver                    -> checkmk:514  (UDP)   |
                 +-------------------------------------------------------------+
```

All incoming connections (Web UI, Agent Receiver, SNMP traps, and Syslog) pass through Traefik. Checkmk does not expose any ports directly to the host.

---

## Domain & DNS Configuration

### 1. Production DNS Setup (Enterprise Network)
In production, your corporate DNS server (e.g. Active Directory DNS, Infoblox, or BIND) must have **A Records** (or a wildcard DNS record) pointing to the **Traefik Server's IP address**:

| Hostname / Record | Type | Target IP | Purpose |
|---|---|---|---|
| `in-ot-monitoring.avgol.com` | `A` | `<SERVER_IP>` | Checkmk Web UI |
| `in-ot-proxy.avgol.com` | `A` | `<SERVER_IP>` | Traefik Proxy Dashboard |
| `in-ot-agent.avgol.com` | `A` | `<SERVER_IP>` | Checkmk Agent Receiver (TCP 8000) |
| `in-ot-snmp.avgol.com` | `A` | `<SERVER_IP>` | SNMP Trap Receiver (UDP 162) |
| `in-ot-syslog.avgol.com` | `A` | `<SERVER_IP>` | Syslog Receiver (UDP 514) |
| `*.avgol.com` *(Alternative)* | `A` | `<SERVER_IP>` | Wildcard DNS covering all subdomains |

### 2. Local Testing (Hosts File)
For local development or pre-production testing on your machine, add the following lines to your `hosts` file:
* **Windows:** `C:\Windows\System32\drivers\etc\hosts`
* **Linux/macOS:** `/etc/hosts`

```text
127.0.0.1  in-ot-monitoring.avgol.com
127.0.0.1  in-ot-proxy.avgol.com
127.0.0.1  in-ot-agent.avgol.com
127.0.0.1  in-ot-snmp.avgol.com
127.0.0.1  in-ot-syslog.avgol.com
```

---

## Ports Overview

All external ports are bound by the `traefik` container:

| Port | Protocol | Purpose | Layer | Handled by |
|---|---|---|---|---|
| **443** | TCP | Checkmk Web UI (HTTPS) / Traefik Dashboard | Layer 7 (HTTP/TLS) | Traefik Router (`websecure`) |
| **80** | TCP | HTTP redirect to HTTPS | Layer 7 (HTTP) | Traefik Entrypoint (`web`) |
| **8080** | TCP | Traefik Internal API / Dashboard | Layer 7 (HTTP) | Traefik Dashboard (`insecure`) |
| **8000** | TCP | Checkmk Agent Receiver | Layer 4 (TCP) | Traefik TCP Proxy (`agent-receiver`) |
| **162** | UDP | SNMP Trap Receiver | Layer 4 (UDP) | Traefik UDP Proxy (`snmp-trap`) |
| **514** | UDP | Syslog Receiver | Layer 4 (UDP) | Traefik UDP Proxy (`syslog`) |

> [!NOTE]
> The Checkmk server also initiates outbound connections to agents on TCP `6556`; it does not listen on that port itself.

---

## Directory Structure

```text
OT-Monitoring/
├── docker-compose.yaml                   # Container orchestration
├── deploy-on-server.sh                   # Deployment script for production host
├── bundle-and-transfer.sh                # Offline packaging and upload script
├── checkmk_data/                         # Checkmk persistent site data
├── backup-files/                         # Checkmk automated backups
└── traefik/
    ├── traefik.yaml                      # Traefik static configuration (Entrypoints & Providers)
    ├── certs/
    │   ├── wildcard_.avgol.com.crt       # Public SSL certificate (*.avgol.com)
    │   └── wildcard_.avgol.com.key       # Private key
    └── dynamic/                          # Dynamic configuration folder (Hot-reloaded)
        ├── tls.yaml                      # TLS certificates & Traefik Dashboard route
        └── in-ot-monitoring.avgol.com.yaml # Checkmk HTTP, TCP & UDP routing rules
```

---

## Quick Start

1. Edit `docker-compose.yaml` and set your desired `CMK_PASSWORD`.
2. Ensure the Traefik wildcard SSL certificates exist:
   ```powershell
   python .\scripts\generate-traefik-cert.py
   ```
3. Start the stack:
   ```bash
   docker compose up -d
   ```
4. Watch logs until Checkmk finishes initializing:
   ```bash
   docker compose logs -f checkmk traefik
   ```
5. Open `https://in-ot-monitoring.avgol.com/monitoring/` and log in:
   - **Username:** `cmkadmin`
   - **Password:** whatever was set in `CMK_PASSWORD` (default: `ChangeMe123!`)

---

## Registering Monitored Hosts (Agent Controller)

Checkmk 2.1+ uses TLS encryption between the Checkmk Agent on target hosts and the Checkmk Agent Receiver (`in-ot-agent.avgol.com` on port 8000).

After installing the Checkmk agent package on your target Windows or Linux server, register it with the monitoring server:

### Windows Agent Registration

Run Command Prompt(use the caret `^` for escaping special characters) or PowerShell(use the backtick `  for escaping special characters) as **Administrator**:

```bat
cd "C:\Program Files (x86)\checkmk\service"

cmk-agent-ctl.exe register ^
  --server in-ot-agent.avgol.com ^
  --site monitoring ^
  --user cmkadmin ^
  --password "ChangeMe123!" ^
  --hostname "IN-OT-HYPERV02"
```
or save it as .bat file, and then run it as Administrator.

### Linux Agent Registration

Run in terminal with `sudo`:

```bash
sudo cmk-agent-ctl register \
  --server "in-ot-agent.avgol.com" \
  --site "monitoring" \
  --user "cmkadmin" \
  --password "ChangeMe123!" \
  --hostname "IN-OT-Monitoring"
```

> [!TIP]
> When prompted to accept the server's certificate / fingerprint, confirm with `y` (yes). The connection will be established with mutual TLS authentication.

---

## Traefik Dynamic Configurations Explained

Traefik watches the `traefik/dynamic/` directory. Any change made to `.yaml` files in this folder is **instantly applied without restarting containers**.

### 1. Checkmk Routing (`traefik/dynamic/in-ot-monitoring.avgol.com.yaml`)
Handles Layer 7 HTTPS routing for the Web UI, Layer 4 TCP proxying for the Agent Receiver, and Layer 4 UDP proxying for SNMP/Syslog:

```yaml
# HTTP / HTTPS (Web UI)
http:
  routers:
    ot-monitoring:
      rule: Host(`in-ot-monitoring.avgol.com`)
      entryPoints:
        - websecure
      service: ot-monitoring-service
      tls: {}
  services:
    ot-monitoring-service:
      loadBalancer:
        servers:
          - url: "http://checkmk:5000"

# TCP (Agent Receiver)
tcp:
  routers:
    agent-receiver:
      rule: HostSNI(`*`)
      entryPoints:
        - agent-receiver
      service: agent-receiver-service
  services:
    agent-receiver-service:
      loadBalancer:
        servers:
          - address: "checkmk:8000"

# UDP (SNMP Traps & Syslog)
udp:
  routers:
    snmp-trap:
      entryPoints:
        - snmp-trap
      service: snmp-trap-service
    syslog:
      entryPoints:
        - syslog
      service: syslog-service
  services:
    snmp-trap-service:
      loadBalancer:
        servers:
          - address: "checkmk:162"
    syslog-service:
      loadBalancer:
        servers:
          - address: "checkmk:514"
```

### 2. TLS & Dashboard Routing (`traefik/dynamic/tls.yaml`)
Loads the wildcard `*.avgol.com` certificate and exposes the Traefik Dashboard over HTTPS:

```yaml
tls:
  certificates:
    - certFile: /certs/wildcard_.avgol.com.crt
      keyFile: /certs/wildcard_.avgol.com.key

http:
  routers:
    traefik-dashboard:
      rule: Host(`in-ot-proxy.avgol.com`)
      entryPoints:
        - websecure
      service: api@internal
      middlewares:
        - dashboard-redirect
      tls: {}

  middlewares:
    dashboard-redirect:
      redirectRegex:
        regex: "^https://in-ot-proxy\\.avgol\\.com/$"
        replacement: "https://in-ot-proxy.avgol.com/dashboard/"
        permanent: true
```

---

## Adding Future Services
To add another service or website in the future (e.g. Grafana, OPC-UA gateway, Node-RED):
1. Add the container to `docker-compose.yaml` (no port publishing needed if routing through Traefik).
2. Create a new `.yaml` file inside `traefik/dynamic/` (e.g. `traefik/dynamic/grafana.avgol.com.yaml`).
3. Define the router and service pointing to `http://<container_name>:<port>`.
4. Traefik immediately serves the new domain with zero downtime!

---

## Offline Deployment Bundle

To deploy to an isolated or air-gapped production host:

1. Pull images locally:
   ```bash
   docker compose pull
   ```
2. Run the bundle script:
   ```bash
   ./bundle-and-transfer.sh
   ```
3. Connect to the remote server and deploy:
   ```bash
   ssh chetan@<SERVER_IP>
   cd /home/chetan/OT-Monitoring
   ./deploy-on-server.sh
   ```

---

## Security Notes

- Change `CMK_PASSWORD` before deploying to production.
- Keep `traefik/certs/*.key` private.
- Restrict firewall access to ports `8000/tcp`, `162/udp`, and `514/udp` to only internal OT/monitoring networks.
- Traefik runs with `exposedByDefault: false` to ensure unconfigured containers are never exposed unintentionally.

---

[Securing systems. Solving problems. Building the future. - Chetan Soni](https://erchetansoni.github.io/)
