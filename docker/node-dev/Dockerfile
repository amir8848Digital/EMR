# Shared dev runtime for every Node/Next app in this folder.
#
# Debian (not Alpine) on purpose: each app's node_modules is bind-mounted from the
# host, and those trees contain prebuilt glibc binaries (next-swc, sharp, rollup,
# better-sqlite3). Alpine's musl would fail to dlopen them.
#
# Node 20 matches the host's node (v20.20.2), so any node-ABI native module built
# on the host loads unchanged inside the container.
FROM node:20-bookworm-slim

# chromium: the catalog backends (DC/POS/WT) drive puppeteer for PDF output.
# Installing the distro build and pointing puppeteer at it avoids puppeteer's own
# ~170MB download on every npm install.
# build-essential/python3: let node-gyp rebuild a native module if one is missing.
RUN apt-get update && apt-get install -y --no-install-recommends \
      chromium \
      fonts-liberation fonts-dejavu-core \
      build-essential python3 \
      ca-certificates curl git \
      default-mysql-client \
      tini \
    && rm -rf /var/lib/apt/lists/*

ENV PUPPETEER_SKIP_DOWNLOAD=true \
    PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium \
    NEXT_TELEMETRY_DISABLED=1 \
    NODE_ENV=development

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /app
# tini reaps the dev server's children, so Ctrl-C / `compose down` stops cleanly
# instead of leaving nodemon or next-server orphaned.
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
