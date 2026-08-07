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
| `MAIL_RELAY_HOST` / `MAIL_RELAY_PORT` / `MAIL_RELAY_USERNAME` / `MAIL_RELAY_PASSWORD` / `MAIL_FROM` / `MAIL_TO` | Optional SMTP relay settings for notifications (commented out by default — no relay is defined in this stack) |

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

## Data Persistence

Checkmk site data, Caddy's certificates, and Caddy's config are stored in named Docker volumes (`checkmk_data`, `caddy_data`, `caddy_config`) so they survive container restarts and recreation.

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
