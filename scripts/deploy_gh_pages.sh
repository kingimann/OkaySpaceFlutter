#!/usr/bin/env bash
#
# Deploy the Flutter web app to the `gh-pages` branch WITHOUT GitHub Actions.
#
# Usage:  ./scripts/deploy_gh_pages.sh [base-href]
#   base-href defaults to /OkaySpaceFlutter/ (GitHub project-page subpath).
#
# One-time setup: GitHub repo Settings -> Pages -> Build and deployment ->
# Source: "Deploy from a branch" -> Branch: gh-pages / (root).
# Then the app serves at https://kingimann.github.io/OkaySpaceFlutter/
set -euo pipefail

cd "$(dirname "$0")/.."
BASE_HREF="${1:-/OkaySpaceFlutter/}"

echo "==> Building web (base-href=$BASE_HREF)"
flutter build web --release --base-href "$BASE_HREF"

ORIGIN="$(git remote get-url origin)"
TMP="$(mktemp -d)"
cp -r build/web/. "$TMP"/
touch "$TMP/.nojekyll"   # serve as-is (no Jekyll processing)

git -C "$TMP" init -q
git -C "$TMP" add -A
git -C "$TMP" commit -q -m "Deploy web $(date -u +%FT%TZ)"
git -C "$TMP" push -f "$ORIGIN" HEAD:gh-pages

rm -rf "$TMP"
echo "==> Pushed to gh-pages."
