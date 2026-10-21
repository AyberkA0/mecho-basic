#!/bin/zsh
# Creates a self-signed code signing identity in the login keychain.
# Signing with a stable identity keeps the Accessibility permission across rebuilds.
set -euo pipefail

NAME="Mecho Basic Dev"
if security find-certificate -c "$NAME" >/dev/null 2>&1; then
  echo "Identity already exists: $NAME"
  exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=$(openssl rand -hex 16)

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -subj "/CN=$NAME" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" \
  -addext "basicConstraints=critical,CA:false" \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
openssl pkcs12 -export -legacy -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -name "$NAME" -passout "pass:$PASS" -out "$TMP/id.p12"
security import "$TMP/id.p12" -k ~/Library/Keychains/login.keychain-db \
  -P "$PASS" -T /usr/bin/codesign

echo "Created identity: $NAME"
