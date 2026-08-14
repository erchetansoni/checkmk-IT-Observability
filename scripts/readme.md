# Wildcard TLS Certificate Generator

A Python script that generates a wildcard TLS certificate for `*.avgol.com`, signed by a local Caddy CA, for use with Traefik as a reverse proxy.

---

## Overview

```
Caddy local CA  ──signs──▶  *.avgol.com cert  ──used by──▶  Traefik
(root.crt/key)               (wildcard cert)                (serves HTTPS)
```

This is designed for a **local dev / homelab setup** where Caddy acts as a local Certificate Authority. Any machine that trusts Caddy's root CA will automatically trust the issued wildcard certificate served by Traefik.

---

## Prerequisites

- Python 3.x
- [`cryptography`](https://pypi.org/project/cryptography/) library

```bash
pip install cryptography
```

- Caddy's local CA root files must exist at:
  - `caddy_cert/caddy/pki/authorities/local/root.crt`
  - `caddy_cert/caddy/pki/authorities/local/root.key`

---

## Configuration

| Constant    | Value                                          | Description                        |
|-------------|------------------------------------------------|------------------------------------|
| `DOMAIN`    | `*.avgol.com`                                  | Wildcard domain for the certificate |
| `ROOT_CERT` | `caddy_cert/caddy/pki/authorities/local/root.crt` | Caddy CA certificate            |
| `ROOT_KEY`  | `caddy_cert/caddy/pki/authorities/local/root.key` | Caddy CA private key            |
| `OUT_CERT`  | `traefik/certs/wildcard_.avgol.com.crt`        | Output certificate path            |
| `OUT_KEY`   | `traefik/certs/wildcard_.avgol.com.key`        | Output private key path            |

---

## How It Works

### 1. Load the Caddy CA

```python
issuer_cert = x509.load_pem_x509_certificate(ROOT_CERT.read_bytes())
issuer_key  = serialization.load_pem_private_key(ROOT_KEY.read_bytes(), None)
```

Reads Caddy's root CA certificate and private key from disk. These are used to **sign** the new leaf certificate, making it trusted by any machine that already trusts Caddy's root.

---

### 2. Generate a New Leaf Key

```python
leaf_key = ec.generate_private_key(ec.SECP256R1())
```

Creates a fresh **ECDSA P-256 private key** for the new certificate — modern, fast, and broadly supported by all current TLS implementations.

---

### 3. Build the Certificate

```python
x509.CertificateBuilder()
    .subject_name(CN=*.avgol.com)
    .issuer_name(Caddy CA name)
    .public_key(leaf_key.public_key())
    .not_valid_before(now - 5 minutes)   # Backdated slightly for clock skew
    .not_valid_after(now + 90 days)
```

| Field              | Value              | Notes                                      |
|--------------------|--------------------|--------------------------------------------|
| Subject CN         | `*.avgol.com`      | Wildcard covers all subdomains             |
| Issuer             | Caddy local CA     | Links cert to the trusted root             |
| Valid From         | `now - 5 minutes`  | Small backdating to handle clock skew      |
| Valid Until        | `now + 90 days`    | Standard short-lived cert lifetime         |
| Serial Number      | Random             | Unique identifier for this certificate     |

---

### 4. Certificate Extensions

| Extension               | Value                          | Critical | Purpose                                              |
|-------------------------|--------------------------------|----------|------------------------------------------------------|
| `SubjectAlternativeName`| `DNS: *.avgol.com`             | No       | Specifies the domains this cert is valid for         |
| `BasicConstraints`      | `CA: False`                    | Yes      | Marks this as a leaf cert — cannot sign other certs  |
| `KeyUsage`              | `digitalSignature`, `keyEncipherment` | Yes | Restricts how the key may be used               |
| `ExtendedKeyUsage`      | `serverAuth`                   | No       | Marks it as a valid **TLS server certificate**       |

---

### 5. Sign and Write Output

```python
.sign(private_key=issuer_key, algorithm=hashes.SHA256())
```

The certificate is signed with Caddy's CA private key using **SHA-256**. Output files are written to `traefik/certs/`:

- `wildcard_.avgol.com.crt` — The signed certificate (PEM format)
- `wildcard_.avgol.com.key` — The private key (PEM, unencrypted, TraditionalOpenSSL format)

---

## Usage

```bash
python generate_cert.py
```

**Expected output:**

```
Wrote traefik/certs/wildcard_.avgol.com.crt
Wrote traefik/certs/wildcard_.avgol.com.key
Valid from 2025-01-01 09:55:00+00:00 to 2025-04-01 10:00:00+00:00
```

---

## Certificate Renewal

The generated certificate is valid for **90 days**. Since the local Caddy CA cannot auto-renew Traefik's certificate, you must **re-run this script manually** before expiry:

```bash
# Re-run every ~85 days to stay ahead of expiry
python generate_cert.py
```

Then reload Traefik to pick up the new certificate.

---

## Security Notes

- The private key is written **unencrypted** to disk — ensure `traefik/certs/` has appropriate file permissions.
- This setup is intended for **local/internal use only**. Do not use a local CA setup like this for public-facing production services.
- The `*.avgol.com` wildcard covers all first-level subdomains (e.g., `app.avgol.com`, `api.avgol.com`) but **not** the apex domain `avgol.com` itself.