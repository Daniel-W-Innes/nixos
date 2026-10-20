#!/usr/bin/env bash
# Generates the AudioMuse postgres mTLS key material into the given output
# dir (default: ./audiomuse-pg-keys).
#
# Layout of the output:
#   ca.key        CA private key — DELETE after encryption/distribution steps
#   ca.crt        CA cert        -> generic/server/audiomuse-pg-certs/ca.crt
#   server.key    server key     -> encrypt as secrets/audiomuse-pg-server-key.age
#   server.crt    server cert    -> generic/server/audiomuse-pg-certs/server.crt
#   client.key    client key     -> encrypt as secrets/audiomuse-pg-client-key.age
#   client.crt    client cert    -> generic/server/audiomuse-pg-certs/client.crt
#
# The private keys must never be committed plaintext — encrypt them with
#   age -a -r <each recipient from secrets/secrets.nix> -o secrets/<name>.age <key>
# (the recipients are the ssh-ed25519 pubkeys listed under `users ++ systems`).
#
# The server cert's primary SAN is DNS:melon (the router's DHCP-lease DNS —
# it auto-tracks melon's IP, and containers can't do mDNS .local). The IP SAN
# is belt-and-suspenders for direct-IP dials. The client cert CN=audiomuse is
# required by pg_hba clientcert=verify-full.
set -euo pipefail

OUT="${1:-audiomuse-pg-keys}"
DAYS=3650

rm -rf "$OUT"
mkdir -p "$OUT"
cd "$OUT"

# --- CA ------------------------------------------------------------------
openssl genrsa -out ca.key 4096 2>/dev/null
openssl req -x509 -new -key ca.key -out ca.crt -days "$DAYS" -subj "/CN=audiomuse-pg-ca"

# --- Server cert ---------------------------------------------------------
openssl genrsa -out server.key 4096 2>/dev/null
openssl req -new -key server.key -out server.csr -subj "/CN=audiomuse-postgres"
openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
  -out server.crt -days "$DAYS" \
  -extfile <(
    printf '%s\n' \
      "subjectAltName=DNS:melon,DNS:melon.local,IP:10.8.8.140,IP:127.0.0.1,DNS:audiomuse-postgres" \
      "basicConstraints=CA:FALSE" \
      "keyUsage=digitalSignature,keyEncipherment" \
      "extendedKeyUsage=serverAuth"
  )

# --- Client cert ---------------------------------------------------------
openssl genrsa -out client.key 4096 2>/dev/null
openssl req -new -key client.key -out client.csr -subj "/CN=audiomuse"
openssl x509 -req -in client.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
  -out client.crt -days "$DAYS" \
  -extfile <(
    printf '%s\n' \
      "basicConstraints=CA:FALSE" \
      "keyUsage=digitalSignature" \
      "extendedKeyUsage=clientAuth"
  )

rm -f server.csr client.csr
echo "Generated certs in $OUT (CA key ca.key is for renewal only — delete after distributing)."
