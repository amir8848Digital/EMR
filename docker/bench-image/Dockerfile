# syntax=docker/dockerfile:1
#
# A ready-to-develop Frappe bench, with all nine apps already installed.
#
# A dev pulls this, restores a database, and starts working — no `bench init`,
# no app installs, no Python or Node setup.
#
# It is built from the bench on disk rather than by cloning, because cloning is
# impossible: none of the nine apps has an `origin` remote, four are private
# 8848digital repos, and `emr_sso` has no remote anywhere plus uncommitted work.
# The copy on disk is the only one that exists.
#
#   build:  docker/bench-image/build.sh
#   run:    docker compose -f docker/bench-image/docker-compose.yml up -d
#
# ⚠ CONTAINS PROPRIETARY CODE (four private 8848digital apps and emr_sso, which
# is licensed Proprietary). Publish only to a PRIVATE registry.
#
# Build context is the bench directory itself (demo-bench/), trimmed by its
# .dockerignore.

ARG BASE=emr-bench-base:latest
FROM ${BASE}

# Matches the `frappe` user in the base image. A fixed uid keeps ownership
# predictable for the volume mounted over the bench.
ARG UID=1000
ARG GID=1000

# Absolute path of the bench this image is built FROM, so symlinks baked with
# that prefix can be repointed. build.sh passes it.
ARG HOST_BENCH_PATH=/home/amir/code/EMR/demo-bench

USER root

# ── everything is built at its FINAL path ───────────────────────────────────
# /workspace/bench is both where the bench is built and where the volume is
# mounted at run time. That is deliberate, and the reason there is no separate
# "pristine copy" elsewhere in the image:
#
#   * The virtualenv's editable installs hardcode ABSOLUTE paths — the .pth
#     files and import finders literally contain /workspace/bench/apps/<app>.
#     Build the venv anywhere else and every import resolves back to that other
#     directory, so a dev's edits under /workspace/bench would silently do
#     nothing.
#   * Docker already seeds an empty NAMED volume from the image's content at the
#     mount point, so mounting a fresh volume here gives the dev a complete
#     bench, and their edits then persist in that volume.
#
# (A bind mount does NOT get seeded — it would shadow the bench with an empty
# directory. The compose file therefore uses a named volume.)
WORKDIR /workspace/bench

# apps/ carries each app's source, its node_modules (frappe + raven, so
# `bench watch` can rebuild frontend assets) and its .git, so devs keep the
# local feature branches and history.
COPY --chown=${UID}:${GID} apps/ ./apps/

# sites/ here is only the bench-level manifest and the built assets — no site
# directory, no credentials (see .dockerignore).
COPY --chown=${UID}:${GID} sites/apps.txt sites/apps.json ./sites/
COPY --chown=${UID}:${GID} sites/assets/ ./sites/assets/
COPY --chown=${UID}:${GID} patches.txt ./patches.txt

# Container-local bench config: redis points at the compose services, and the
# Procfile drops the host's redis lines and hardcoded nvm PATH.
# `cfg` is a named build context (build.sh passes --build-context cfg=...),
# because a COPY cannot reach outside the main context (the bench directory).
COPY --from=cfg --chown=${UID}:${GID} common_site_config.json ./sites/common_site_config.json
COPY --from=cfg --chown=${UID}:${GID} Procfile ./Procfile

# Only the new directories need chowning. A `chown -R /workspace` here would
# rewrite every one of the ~1.5GB of files copied above into a fresh layer,
# roughly doubling the image for no benefit — COPY --chown already set them.
RUN mkdir -p ./logs ./config/pids && chown ${UID}:${GID} ./logs ./config ./config/pids

# Repoint the per-app asset symlinks.
#
# On the host, sites/assets/<app> is an ABSOLUTE symlink into
# /home/amir/code/EMR/demo-bench/apps/..., which does not exist here — copied
# verbatim they all dangle and the desk serves 404s for every stylesheet and
# script. Relative links are correct here and stay correct for anyone who
# relocates the bench. Layout is <bench>/apps/<app>/<app>/public, so from
# sites/assets that is ../../apps/<app>/<app>/public.
#
# `|| [ -n "$app" ]` is required: sites/apps.txt has no trailing newline, so a
# plain `while read` silently drops the last app (product_development) and
# leaves its absolute symlink dangling. The assertion at the end catches that.
RUN set -eu; \
    cd /workspace/bench/sites/assets; \
    while read -r app || [ -n "$app" ]; do \
      [ -n "$app" ] || continue; \
      if [ -d "/workspace/bench/apps/$app/$app/public" ]; then \
        rm -rf "./$app"; \
        ln -s "../../apps/$app/$app/public" "./$app"; \
        echo "assets: $app -> ../../apps/$app/$app/public"; \
      else \
        echo "assets: $app has no public/ — skipped"; \
      fi; \
    done < /workspace/bench/sites/apps.txt; \
    echo "--- dangling asset links (must be none) ---"; \
    find . -maxdepth 1 -xtype l -print | tee /tmp/dangling; \
    test ! -s /tmp/dangling

