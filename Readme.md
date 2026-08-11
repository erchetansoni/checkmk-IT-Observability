# Checkmk Monitoring Stack

A Docker Compose stack that runs [Checkmk](https://checkmk.com/) (Raw Edition) for infrastructure monitoring, fronted by [Caddy](https://caddyserver.com/) as a reverse proxy for automatic HTTPS.

## Architecture

```
                 ┌────────────────────┐
  HTTPS (443) ─▶ │       Caddy        │──▶ checkmk:5000  (Web UI)
  HTTP  (80)  ─▶ │  (reverse proxy)   │
                 └────────────────────┘

  Agents ───────────────────▶ checkmk:8000     (Agent Receiver)
  SNMP traps ───────────────▶ checkmk:162/udp  (SNMP Trap receiver)
  Syslog ───────────────────▶ checkmk:514/udp  (Syslog receiver)
```

Caddy only proxies the web UI (HTTP/HTTPS). The Agent Receiver, SNMP trap, and Syslog ports are published directly on the host, since they're not HTTP services.

## Prerequisites

- Docker Engine and the Docker Compose plugin
- A DNS record pointing your domain (e.g. `OT-Infra.avgol.com`) at this host
- Inbound firewall access to ports `80`, `443`, `8000/tcp`, `162/udp`, and `514/udp` as needed

## Quick Start

1. Clone this repo and `cd` into it.
2. Edit the `Caddyfile` and replace `OT-Infra.avgol.com` with your own domain.
3. Edit `docker-compose.yaml` and change `CMK_PASSWORD` to something other than the default.
4. Start the stack:
   ```bash
   docker compose up -d
   ```
5. Watch the logs until Checkmk finishes initializing (first boot can take a couple of minutes):
   ```bash
   docker compose logs -f checkmk
   ```
6. Open `https://<your-domain>/monitoring/` and log in with:
   - **User:** `cmkadmin`
   - **Password:** whatever you set in `CMK_PASSWORD`

> Checkmk serves its UI under a site path (`/monitoring/` by default, matching `CMK_SITE_ID`), not the bare domain root.

## Configuration

| Environment Variable | Purpose |
|---|---|
| `TZ` | Container timezone |
| `CMK_PASSWORD` | Initial `cmkadmin` password — **change this** |
| `CMK_SITE_ID` | Name of the Checkmk monitoring site |
| `MAIL_RELAY_HOST` | Optional, **unauthenticated** SMTP smarthost for outbound mail (commented out by default). Not usable with providers that require authentication, such as Office 365. |

### Email notifications with authenticated SMTP (e.g. Office 365)

There is no environment variable for authenticated mail relay in this image. Instead, configure it directly in the Checkmk Web UI, where the HTML Email notification method supports a smarthost with authentication and STARTTLS:

`Setup > Events > Notifications > Parameters for notification methods > HTML Email`

Enter the smarthost (`smtp.office365.com`, port `587`, STARTTLS), enable authentication, and provide the sending mailbox's credentials. Note that Microsoft disables SMTP AUTH on mailboxes by default — it must be explicitly enabled for the sending account in the Microsoft 365 admin center (`Users > Active users > <account> > Mail > Manage email apps > Authenticated SMTP`) before this will work.

## Ports

| Port | Protocol | Purpose | Exposed via |
|---|---|---|---|
| 443 | TCP | Web UI (HTTPS) | Caddy |
| 80 | TCP | Web UI (HTTP → redirected) | Caddy |
| 8000 | TCP | Agent Receiver | Direct host port |
| 162 | UDP | SNMP Trap receiver | Direct host port |
| 514 | UDP | Syslog receiver | Direct host port |

The Checkmk server also initiates *outbound* connections to agents on TCP `6556` — it does not listen on that port itself.

## Security Notes

- Change `CMK_PASSWORD` before deploying to anything reachable beyond your own machine.
- Caddy issues a self-signed certificate (`tls internal`). For a publicly trusted certificate, remove the `tls internal` directive and let Caddy use ACME (Let's Encrypt) automatically, provided your domain is publicly resolvable and ports 80/443 are reachable from the internet.
- Restrict inbound access to `8000/tcp`, `162/udp`, and `514/udp` to only the networks your agents/devices live on.

## Wildcard TLS Certificate (`*.avgol.com`) & Multi-Project Sharing

This project uses Caddy's internal PKI engine (`tls internal`) to issue a **wildcard certificate (`*.avgol.com`)**. By trusting Caddy's Root Certificate Authority (CA) **once** on your machine, Chrome and Edge will automatically trust all current and future subdomains (`OT-Monitoring.avgol.com`, `app2.avgol.com`, etc.) across all your projects.

---

### Step 1: First-Time Certificate Generation
When you first spin up the stack with `docker compose up -d`, Caddy automatically generates the Root CA files and wildcard certificates inside the bind-mounted host folder `./caddy_cert/`.

Structure generated in `./caddy_cert/`:
```text
caddy_cert/
└── caddy/
    ├── pki/
    │   └── authorities/
    │       └── local/
    │           ├── root.crt          <-- MAIN FILE: Root CA Certificate
    │           ├── root.key          <-- MAIN FILE: Root CA Private Key
    │           ├── intermediate.crt
    │           └── intermediate.key
    └── certificates/
        └── local/
            └── wildcard_.avgol.com/  <-- Wildcard certificate files
```

---

### Step 2: Copy to a Central Shared Location (Optional & Recommended)
To use the same Root CA across multiple independent projects on your machine, copy the generated `caddy_cert` directory to a central location:

* **Windows:** `C:\caddy_cert\`
* **Linux / macOS:** `~/caddy_cert/`

```powershell
# Windows PowerShell Example:
Copy-Item -Recurse -Force .\caddy_cert\ C:\caddy_cert\
```

---

### Step 3: Installing the Root Certificate (`root.crt`)

You must import **`root.crt`** into your operating system's Trusted Store so browsers recognize all `*.avgol.com` domains.

* **File to install:** `root.crt`
* **File Location:** `C:\caddy_cert\caddy\pki\authorities\local\root.crt` (or `./caddy_cert/caddy/pki/authorities/local/root.crt`)

#### Installation Steps for Windows:
1. Open File Explorer and navigate to `C:\caddy_cert\caddy\pki\authorities\local\`.
2. **Double-click `root.crt`** (or right-click $\rightarrow$ **Install Certificate**).
3. Select **Local Machine** (or Current User) and click **Next**.
4. Select **"Place all certificates in the following store"**.
5. Click **Browse...** $\rightarrow$ Select **"Trusted Root Certification Authorities"** *(Crucial)* $\rightarrow$ Click **OK**.
6. Click **Next** $\rightarrow$ **Finish** $\rightarrow$ Confirm the security prompt.
7. Fully restart Google Chrome or Edge (`chrome://restart`).

---

### Step 4: Using the Shared Certificate in Other Projects

To share the exact same Certificate Authority in another project's `docker-compose.yaml`, mount the central `caddy_cert` directory to `/data`:

#### In `docker-compose.yaml` (Other Project):
```yaml
services:
  caddy:
    image: caddy:latest
    container_name: caddy
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      # Option A: Mount central Windows path
      - C:/caddy_cert:/data
      # Option B: Mount central Linux/Mac path
      # - ~/caddy_cert:/data
      - caddy_config:/config

volumes:
  caddy_config:
```

#### In `Caddyfile` (Routing Subdomains):
```caddyfile
*.avgol.com {
    tls internal

    @ot_monitoring host OT-Monitoring.avgol.com
    handle @ot_monitoring {
        reverse_proxy checkmk:5000
    }

    @app2 host app2.avgol.com
    handle @app2 {
        reverse_proxy app2_container:8080
    }

    handle {
        respond "Service not configured" 404
    }
}
```

---

## Data Persistence

Checkmk site data is stored in a named Docker volume (`checkmk_data`), while Caddy's certificates and root CA keys are stored in host bind-mount `./caddy_cert/` so they survive container recreation. Caddy runtime state uses named volume `caddy_config`.

## Third-Party Notices

This repository contains only original orchestration/configuration files (`docker-compose.yaml`, `Caddyfile`, documentation) — no third-party source code is included or redistributed here. At runtime, Docker Compose pulls the following pre-built, publicly published images:

| Component | License | Source |
|---|---|---|
| [Checkmk Raw / Community Edition](https://github.com/Checkmk/checkmk) | GPL-2.0 | [checkmk/check-mk-raw](https://hub.docker.com/r/checkmk/check-mk-raw) on Docker Hub |
| [Caddy](https://github.com/caddyserver/caddy) | Apache-2.0 | [caddy](https://hub.docker.com/_/caddy) on Docker Hub |

Using these images to deploy the stack does not modify or redistribute their source code, so it does not trigger GPL-2.0's copyleft obligations for this repository's own files. If you fork, modify, or redistribute Checkmk's own source code, those obligations apply to you independently of this project's license — see the [Checkmk license](https://github.com/Checkmk/checkmk?tab=GPL-2.0-1-ov-file) for details.

## License

Licensed under the [MIT License](LICENSE) — this covers the original files in this repository (compose file, Caddyfile, documentation). It does not apply to Checkmk or Caddy themselves; see [Third-Party Notices](#third-party-notices) above.

---

❤️ [Securing systems. Solving problems. Building the future. — Chetan Soni](https://erchetansoni.github.io/)
