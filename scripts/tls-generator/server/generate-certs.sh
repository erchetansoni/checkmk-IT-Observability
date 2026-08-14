#!/usr/bin/env bash
set -Eeuo pipefail

################################################################################
# CERTIFICATE CONFIGURATION VARIABLES (EDIT AS NEEDED)
################################################################################

# Primary Wildcard Domain & Subject
DOMAIN="*.avgol.com"
PRIMARY_CN="*.avgol.com"

# Additional Subject Alternative Names (SANs)
SAN_DOMAINS=(
    "*.avgol.com"
    "in-ot-monitoring.avgol.com"
    "in-ot-proxy.avgol.com"
    "in-ot-agent.avgol.com"
    "in-ot-snmp.avgol.com"
    "in-ot-syslog.avgol.com"
    "localhost"
)

# Note: Binding TLS certificates to raw IP addresses is generally discouraged in enterprise
# environments because IPs can change (DHCP, network migration) and IP-based certificates
# bypass DNS governance and SNI routing. Always use proper FQDNs / domain names instead.
# If strictly needed in rare testing scenarios, you can uncomment the SAN_IPS below:
# SAN_IPS=(
#     "127.0.0.1"
# )

# Validity Periods
CA_VALIDITY_DAYS=3650     # 10 Years
CERT_VALIDITY_DAYS=1825   # 5 Years

# Certificate Subject Details
COUNTRY="IN"
STATE="Gujarat"
LOCALITY="Surat"
ORGANIZATION="Avgol Nonwovens"
ORGANIZATIONAL_UNIT="OT-Monitoring"
CA_COMMON_NAME="Avgol Internal Root CA"

# Output Locations
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CA_STORAGE_DIR="${SCRIPT_DIR}/../ca-store"
SERVER_CERTS_DIR="${SCRIPT_DIR}/../output"

################################################################################
# SCRIPT EXECUTION
################################################################################

echo "================================================================="
echo " Generating Custom Internal Root CA and Wildcard TLS Certificate"
echo "================================================================="

# Check for OpenSSL
command -v openssl >/dev/null 2>&1 || {
    echo "ERROR: 'openssl' command is not installed. Please install openssl."
    exit 1
}

# Create output directories
mkdir -p "${CA_STORAGE_DIR}"
mkdir -p "${SERVER_CERTS_DIR}"

CA_KEY="${CA_STORAGE_DIR}/rootCA.key"
CA_CERT="${CA_STORAGE_DIR}/rootCA.crt"
SERVER_KEY="${SERVER_CERTS_DIR}/wildcard_.avgol.com.key"
SERVER_CERT="${SERVER_CERTS_DIR}/wildcard_.avgol.com.crt"
TEMP_CSR="${CA_STORAGE_DIR}/wildcard.csr"
TEMP_EXT="${CA_STORAGE_DIR}/wildcard.ext"

# ------------------------------------------------------------------------------
# 1. Generate Root CA (if it does not already exist)
# ------------------------------------------------------------------------------
if [ -f "${CA_KEY}" ] && [ -f "${CA_CERT}" ]; then
    echo "✔ Existing Root CA found in ${CA_STORAGE_DIR}. Reusing existing CA."
else
    echo "Generating new Root CA Private Key & Certificate..."
    openssl genrsa -out "${CA_KEY}" 4096
    openssl req -x509 -new -nodes -key "${CA_KEY}" -sha256 -days "${CA_VALIDITY_DAYS}" \
        -out "${CA_CERT}" \
        -subj "/C=${COUNTRY}/ST=${STATE}/L=${LOCALITY}/O=${ORGANIZATION}/OU=${ORGANIZATIONAL_UNIT}/CN=${CA_COMMON_NAME}"
    echo "✔ Root CA created: ${CA_CERT}"
fi

# ------------------------------------------------------------------------------
# 2. Generate Server Private Key & Certificate Signing Request (CSR)
# ------------------------------------------------------------------------------
echo "Generating Server Private Key for ${DOMAIN}..."
openssl genrsa -out "${SERVER_KEY}" 2048

echo "Generating Certificate Signing Request (CSR)..."
openssl req -new -key "${SERVER_KEY}" -out "${TEMP_CSR}" \
    -subj "/C=${COUNTRY}/ST=${STATE}/L=${LOCALITY}/O=${ORGANIZATION}/OU=${ORGANIZATIONAL_UNIT}/CN=${PRIMARY_CN}"

# ------------------------------------------------------------------------------
# 3. Create OpenSSL Extensions Configuration (SAN)
# ------------------------------------------------------------------------------
cat <<EOF > "${TEMP_EXT}"
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = @alt_names

[alt_names]
EOF

# Append DNS SANs
DNS_INDEX=1
for d in "${SAN_DOMAINS[@]}"; do
    echo "DNS.${DNS_INDEX} = ${d}" >> "${TEMP_EXT}"
    ((DNS_INDEX++))
done

# Append IP SANs (if defined)
if [ "${#SAN_IPS[@]:-0}" -gt 0 ]; then
    IP_INDEX=1
    for ip in "${SAN_IPS[@]}"; do
        echo "IP.${IP_INDEX} = ${ip}" >> "${TEMP_EXT}"
        ((IP_INDEX++))
    done
fi

# ------------------------------------------------------------------------------
# 4. Sign the Server Certificate with Root CA
# ------------------------------------------------------------------------------
echo "Signing Server Certificate with Root CA..."
openssl x509 -req -in "${TEMP_CSR}" -CA "${CA_CERT}" -CAkey "${CA_KEY}" \
    -CAcreateserial -out "${SERVER_CERT}" -days "${CERT_VALIDITY_DAYS}" -sha256 \
    -extfile "${TEMP_EXT}"

# Clean up temporary files
rm -f "${TEMP_CSR}" "${TEMP_EXT}"

# Also copy rootCA.crt to client scripts directory for convenience
CLIENT_DIR="${SCRIPT_DIR}/../client"
mkdir -p "${CLIENT_DIR}"
cp "${CA_CERT}" "${CLIENT_DIR}/rootCA.crt"

echo "================================================================="
echo " Certificate Generation Complete!"
echo "================================================================="
echo " Server Cert: ${SERVER_CERT}"
echo " Server Key : ${SERVER_KEY}"
echo " Root CA    : ${CA_CERT}"
echo " Client CA  : ${CLIENT_DIR}/rootCA.crt"
echo " Validity   : ${CERT_VALIDITY_DAYS} days (~$((CERT_VALIDITY_DAYS / 365)) years)"
echo "================================================================="
