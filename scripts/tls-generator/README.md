# Custom TLS Certificate Generator & Client Trust Manager

A standalone solution for generating private Root Certificate Authorities (CA) and long-lived Wildcard TLS certificates (e.g. 5–10 years) without relying on Caddy, Traefik ACME, or external internet connections.

---

## Directory Structure

```text
scripts/tls-generator/
├── README.md
├── server/
│   ├── generate-certs.sh       # Bash script for Linux Server
│   └── generate-certs.ps1      # PowerShell script for Windows Server
├── client/
│   ├── install-ca-linux.sh     # Bash script to trust Root CA on Linux PCs
│   ├── install-ca-windows.ps1   # PowerShell script to trust Root CA on Windows PCs
│   ├── uninstall-ca-linux.sh   # Bash script to remove Root CA from Linux PCs
│   ├── uninstall-ca-windows.ps1 # PowerShell script to remove Root CA from Windows PCs
│   └── rootCA.crt              # (Auto-copied here by server script)
└── ca-store/                   # (Created on first run: stores private Root CA key & cert)
    ├── rootCA.key
    └── rootCA.crt
```

---

## 1. Server-Side: Generate Certificates

All variables (Domain, SANs, Country, Organization, Validity Days) are configured at the top of the generator scripts.

### On Linux Server
```bash
cd scripts/tls-generator/server
chmod +x generate-certs.sh
./generate-certs.sh
```

### On Windows Server (PowerShell)
```powershell
cd .\scripts\tls-generator\server
.\generate-certs.ps1
```

### What happens:
1. Generates an internal **Root CA** valid for **10 Years (3650 days)** (stored in `ca-store/`).
2. Generates a **Wildcard Server Certificate** (`*.avgol.com`) valid for **5 Years (1825 days)**.
3. Outputs the server certificate & private key into `output/`:
   - `output/wildcard_.avgol.com.crt`
   - `output/wildcard_.avgol.com.key`
   *(You can copy/paste these files wherever you need them, e.g. into `traefik/certs/`)*
4. Automatically copies `rootCA.crt` to the `client/` folder for distribution.

---

## 2. Client-Side: Install Root CA on PCs

To eliminate browser security warnings and enable green lock 🔒 on client workstations:

### On Windows Clients
1. Copy `scripts/tls-generator/client/` to the Windows machine.
2. Open PowerShell as **Administrator**.
3. Run:
   ```powershell
   cd .\scripts\tls-generator\client
   .\install-ca-windows.ps1
   ```
4. Restart Chrome or Edge.

### On Linux Clients
1. Copy `scripts/tls-generator/client/` to the Linux machine.
2. Run with `sudo`:
   ```bash
   cd scripts/tls-generator/client
   chmod +x install-ca-linux.sh
   sudo ./install-ca-linux.sh
   ```

---

## 3. Client-Side: Remove / Uninstall Root CA (After Testing)

If you need to clean up and remove the Root CA from test PCs:

* **Windows:** Open PowerShell as Administrator and run `.\uninstall-ca-windows.ps1`
* **Linux:** Run `sudo ./uninstall-ca-linux.sh`

---

## Variables & Concepts Explained

### 1. Root CA vs. Server Certificate Validity

| Variable | Default Value | Purpose |
|---|---|---|
| **`CA_VALIDITY_DAYS`** | **`3650`** (10 Years) | **Root Certificate Authority (Root CA)**<br>This is the master authority (`rootCA.crt`) installed on client workstations. A 10-year validity means **you only install it once on client PCs and do not need to touch those PCs for a decade**. |
| **`CERT_VALIDITY_DAYS`** | **`1825`** (5 Years) | **Server / Web TLS Certificate (`*.avgol.com`)**<br>This is the leaf certificate used by Traefik/Checkmk for HTTPS. It is signed by your Root CA. When it expires after 5 years, you simply re-run the generator script to issue a new certificate for the server. *Client PCs do not need any updates.* |

---

### 2. SAN Domains vs. SAN IPs

**SAN** stands for **Subject Alternative Name**.

* **`SAN_DOMAINS`**: Lists all valid domain names/subdomains (e.g. `*.avgol.com`, `in-ot-monitoring.avgol.com`). When a user navigates to `https://in-ot-monitoring.avgol.com`, the browser validates the domain against this list to display the secure green lock 🔒.
* **`SAN_IPS` (Commented Out by Default)**:
  - Binding TLS certificates to raw IP addresses is **discouraged** in enterprise OT/IT environments.
  - **Why?**
    1. **SNI (Server Name Indication)**: Modern reverse proxies like Traefik rely on domain names (HTTP `Host` headers) to route traffic to the correct container.
    2. **Network Flexibility**: Server IP addresses can change during migrations or subnet changes; domain names remain stable.
    3. **Corporate Standard**: Industry best practice dictates that internal users and automated agents always communicate via fully qualified domain names (FQDNs) rather than raw IP addresses.

---

## Variables Customization

To customize parameters, edit the top section of [`generate-certs.sh`](file:///c:/Projects/Companies/Avgol/OT-Monitoring/scripts/tls-generator/server/generate-certs.sh) or [`generate-certs.ps1`](file:///c:/Projects/Companies/Avgol/OT-Monitoring/scripts/tls-generator/server/generate-certs.ps1):

```bash
DOMAIN="*.avgol.com"
PRIMARY_CN="*.avgol.com"

# SAN Domains to include in the certificate
SAN_DOMAINS=(
    "*.avgol.com"
    "in-ot-monitoring.avgol.com"
    "in-ot-proxy.avgol.com"
    "in-ot-agent.avgol.com"
    "in-ot-snmp.avgol.com"
    "in-ot-syslog.avgol.com"
    "localhost"
)

CA_VALIDITY_DAYS=3650     # 10 Years
CERT_VALIDITY_DAYS=1825   # 5 Years
COUNTRY="IN"
STATE="Gujarat"
LOCALITY="Surat"
ORGANIZATION="Avgol Nonwovens"
ORGANIZATIONAL_UNIT="OT-Monitoring"
CA_COMMON_NAME="Avgol Internal Root CA"
```
