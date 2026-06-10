#!/usr/bin/env bash
# Manual fallback deploy: build the web app and publish build/web to the
# `gh-pages` branch.
#
# NOTE: Deploys are now handled automatically by GitHub Actions on every push
# to `main` (see .github/workflows/deploy.yml), which uses the reliable
# OIDC-authenticated Pages deployment. This script is only useful if you
# revert Pages back to "Deploy from a branch". With the source set to
# "GitHub Actions", pushing this branch will NOT update the live site.
#
# GitHub Pages serves the site at:
#   https://<user>.github.io/OkaySpaceFlutter/
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

BASE_HREF="/OkaySpaceFlutter/"
BRANCH="gh-pages"
BUILD_DIR="build/web"
BUILD_STAMP="$(git rev-parse --short HEAD 2>/dev/null || echo dev)-$(date -u +%Y%m%d%H%M%S)"

echo "==> Building web bundle"
flutter build web --release --base-href "$BASE_HREF"

# Replace Flutter's caching service worker with a self-unregistering
# "kill switch". It is stamped with a unique build id every deploy so the
# browser always detects a change, installs it, unregisters itself, clears
# caches, and reloads — so deploys are always picked up immediately and
# users never get stuck on a stale build.
cat > "$BUILD_DIR/flutter_service_worker.js" <<SW
// OkaySpace cache kill-switch · build $BUILD_STAMP
self.addEventListener('install', (e) => self.skipWaiting());
self.addEventListener('activate', (e) => {
  e.waitUntil((async () => {
    try { await self.registration.unregister(); } catch (_) {}
    try {
      const keys = await caches.keys();
      await Promise.all(keys.map((k) => caches.delete(k)));
    } catch (_) {}
    const clients = await self.clients.matchAll({ type: 'window' });
    for (const c of clients) { try { c.navigate(c.url); } catch (_) {} }
  })());
});
SW

# Cache-bust the entry scripts. Flutter's main.dart.js / flutter_bootstrap.js
# have fixed names, so without a versioned query GitHub Pages' HTTP cache keeps
# serving the old app code after a deploy. Appending a unique build stamp forces
# the browser to fetch the new code every deploy.
perl -pi -e "s/flutter_bootstrap\.js(\?v=[^\"']*)?/flutter_bootstrap.js?v=$BUILD_STAMP/g" "$BUILD_DIR/index.html"
perl -pi -e "s/main\.dart\.js(\?v=[^\"']*)?/main.dart.js?v=$BUILD_STAMP/g" "$BUILD_DIR/flutter_bootstrap.js"

# Make the HTML itself always revalidate, so a new deploy is picked up on the
# next load instead of waiting out GitHub Pages' ~10-min HTML CDN cache.
perl -0pi -e 's/<head>/<head>\n  <meta http-equiv="Cache-Control" content="no-cache, no-store, must-revalidate">\n  <meta http-equiv="Pragma" content="no-cache">\n  <meta http-equiv="Expires" content="0">/' "$BUILD_DIR/index.html"

# SPA fallback so deep links don't 404 on GitHub Pages.
cp "$BUILD_DIR/index.html" "$BUILD_DIR/404.html"
touch "$BUILD_DIR/.nojekyll"

ORIGIN_URL="$(git config --get remote.origin.url)"
COMMIT_SHA="$(git rev-parse --short HEAD)"

echo "==> Publishing $BUILD_DIR to $BRANCH"
pushd "$BUILD_DIR" >/dev/null
rm -rf .git
git init -q
# The sandbox signing server fails on throwaway repos; disable signing here.
git config commit.gpgsign false
git checkout -q -b "$BRANCH"
git add -A
git commit -q -m "Deploy OkaySpace web app ($COMMIT_SHA)"
git push -f -q "$ORIGIN_URL" "$BRANCH"
popd >/dev/null

echo "✓ Deployed to $BRANCH"
echo "  Live (after Pages is enabled): https://<user>.github.io/OkaySpaceFlutter/"
