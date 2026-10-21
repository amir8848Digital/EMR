# Ready-to-develop Frappe bench image

A single image with **all nine bench apps already installed** — source, their
`node_modules`, and a prebuilt Python virtualenv. A dev pulls it, restores a
database, and starts working. No `bench init`, no app installs, no Python or
Node setup.

> ⚠ **This image contains proprietary code** — four private 8848digital apps
> (`8848_frappe_core`, `crm_integration`, `frappe_emr`, `product_development`)
> and `emr_sso`, which is licensed `Proprietary`. It must only ever live in a
> **private** registry. Do not make the GHCR package public.

## For a developer

```bash
docker login ghcr.io                                   # private package
cp docker/bench-image/.env.example docker/bench-image/.env   # fill in passwords
docker compose -f docker/bench-image/docker-compose.yml up -d
docker compose -f docker/bench-image/docker-compose.yml logs -f bench
```

Then load a database (next section) and open **http://demo.localhost:8002**.
Use `demo.localhost`, not `localhost` — Frappe serves per `Host` header.

### Restoring the database

The site directory is deliberately **not** in the image: `site_config.json`
holds the database password and the `encryption_key`, and that key must match
the database being restored or Frappe cannot decrypt stored passwords. Both
travel with the database hand-off, not the image.

**If you were given a dump and the matching `site_config.json`** — fastest path:

```bash
cp <handover>/demo_site.sql.gz docker/bench-image/db-init/10-demo_site.sql.gz
cp -r <handover>/demo.localhost docker/bench-image/handover/
docker compose -f docker/bench-image/docker-compose.yml up -d mariadb   # imports it
docker compose -f docker/bench-image/docker-compose.yml exec bench bash
  cp -r /handover/demo.localhost sites/demo.localhost
  bench --site demo.localhost migrate
```

`db-init/` is imported **once**, on an empty data volume. To re-import:

```bash
docker compose -f docker/bench-image/docker-compose.yml down
docker volume rm emr-bench_mariadb-data
docker compose -f docker/bench-image/docker-compose.yml up -d
```

**If you were given only a dump**, let bench build the site:

```bash
docker compose -f docker/bench-image/docker-compose.yml exec bench bash
  bench new-site demo.localhost --force \
    --db-name demo_site \
    --mariadb-root-password "$MARIADB_ROOT_PASSWORD" \
    --mariadb-user-host-login-scope=%
  bench --site demo.localhost restore /handover/demo_site.sql.gz --encryption-key <key>
  bench --site demo.localhost migrate
```

Both flags matter, and neither is obvious:

| Flag | Why |
|---|---|
| `--force` | the `mariadb` service pre-creates the database from `MARIADB_DATABASE`, and `new-site` refuses to touch an existing database without it — you get *"Database demo_site already exists, please drop it manually"* |
| `--mariadb-user-host-login-scope=%` | bench connects from a different container, so the database user must not be scoped to `localhost`. (`--no-mariadb-socket` is the deprecated spelling.) |

### Developing

```bash
docker compose -f docker/bench-image/docker-compose.yml exec bench bash
  bench --site demo.localhost console
  bench --site demo.localhost migrate
  bench build --app frappe_emr
```

Your bench lives in the `bench` volume, seeded from the image on first run, so
**edits to app code persist** across `down`/`up`. `bench start` runs web,
socketio, `watch`, schedule and worker, so editing frontend assets rebuilds them
live. To work on an app from your own checkout instead, bind-mount over it:

```yaml
    volumes:
      - ../../demo-bench/apps/frappe_emr:/workspace/bench/apps/frappe_emr
```

Reset to a clean bench: `docker volume rm emr-bench_bench`.

## What has been verified

Built and run end to end on a clean volume, with a site created from scratch:

| Check | Result |
|---|---|
| image | 6.3GB, Python **3.14.8**, Node **24.22.0**, bench 5.31.0, wkhtmltopdf with patched qt |
| named-volume seeding | a fresh volume arrives with all **9 apps** and the virtualenv; `emr_sso` present on branch `N` with its git history |
| `bench start` | all five processes stay up (web, socketio, watch, schedule, worker) |
| `bench watch` | reaches *"Watching for changes..."* — frontend asset rebuilds work |
| `bench --site` commands | work; the bench directory is recognised |
| dangling asset symlinks | **0** |
| `bench new-site` | succeeds with the two flags above |
| desk | `/` and `/login` return **HTTP 200** |
| assets | serve with real content — frappe's 951KB `desk.bundle.css` and a private app's `8848_frappe_core` JS bundle both **HTTP 200** |

Not covered: restoring the real ~4.7GB `demo_site` dump, which needs the dump
and its matching `encryption_key`. The site above was a fresh one, which
exercises the same path.

Five defects were found and fixed while getting here, four of which only
appeared when the image was actually run rather than merely built:

| Defect | Symptom |
|---|---|
| `.dockerignore` glob `sites/*/` also excluded `sites/assets` | build failed |
| `sites/apps.txt` has no trailing newline, so `while read` dropped the last app | `product_development`'s asset symlink left dangling |
| the virtualenv's editable `.pth` files hardcode absolute paths | staging the bench elsewhere and copying it in made **every dev edit a no-op** |
| Frappe v16 requires Node >= 24; the base had 22 | `bench watch` exited and `bench start` tore down every other process with it |
| `apps/<app>/<app>/public/node_modules` are absolute symlinks into the source bench | `bench watch` CSS build died on a missing `highlight.js` stylesheet |

The build now asserts against the last three: no symlink may reference the
source bench, no editable install may point outside `/workspace/bench`, and no
credential file may be present.

## For whoever maintains the image

```bash
docker/bench-image/build.sh            # build
docker/bench-image/build.sh --push     # build and push to GHCR
```

It builds two images so the runtime is defined once:

| Image | Contents |
|---|---|
| `emr-bench-base` | OS, Python 3.14, Node 24, wkhtmltopdf (patched qt), bench CLI — from `docker/frappe/Dockerfile`, shared with the main stack |
| `emr-bench` | the above, plus the nine apps, their `node_modules`, and the virtualenv |

**It is built from the bench on disk, not by cloning** — and it has to be. None
of the nine apps has an `origin` remote, four are private, and `emr_sso` has no
remote anywhere plus uncommitted work. The copy in `demo-bench/apps` is the only
one that exists, which also means **this image is currently the only backup of
`emr_sso`**. Treat it accordingly.

What is left out, and why:

| Excluded | Why |
|---|---|
| `sites/*/` | `site_config.json` carries the db password and `encryption_key`; `private/`+`public/` are ~605MB of uploads |
| `env/` (host) | host-absolute paths and a host-built interpreter; the image builds its own |
| `logs/`, `config/pids/` | runtime state |

After adding an app or changing a `pyproject.toml`, rebuild and bump `TAG`.
Devs then `docker compose pull` and `docker volume rm emr-bench_bench` to
re-seed from the new image.
