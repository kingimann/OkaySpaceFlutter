#!/usr/bin/env bash
#
# Build the OkaySpace Flutter web app for deployment.
#
# Usage:
#   ./scripts/build_web.sh [base-href]
#
#   base-href  Path the app is served from. Defaults to "/".
#              For root-domain hosting (e.g. example.com)      -> "/"
#              For subpath hosting (e.g. GitHub project pages,
#              kingimann.github.io/OkaySpaceFlutter/)           -> "/OkaySpaceFlutter/"
#              The value must start and end with a slash.
#
# Output: build/web  — a set of static files. Deploy them to any static host
# (GitHub Pages, Render static site, Netlify, Vercel, S3/CloudFront, Nginx…).
#
# NOTE: Flutter web must be served over HTTP(S); opening index.html via file://
# yields a blank page.
set -euo pipefail

BASE_HREF="${1:-/}"

# Allow running from anywhere by moving to the repo root (parent of this script).
cd "$(dirname "$0")/.."

if ! command -v flutter >/dev/null 2>&1; then
  echo "error: 'flutter' not found on PATH. Install the Flutter SDK first." >&2
  exit 1
fi

echo "==> flutter pub get"
flutter pub get

echo "==> flutter build web --release --base-href \"$BASE_HREF\""
flutter build web --release --base-href "$BASE_HREF"

echo
echo "Built build/web (base-href=$BASE_HREF)."
echo "Preview locally:  (cd build/web && python3 -m http.server 8000)  -> http://localhost:8000"
