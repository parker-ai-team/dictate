#!/bin/zsh
# Optional. Creates a self-signed code-signing identity ("Dictate Dev") in a
# dedicated keychain so rebuilds keep the same signature and macOS keeps the
# Microphone and Accessibility grants attached to the app. Afterwards build
# with:
#   export DICTATE_SIGN_IDENTITY="Dictate Dev"
#   export DICTATE_SIGN_KEYCHAIN="$HOME/Library/Keychains/dictate-signing.keychain-db"
#   scripts/build.sh
#
# Why a dedicated keychain: a key imported into the login keychain makes
# codesign ask for the login password on every build. For a keychain we create
# ourselves we know the password; it is a random string stored in the login
# keychain under service "<bundle id>.signing". The key only signs this app.
#
# Safe to re-run (skips if the identity exists). No sudo. If codesign still
# shows a keychain dialog on first use, click "Always Allow".
set -euo pipefail
NAME="${1:-Dictate Dev}"
BUNDLE_ID="${DICTATE_BUNDLE_ID:-com.parkeraiteam.dictate}"
KC="$HOME/Library/Keychains/dictate-signing.keychain-db"
if [[ -f "$KC" ]] && security find-identity -v -p codesigning "$KC" 2>/dev/null | grep -q "\"$NAME\""; then
  echo "identity '$NAME' already present in $KC"; exit 0
fi
PW="$(security find-generic-password -s "$BUNDLE_ID.signing" -a keychain -w 2>/dev/null || true)"
if [[ -z "$PW" ]]; then
  PW="$(openssl rand -hex 24)"
  security add-generic-password -U -s "$BUNDLE_ID.signing" -a keychain \
    -l "Dictate - signing keychain password" -T /usr/bin/security -w "$PW"
fi
[[ -f "$KC" ]] || security create-keychain -p "$PW" "$KC"
security set-keychain-settings "$KC"        # never auto-lock
security unlock-keychain -p "$PW" "$KC"

TMP=$(mktemp -d)
cat > "$TMP/ext.cnf" <<EOF
[req]
distinguished_name=dn
x509_extensions=v3
prompt=no
[dn]
CN=$NAME
[v3]
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
basicConstraints=critical,CA:false
subjectKeyIdentifier=hash
EOF
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -days 3650 -config "$TMP/ext.cnf"
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -out "$TMP/dev.p12" -passout pass:dictate -name "$NAME" -legacy
security import "$TMP/dev.p12" -k "$KC" -P dictate -T /usr/bin/codesign -A
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PW" "$KC" >/dev/null
security add-trusted-cert -r trustRoot -p codeSign -k "$KC" "$TMP/cert.pem"
rm -rf "$TMP"
unset PW
security find-identity -v -p codesigning "$KC" | grep "$NAME" && echo "identity '$NAME' created in $KC"
echo "Note: a NEW certificate means macOS sees a new app - re-grant Accessibility and Microphone once."
