#!/usr/bin/env bash
# Prepare the bind-mounted bench, then hand over to `bench start`.
#
# The bench directory comes from the host, but its `env/` virtualenv does NOT:
# that is a named volume mounted over ./env. The host's venv has absolute host
# paths and a host-built interpreter baked in, so reusing it inside the container
# would break, and writing to it would break the host's bench. Keeping env/ as a
# volume means both benches have their own interpreter over the same source.
set -euo pipefail

BENCH_DIR=/workspace/bench
cd "$BENCH_DIR"

DB_HOST="${FRAPPE_DB_HOST:-mariadb}"
DB_PORT="${FRAPPE_DB_PORT:-3306}"

# ── 1. virtualenv ───────────────────────────────────────────────────────────
# First boot on a given volume builds it; later boots skip straight through.
if [ ! -x env/bin/python ]; then
  echo "[frappe] creating virtualenv (first run — this takes a few minutes)"
  python -m venv env
  env/bin/pip install --no-cache-dir --upgrade pip wheel
fi

# `bench setup requirements` installs every app in sites/apps.txt in editable
# mode. The marker keeps that off the hot path for every subsequent start; delete
# it (or the env volume) after adding an app or changing a pyproject.
if [ ! -f env/.requirements-installed ]; then
  echo "[frappe] installing python requirements for: $(tr '\n' ' ' < sites/apps.txt)"
  # --python only. The default also runs yarn in every app that has a
  # package.json, which would churn the bind-mounted apps/*/node_modules that
  # the host bench shares — and the assets in sites/assets are already built.
  bench setup requirements --python
  touch env/.requirements-installed
fi

# ── 2. wait for the database ────────────────────────────────────────────────
# depends_on only waits for the container, not for mariadb to accept queries.
echo "[frappe] waiting for mariadb at ${DB_HOST}:${DB_PORT}"
for i in $(seq 1 120); do
  if mariadb-admin ping -h "$DB_HOST" -P "$DB_PORT" --silent 2>/dev/null; then
    echo "[frappe] database is up"
    break
  fi
  if [ "$i" = 120 ]; then
    echo "[frappe] ERROR: database did not come up within 240s" >&2
    exit 1
  fi
  sleep 2
done

# ── 3. sanity check the site ────────────────────────────────────────────────
# A seeded DB is a prerequisite, not something this container can create: the
# demo_site data is ~4.7GB of real business tables, not a fixture.
SITE="${FRAPPE_SITE:-demo.localhost}"
if ! mariadb -h "$DB_HOST" -P "$DB_PORT" -u root -p"${MARIADB_ROOT_PASSWORD:-root}" \
      -N -e "SHOW DATABASES LIKE '${FRAPPE_DB_NAME:-demo_site}'" 2>/dev/null | grep -q .; then
  cat >&2 <<MSG
[frappe] WARNING: database '${FRAPPE_DB_NAME:-demo_site}' does not exist yet.
[frappe] The site will not load until the database is imported. See DOCKER.md ->
[frappe] "Load the database". Starting anyway so you can run bench commands.
MSG
fi

echo "[frappe] starting bench for site ${SITE}"
exec "$@"
