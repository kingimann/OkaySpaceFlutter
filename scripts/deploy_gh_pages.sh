#!/usr/bin/env bash
# Build the web app and publish build/web to the `gh-pages` branch.
#
# GitHub Pages then serves it at:
#   https://<user>.github.io/OkaySpaceFlutter/
#
# One-time setup (cannot be toggled via token): in the repo on GitHub, go to
# Settings > Pages > Build and deployment > Source: "Deploy from a branch",
# branch: gh-pages, folder: / (root).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

BASE_HREF="/OkaySpaceFlutter/"
BRANCH="gh-pages"
BUILD_DIR="build/web"

echo "==> Building web bundle"
flutter build web --release --base-href "$BASE_HREF"

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
