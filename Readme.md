# Checkmk Monitoring Stack

A Docker Compose stack that runs [Checkmk](https://checkmk.com/) Raw Edition for infrastructure monitoring, fronted by [Traefik](https://traefik.io/traefik/) `v3.7.10` as the HTTPS reverse proxy.

## Architecture

```text
                 +--------------------+
  HTTPS (443) -> |      Traefik       | -> checkmk:5000  (Web UI)
  HTTP  (80) ->  |  reverse proxy     |    HTTP redirects to HTTPS
  UI   (8080) -> |  (Dashboard/API)   |
                 +--------------------+

  Agents ---------------------> checkmk:8000     (Agent Receiver)
  SNMP traps -----------------> checkmk:162/udp  (SNMP Trap receiver)
  Syslog ---------------------> checkmk:514/udp  (Syslog receiver)
```

Traefik proxies the Checkmk web UI and serves its own Traefik Dashboard Web UI. The Agent Receiver, SNMP trap, and Syslog ports are published directly on the host because they are not HTTP services.

## Prerequisites

- Docker Engine and the Docker Compose plugin
- DNS or hosts-file records pointing the domains at this host:
  ```text
  IN-OT-Monitoring.avgol.com  127.0.0.1
  in-ot-proxy.avgol.com       127.0.0.1  (Traefik Web UI / Proxy)
  ```
- Inbound firewall access to ports `80`, `443`, `8080/tcp`, `8000/tcp`, `162/udp`, and `514/udp` as needed
- A trusted local root CA if you want the browser to trust local HTTPS

Host names are case-insensitive. The Traefik rule in `docker-compose.yaml` uses `in-ot-monitoring.avgol.com`, which matches `IN-OT-Monitoring.avgol.com`.

## Quick Start

1. Edit `docker-compose.yaml` and change `CMK_PASSWORD` to something other than the default.
2. Make sure the Traefik certificate files exist:
   ```powershell
   python .\scripts\generate-traefik-cert.py
   ```
3. Start the stack:
   ```bash
   docker compose up -d
   ```
4. Watch the logs until Checkmk finishes initializing. First boot can take a couple of minutes:
   ```bash
   docker compose logs -f checkmk traefik
   ```
5. Open `https://IN-OT-Monitoring.avgol.com/monitoring/` and log in with:
   - **User:** `cmkadmin`
   - **Password:** whatever you set in `CMK_PASSWORD`

> Checkmk serves its UI under a site path (`/monitoring/` by default, matching `CMK_SITE_ID`), not the bare domain root.

## Traefik Routing

Traefik discovers the Checkmk web UI from Docker labels on the `checkmk` service:

```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.ot-monitoring.rule=Host(`in-ot-monitoring.avgol.com`)"
  - "traefik.http.routers.ot-monitoring.entrypoints=websecure"
  - "traefik.http.routers.ot-monitoring.tls=true"
  - "traefik.http.services.ot-monitoring.loadbalancer.server.port=5000"
```

The `traefik` service has `exposedbydefault=false`, so only containers with `traefik.enable=true` are published.

## Configuration

| Environment Variable | Purpose |
|---|---|
| `TZ` | Container timezone |
| `CMK_PASSWORD` | Initial `cmkadmin` password; change this |
| `CMK_SITE_ID` | Name of the Checkmk monitoring site |
| `MAIL_RELAY_HOST` | Optional, unauthenticated SMTP smarthost for outbound mail. Commented out by default. Not usable with providers that require authentication, such as Office 365. |

### Email Notifications With Authenticated SMTP

There is no environment variable for authenticated mail relay in this image. Instead, configure it directly in the Checkmk Web UI, where the HTML Email notification method supports a smarthost with authentication and STARTTLS:

`Setup > Events > Notifications > Parameters for notification methods > HTML Email`

Enter the smarthost (`smtp.office365.com`, port `587`, STARTTLS), enable authentication, and provide the sending mailbox's credentials. Microsoft disables SMTP AUTH on mailboxes by default; it must be explicitly enabled for the sending account in the Microsoft 365 admin center before this will work.

## Ports

| Port | Protocol | Purpose | Exposed via |
|---|---|---|---|
| 443 | TCP | Checkmk Web UI (HTTPS) / Traefik UI | Traefik |
| 80 | TCP | HTTP redirect to HTTPS | Traefik |
| 8080 | TCP | Traefik Web UI / Dashboard | Traefik |
| 8000 | TCP | Agent Receiver | Direct host port |
| 162 | UDP | SNMP Trap receiver | Direct host port |
| 514 | UDP | Syslog receiver | Direct host port |

The Checkmk server also initiates outbound connections to agents on TCP `6556`; it does not listen on that port itself.

## Traefik Configuration

Traefik uses file-based static configuration in `traefik/traefik.yaml` mounted to `/etc/traefik/traefik.yaml`:

```yaml
global:
  checkNewVersion: false
  sendAnonymousUsage: false

log:
  level: INFO

api:
  dashboard: true
  insecure: true

entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
  websecure:
    address: ":443"
  traefik:
    address: ":8080"

providers:
  docker:
    exposedByDefault: false
  file:
    filename: /etc/traefik/dynamic/tls.yaml
    watch: true
```

The Traefik Dashboard Web UI can be accessed at:
- `http://in-ot-proxy.avgol.com:8080/dashboard/` (or `http://localhost:8080/dashboard/`)
- `https://in-ot-proxy.avgol.com/dashboard/` (via HTTPS TLS on port 443)

## Local TLS Certificate

Traefik uses the file provider config in `traefik/tls.yaml`:

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

The corresponding local certificate files live in `traefik/certs/`:

```text
traefik/certs/
├── wildcard_.avgol.com.crt
└── wildcard_.avgol.com.key
```

These files are local secrets and are ignored by git. The helper script generates a fresh `*.avgol.com` certificate signed by the existing local Caddy root CA:

```powershell
python .\scripts\generate-traefik-cert.py
```

The existing root CA certificate remains here:

```text
caddy_cert/caddy/pki/authorities/local/root.crt
```

If that root certificate is already trusted by Windows, Chrome and Edge should trust the Traefik certificate generated by the script. To install it for the first time:

1. Open `caddy_cert\caddy\pki\authorities\local\`.
2. Double-click `root.crt`, or right-click and choose **Install Certificate**.
3. Select **Local Machine** or **Current User**.
4. Select **Place all certificates in the following store**.
5. Choose **Trusted Root Certification Authorities**.
6. Finish the wizard and restart Chrome or Edge.

When testing with Windows `curl.exe`, local CA certificates can fail revocation checking even when the chain is otherwise trusted. Use `--ssl-no-revoke` for that local check:

```powershell
curl.exe --ssl-no-revoke https://IN-OT-Monitoring.avgol.com/monitoring/check_mk/login.py
```

## Offline Bundle

`bundle-and-transfer.sh` now copies:

- `docker-compose.yaml`
- `deploy-on-server.sh`
- `traefik/`

Before creating the bundle, make sure the images are available locally:

```bash
docker compose pull
```

The deployment script verifies these required bind-mounted files before starting Docker Compose:

- `traefik/traefik.yaml`
- `traefik/tls.yaml`
- `traefik/certs/wildcard_.avgol.com.crt`
- `traefik/certs/wildcard_.avgol.com.key`

## Data Persistence

Checkmk site data is stored in `./checkmk_data`. Backup files are stored in `./backup-files`. Traefik TLS material is stored in `./traefik/certs`.

## Security Notes

- Change `CMK_PASSWORD` before deploying to anything reachable beyond your own machine.
- Keep `traefik/certs/*.key` private.
- Restrict inbound access to `8000/tcp`, `162/udp`, and `514/udp` to only the networks your agents and devices live on.
- The Docker socket is mounted read-only into Traefik so it can discover labeled containers. Do not enable routing labels on containers you do not intend to expose.

## Third-Party Notices

This repository contains only original orchestration/configuration files; no third-party source code is included or redistributed here. At runtime, Docker Compose pulls the following pre-built, publicly published images:

| Component | License | Source |
|---|---|---|
| [Checkmk Raw / Community Edition](https://github.com/Checkmk/checkmk) | GPL-2.0 | [checkmk/check-mk-raw](https://hub.docker.com/r/checkmk/check-mk-raw) on Docker Hub |
| [Traefik](https://github.com/traefik/traefik) | MIT | [traefik](https://hub.docker.com/_/traefik) on Docker Hub |
| [Postfix relay image](https://hub.docker.com/r/boky/postfix) | See upstream image | [boky/postfix](https://hub.docker.com/r/boky/postfix) on Docker Hub |

Using these images to deploy the stack does not modify or redistribute their source code, so it does not trigger GPL-2.0's copyleft obligations for this repository's own files. If you fork, modify, or redistribute Checkmk's own source code, those obligations apply to you independently of this project's license.

## License

Licensed under the [MIT License](LICENSE) if one is added to this repository. This covers the original orchestration/configuration files. It does not apply to Checkmk, Traefik, or the Postfix relay image.

---

[Securing systems. Solving problems. Building the future. - Chetan Soni](https://erchetansoni.github.io/)
