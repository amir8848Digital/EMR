# Dev runtime for DC/digital-catalog only.
#
# That repo is a pnpm@11 + turbo workspace, and pnpm 11 refuses to run on Node 20
# (needs >=22.13), so it cannot share the Node 20 image the other apps use.
#
# Debian again, because apps/web/node_modules carries prebuilt glibc binaries
# (@next/swc-linux-x64-gnu, @img/sharp-linux-x64, @rollup/rollup-linux-x64-gnu).
# All three are N-API, so Node 22 loads them even though they were installed
# under a different Node major on the host.
FROM node:22-bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential python3 ca-certificates curl git tini \
    && rm -rf /var/lib/apt/lists/*

# corepack pins the exact pnpm the repo asks for (packageManager: pnpm@11.0.8)
RUN corepack enable && corepack prepare pnpm@11.0.8 --activate

ENV NEXT_TELEMETRY_DISABLED=1 \
    NODE_ENV=development \
    # pnpm's recorded storeDir points into a snap-confined path that does not
    # exist here. Nothing should re-resolve the graph, but if pnpm is ever run it
    # must not inherit that dead path and try to purge node_modules.
    PNPM_HOME=/home/node/.local/share/pnpm

WORKDIR /app
ENTRYPOINT ["/usr/bin/tini", "--"]
