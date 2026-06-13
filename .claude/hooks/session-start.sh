#!/bin/bash
# Installs the Flutter SDK (which bundles Dart) and resolves project
# dependencies so `flutter analyze` and `flutter test` work in Claude Code
# on the web sessions. Idempotent: the SDK download is skipped once present.
set -euo pipefail

# Only needed in Claude Code on the web (remote) containers. Locally the
# developer already has their own toolchain.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

FLUTTER_VERSION="3.44.2"
FLUTTER_DIR="/opt/flutter"
ARCHIVE="flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/${ARCHIVE}"

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"

# Install the SDK once. The container snapshot is cached after the hook
# completes, so later sessions reuse it and skip straight to `pub get`.
if [ ! -x "${FLUTTER_DIR}/bin/flutter" ]; then
  echo "Installing Flutter ${FLUTTER_VERSION} (one-time)..."
  curl -fsSL --retry 3 -o "/tmp/${ARCHIVE}" "${URL}"
  tar xf "/tmp/${ARCHIVE}" -C /opt
  rm -f "/tmp/${ARCHIVE}"
fi

# Flutter's tool runs git inside its own SDK checkout; the container extracts
# it as root, so mark it (and the project) as safe to silence "dubious
# ownership" errors.
git config --global --add safe.directory "${FLUTTER_DIR}" || true
git config --global --add safe.directory "${PROJECT_DIR}" || true

# Persist flutter/dart on PATH for the rest of the session.
echo "export PATH=\"${FLUTTER_DIR}/bin:\$PATH\"" >> "${CLAUDE_ENV_FILE}"
export PATH="${FLUTTER_DIR}/bin:$PATH"

# Resolve dependencies so analyze/test are ready immediately. Keep output
# quiet on success; surface it only if something fails.
cd "${PROJECT_DIR}"
if ! flutter pub get > /tmp/flutter_pub_get.log 2>&1; then
  echo "flutter pub get failed:"
  cat /tmp/flutter_pub_get.log
  exit 1
fi

echo "Flutter toolchain ready: $(flutter --version 2>/dev/null | grep -m1 '^Flutter')"