# Repoint every symlink that still references the host bench path.
#
# The asset links above are not the only ones: each app with a frontend build
# carries apps/<app>/<app>/public/node_modules as an ABSOLUTE symlink into
# $HOST_BENCH_PATH (frappe, raven and frappe_assistant_core all do). Left
# dangling, `bench watch` fails its first CSS build — esbuild's postcss plugin
# resolves stylesheet imports through that link, so it cannot find
# highlight.js/styles/tomorrow.css and the whole asset build errors out.
#
# Done generically rather than by fixing those three paths by name, so an app
# added later is handled too, with an assertion that none are left.
RUN set -eu; \
    echo "--- repointing symlinks that reference $HOST_BENCH_PATH ---"; \
    find /workspace/bench -type l -print | while read -r link; do \
      target=$(readlink "$link"); \
      case "$target" in \
        "$HOST_BENCH_PATH"/*) \
          new="/workspace/bench${target#"$HOST_BENCH_PATH"}"; \
          ln -sfn "$new" "$link"; \
          echo "  $link -> $new"; \
          ;; \
      esac; \
    done; \
    echo "--- asserting none remain ---"; \
    left=$(find /workspace/bench -type l -print | while read -r link; do \
      case "$(readlink "$link")" in "$HOST_BENCH_PATH"/*) echo "$link";; esac; \
    done); \
    if [ -n "$left" ]; then \
      echo "STILL POINTING AT THE HOST BENCH:"; printf '  %s\n' $left; exit 1; \
    fi; \
    echo "clean: no symlink references the host bench path"

# Refuse to build an image carrying credentials.
#
# This image is distributed to developers, so a site_config.json (db_password +
# encryption_key), a signing keypair or a database dump slipping in through a
# .dockerignore mistake would leak to everyone who pulls it. Caught at build
# time rather than discovered later.
#
# Scoped to sites/ and the bench root — the only places such files would land.
# apps/ is upstream source and legitimately contains files that look alarming
# to a naive glob: Frappe ships framework_mariadb.sql / framework_postgres.sql
# (its schema bootstrap, required at runtime) and Raven carries a CI fixture
# named site_config.json.
RUN set -eu; \
    echo "--- scanning for credentials in sites/ and the bench root ---"; \
    found=$( \
      find /workspace/bench/sites \( \
           -name "site_config.json" -o -name "site_config_backup.json" \
        -o -name "*.jwk.json" -o -name "*.sql" -o -name "*.sql.gz" \
        -o -name "*.dump" \) -print 2>/dev/null; \
      find /workspace/bench -maxdepth 1 \( \
           -name "*.env" -o -name "local-clients.env" \
        -o -name "*.sql" -o -name "*.sql.gz" \) -print 2>/dev/null \
    ); \
    if [ -n "$found" ]; then \
      echo "REFUSING TO BUILD — these would ship to every developer:"; \
      printf '  %s\n' $found; \
      exit 1; \
    fi; \
    echo "clean: no site configs, keypairs or dumps outside apps/"

# ── python environment ──────────────────────────────────────────────────────
# Built at image-build time so first start is immediate rather than a ten-minute
# install. Editable installs now record /workspace/bench/apps/<app>, which is
# exactly where the dev's code will be.
USER frappe
RUN python -m venv env \
    && env/bin/pip install --no-cache-dir --quiet --upgrade pip wheel \
    && bench setup requirements --python \
    && find env -name "__pycache__" -prune -exec rm -rf {} + 2>/dev/null || true

# Fail the build rather than ship an image whose imports point somewhere else.
RUN set -eu; \
    echo "--- verifying editable installs point at /workspace/bench ---"; \
    grep -rhoE "^/[^ ]*/apps/[a-z0-9_]+" env/lib/python*/site-packages/*.pth \
      | sort -u | tee /tmp/paths; \
    ! grep -qv "^/workspace/bench/apps/" /tmp/paths

COPY --from=cfg --chown=${UID}:${GID} entrypoint.sh /usr/local/bin/bench-entrypoint.sh
USER root
RUN chmod +x /usr/local/bin/bench-entrypoint.sh
USER frappe

WORKDIR /workspace/bench
EXPOSE 8002 9002
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/bench-entrypoint.sh"]
CMD ["bench", "start"]
