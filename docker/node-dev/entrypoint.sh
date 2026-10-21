#!/usr/bin/env bash
# Bring an app up without ever destroying a working node_modules.
#
# Every app's source is bind-mounted, node_modules included. Where the host
# already installed dependencies we must NOT reinstall: DC's tree holds
# @8848digital/catalyst and offline-kit, which come from GitHub Packages and
# cannot be refetched without an auth token nobody here has. Reinstalling would
# turn a working checkout into a broken one.
#
# So: install only when node_modules is genuinely absent (fresh machine), and
# otherwise run the app exactly as it is.
set -euo pipefail

if [ ! -d node_modules ] || [ -z "$(ls -A node_modules 2>/dev/null)" ]; then
  echo "[entrypoint] node_modules missing in $(pwd) — installing"
  if [ -f pnpm-lock.yaml ]; then
    echo "[entrypoint] ERROR: this is a pnpm workspace and its private @8848digital"
    echo "[entrypoint] packages need a GitHub Packages token. Install on the host"
    echo "[entrypoint] first (see DOCKER.md), then start this service again."
    exit 1
  fi
  npm install --no-audit --no-fund
else
  echo "[entrypoint] reusing existing node_modules in $(pwd)"
fi

exec "$@"
