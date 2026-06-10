#!/usr/bin/env bash
# Build the OkaySpace Flutter web bundle into build/web.
#
# Usage:
#   ./scripts/build_web.sh                 # base-href "/"  (root-domain hosting)
#   ./scripts/build_web.sh /OkaySpaceFlutter/   # subpath hosting (GitHub project pages)
set -euo pipefail

BASE_HREF="${1:-/}"

echo "Building web (base-href: $BASE_HREF)…"
flutter build web --release --base-href "$BASE_HREF"
echo "✓ Built build/web"
