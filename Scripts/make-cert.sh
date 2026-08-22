#!/usr/bin/env bash
# Creates a self-signed code signing certificate named "Cobra Dev".
#
# Without a stable signing identity, macOS treats each rebuild as a different
# program and drops the Microphone and Accessibility grants.
set -euo pipefail

NAME="Cobra Dev"

if security find-identity -v -p codesigning | grep -q "$NAME"; then
    echo "'$NAME' already exists."
    exit 0
fi

cat <<'INSTRUCTIONS'
Keychain Access cannot create a code signing certificate from the command line
without an interactive assistant. Do this once:

  1. Open Keychain Access.
  2. Menu: Keychain Access > Certificate Assistant > Create a Certificate…
  3. Name:            Cobra Dev
     Identity Type:   Self Signed Root
     Certificate Type: Code Signing
  4. Create, then Done.

Then re-run Scripts/bundle.sh — it will pick the identity up automatically.
INSTRUCTIONS
