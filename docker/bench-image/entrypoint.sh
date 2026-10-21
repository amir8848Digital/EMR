#!/usr/bin/env bash
# Wait for the database, report whether the site is ready, then start bench.
#
# There is no copy-into-place step here: the bench is built at /workspace/bench
# inside the image, and Docker seeds an empty NAMED volume mounted there from
# that content. So a fresh volume arrives complete, and the dev's edits then
# live in the volume. (The venv's editable installs hardcode
# /workspace/bench/apps/<app>, which is why the bench cannot be staged anywhere
# else and copied in — imports would resolve to the staging directory.)
set -euo pipefail

BENCH=/workspace/bench
SITE="${FRAPPE_SITE:-demo.localhost}"
DB_HOST="${FRAPPE_DB_HOST:-mariadb}"
DB_PORT="${FRAPPE_DB_PORT:-3306}"

cd "$BENCH"

# A bind mount is not seeded by Docker, so catch that rather than failing later
# with something cryptic.
if [ ! -e sites/apps.txt ]; then
  cat >&2 <<MSG
[bench] ERROR: $BENCH looks empty — no sites/apps.txt.
[bench] This happens when a BIND mount is mounted over it: Docker only seeds
[bench] NAMED volumes from the image. Use the named volume in
[bench] docker/bench-image/docker-compose.yml, or bind-mount individual apps
[bench] under apps/ instead of the whole bench.
MSG
  exit 1
fi

mkdir -p logs config/pids

# ── wait for the database ───────────────────────────────────────────────────
# depends_on waits for the container, not for mariadb to accept queries.
echo "[bench] waiting for mariadb at ${DB_HOST}:${DB_PORT}"
for i in $(seq 1 150); do
  if mariadb-admin ping -h "$DB_HOST" -P "$DB_PORT" --silent 2>/dev/null; then
    echo "[bench] database is up"
    break
  fi
  if [ "$i" = 150 ]; then
    echo "[bench] ERROR: database did not accept connections within 300s" >&2
    exit 1
  fi
  sleep 2
done

# ── tell the dev what to do if the site is not set up yet ───────────────────
# The site directory is intentionally not in the image: site_config.json holds
# the db password and the encryption_key, and that key must match the database
# being restored. Both travel with the database hand-off.
if [ ! -f "sites/$SITE/site_config.json" ]; then
  cat <<MSG

  ────────────────────────────────────────────────────────────────────────────
  Site '$SITE' is not set up yet. All $(grep -c . sites/apps.txt) apps are
  installed and ready — you only need a database.

  Given a dump AND the matching site_config.json:
      cp -r /handover/$SITE sites/$SITE
      bench --site $SITE migrate

  Given only a dump:
      bench new-site $SITE --force \
        --db-name "${FRAPPE_DB_NAME:-demo_site}" \
        --mariadb-root-password <root-pw> \
        --mariadb-user-host-login-scope=%
      bench --site $SITE restore /handover/<dump.sql.gz> --encryption-key <key>
      bench --site $SITE migrate

  Both flags are needed here, and neither is obvious:
    --force                        the compose mariadb pre-creates the database
                                   from MARIADB_DATABASE, and new-site refuses
                                   to touch an existing one without this
    --mariadb-user-host-login-scope=%   bench connects from another container,
                                   so the db user must not be scoped to
                                   localhost

  The encryption key must match the dump or Frappe cannot decrypt stored
  passwords. Ask whoever shared the database for it.

  bench is starting anyway, so you can run the above with:
      docker compose -f docker/bench-image/docker-compose.yml exec bench bash
  ────────────────────────────────────────────────────────────────────────────

MSG
else
  echo "[bench] site $SITE is present"
fi

echo "[bench] starting: $*"
exec "$@"
