#!/usr/bin/env python3
from __future__ import annotations

from datetime import datetime, timedelta, timezone
from pathlib import Path

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.x509.oid import ExtendedKeyUsageOID, NameOID


DOMAIN = "*.avgol.com"
ROOT_CERT = Path("caddy_cert/caddy/pki/authorities/local/root.crt")
ROOT_KEY = Path("caddy_cert/caddy/pki/authorities/local/root.key")
OUT_DIR = Path("traefik/certs")
OUT_CERT = OUT_DIR / "wildcard_.avgol.com.crt"
OUT_KEY = OUT_DIR / "wildcard_.avgol.com.key"


def main() -> None:
    if not ROOT_CERT.is_file() or not ROOT_KEY.is_file():
        raise SystemExit(
            "Missing Caddy local CA root files. Expected "
            f"{ROOT_CERT} and {ROOT_KEY}."
        )

    issuer_cert = x509.load_pem_x509_certificate(ROOT_CERT.read_bytes())
    issuer_key = serialization.load_pem_private_key(ROOT_KEY.read_bytes(), None)
    leaf_key = ec.generate_private_key(ec.SECP256R1())

    now = datetime.now(timezone.utc)
    subject = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, DOMAIN)])
    cert = (
        x509.CertificateBuilder()
        .subject_name(subject)
        .issuer_name(issuer_cert.subject)
        .public_key(leaf_key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(now - timedelta(minutes=5))
        .not_valid_after(now + timedelta(days=90))
        .add_extension(
            x509.SubjectAlternativeName([x509.DNSName(DOMAIN)]),
            critical=False,
        )
        .add_extension(x509.BasicConstraints(ca=False, path_length=None), critical=True)
        .add_extension(
            x509.KeyUsage(
                digital_signature=True,
                content_commitment=False,
                key_encipherment=True,
                data_encipherment=False,
                key_agreement=False,
                key_cert_sign=False,
                crl_sign=False,
                encipher_only=False,
                decipher_only=False,
            ),
            critical=True,
        )
        .add_extension(
            x509.ExtendedKeyUsage([ExtendedKeyUsageOID.SERVER_AUTH]),
            critical=False,
        )
        .sign(private_key=issuer_key, algorithm=hashes.SHA256())
    )

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    OUT_CERT.write_bytes(cert.public_bytes(serialization.Encoding.PEM))
    OUT_KEY.write_bytes(
        leaf_key.private_bytes(
            serialization.Encoding.PEM,
            serialization.PrivateFormat.TraditionalOpenSSL,
            serialization.NoEncryption(),
        )
    )

    print(f"Wrote {OUT_CERT}")
    print(f"Wrote {OUT_KEY}")
    print(f"Valid from {cert.not_valid_before_utc} to {cert.not_valid_after_utc}")


if __name__ == "__main__":
    main()
