# Database drop-in

The `demo_site` database is **not** distributed through this repo — it is ~4.7GB
of real business data, and the repo owner shares it separately.

Once you have been given the dump, drop it in here:

```
docker/db-init/10-demo_site.sql.gz
```

Anything in this directory (`.sql`, `.sql.gz`, `.sh`) is imported **once**, the
first time the `mariadb` service starts on an empty data volume, in filename
order. On later starts it is ignored. If you need to re-import, reset the volume:

```bash
docker compose down
docker volume rm emr-stack_mariadb-data
docker compose up -d mariadb
```
