#!/usr/bin/env bash
# Creates the "Cobra Dev" self-signed code signing identity.
#
# Why this matters: an ad-hoc signature makes the app's designated requirement
# depend on its cdhash, which changes on every build. macOS then treats each
# rebuild as a different program and silently drops the Microphone and
# Accessibility grants. Signing with a stable certificate instead produces
#
#     identifier "ai.cobra.mac" and certificate leaf = H"..."
#
# which holds across rebuilds, so permissions are granted once.
#
# The certificate does NOT need to be added to the trust store — codesign
# accepts an untrusted self-signed identity, and TCC only cares about the leaf
# hash. That keeps this script free of authorisation prompts.
set -euo pipefail

NAME="Cobra Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$NAME" >/dev/null 2>&1; then
    echo "'$NAME' already exists — nothing to do."
    echo "If it was created by Cobra before August 2026, remove that identity in Keychain Access and rerun this script to replace its permissive ACL."
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/cert.cnf" <<'CNF'
[req]
distinguished_name=dn
x509_extensions=v3
prompt=no
[dn]
CN=Cobra Dev
[v3]
basicConstraints=critical,CA:false
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
CNF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$WORK/cobra.key" -out "$WORK/cobra.crt" -config "$WORK/cert.cnf" 2>/dev/null

# OpenSSL 3 defaults to a PKCS#12 MAC that macOS cannot read ("MAC verification
# failed"); the legacy algorithms below are required for `security import`.
openssl pkcs12 -export -out "$WORK/cobra.p12" \
    -inkey "$WORK/cobra.key" -in "$WORK/cobra.crt" \
    -passout pass:cobra -name "$NAME" \
    -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1 2>/dev/null

# Keep the key non-extractable and do not trust a generally invocable signing
# tool. macOS will ask for confirmation when a build uses this identity.
security import "$WORK/cobra.p12" -k "$KEYCHAIN" -P cobra -x -T ""

echo "Created '$NAME'. Run Scripts/bundle.sh, then grant permissions once."
