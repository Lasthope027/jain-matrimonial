# Local backup and restoration

Back up PostgreSQL and private file storage together during a maintenance window. Store backups outside the server with restricted access and encryption. Never commit them to source control.

From the project directory, using the default local database name/user:

```powershell
docker compose exec -T db pg_dump -U jain -d jain -Fc -f /tmp/jain.dump
docker compose cp db:/tmp/jain.dump .\jain.dump
```

Using pg_dump's output file and docker cp avoids binary redirection corruption on older Windows PowerShell. Copy the private-files Docker volume through your backup tooling as part of the same backup set. In host mode back up `storage/private` instead.

Restore only into an empty database in a separate recovery environment first:

```powershell
docker compose cp .\jain.dump db:/tmp/jain.dump
docker compose exec -T db pg_restore -U jain -d jain --no-owner --exit-on-error /tmp/jain.dump
```

Restore the corresponding private file backup, check readiness and document access, and verify row counts before switching environments. Change database/user arguments if configured differently.

The native PostgreSQL 17 `pg_dump -Fc` / `pg_restore --no-owner --exit-on-error` path was exercised on 2026-11-15 using two newly created disposable databases. The restored database retained migration 0005, its customer/profile association and role. Restored private-file bytes matched the database SHA-256. The script removed its own test databases afterward. Docker's equivalent commands remain untested because the local Docker Linux engine is unavailable.

Run `python scripts/verify-backup.py` from a configured development environment with PostgreSQL tools under `.tools/pgsql/bin` to repeat this rehearsal. It creates uniquely named test databases and uses synthetic data; it does not back up the working database. Credentials come from the configured environment and are not written into the report.
