#!/usr/bin/env bash
# Builds a signed App Store IPA for Xcode / Transporter.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ ! -f .env.production ]]; then
  echo "Create mobile/.env.production from .env.production.example"
  echo "It must be a public https:// URL — not 127.0.0.1."
  exit 1
fi

if grep -Eq 'API_BASE=https?://(127\.0\.0\.1|localhost|0\.0\.0\.0|192\.168\.|10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.)' .env.production; then
  echo "API_BASE in .env.production is still a local/LAN address."
  echo "Point it at your live HTTPS server before building for the App Store."
  exit 1
fi

if ! grep -Eq '^API_BASE=https://' .env.production; then
  echo "API_BASE must start with https://"
  exit 1
fi

flutter pub get
flutter build ipa \
  --release \
  --dart-define-from-file=.env.production \
  --export-options-plist=ios/ExportOptions.plist

echo
echo "IPA ready. Upload this file with Transporter or Xcode Organizer:"
ls -1 "$ROOT"/build/ios/ipa/*.ipa
echo
echo "Archive (optional, open in Xcode):"
ls -1d "$ROOT"/build/ios/archive/*.xcarchive 2>/dev/null || true
