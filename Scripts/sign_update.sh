#!/bin/bash
# Sign a DMG for Sparkle using EdDSA (ed25519)
DMG="$1"
if [ ! -f "$DMG" ]; then echo "Usage: $0 <dmg-path>"; exit 1; fi

PRIVATE_KEY="/tmp/sparkle_private.pem"
LENGTH=$(stat -f%z "$DMG")
SIGNATURE=$(echo -n "$LENGTH" | cat - <(cat "$DMG") | openssl dgst -sha512 -sign "$PRIVATE_KEY" | base64)

echo "  sparkle:length=\"$LENGTH\""
echo "  sparkle:edSignature=\"$SIGNATURE\""
