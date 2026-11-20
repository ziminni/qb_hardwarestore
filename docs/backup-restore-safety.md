# Backup and restore safety

## What this change fixes

- Backups now live in `backend_django/private/backups/`, outside public `media/`.
- Django refuses `/media/backups/*` and `/media/system_security_policy.json`, including old files not yet migrated.
- On first backup/security access, old files are moved into private storage. Collisions preserve the entire old directory under `private/backups/legacy-<id>/`; nothing is discarded. Such quarantined archives are retained for manual recovery rather than automatically merged into the new history.
- Admin-only downloads use the authenticated API, not a public file URL.
- A local restore uploads actual file bytes. A server restore selects a known snapshot; an unknown filename never counts as success.
- Restore takes a safety backup, replaces the backed-up database tables in a transaction and rolls back if loading fails. Empty/invalid files are refused.

## Deployment precautions

1. Stop cashiers, the SMS bridge, CPMS writers and background jobs before restoring. Take a separate native PostgreSQL backup first. Never use a running shop as a restore test.
2. Preserve BOTH `backend_django/media/` (photos) and `backend_django/private/` (snapshots/policy) when copying the installation. Restrict private folder access to the backend operator. Backups contain password hashes and personal/financial data.
3. If nginx/IIS or another server serves media directly, deny `/media/backups/` and `/media/system_security_policy.json` there too **before** deploying. Django cannot protect requests which never reach it. Never serve `backend_django/private/`.
4. After deployment, visit Backup & Restore as Admin to migrate legacy files. Check that unauthenticated legacy URLs return 404 and an authenticated snapshot download works. Test on a disposable installation first.
5. After any restore, restart services and have users sign in again. Existing access JWTs may remain valid until expiry; this change does not implement global access-token revocation. Do not allow client activity during restoration.

## Format and limits

These app snapshots contain Django `dumpdata` JSON, even when older file names end in `.dump` or `.sql`. They are **not** native PostgreSQL archives and cannot be fed to `pg_restore` or `psql`. Use a backup from the same application/schema version. Media file names are recorded but the image bytes are not included: back up `media/` separately. `includes_media` is now always false.

The maximum restore upload is 512 MiB. Snapshot generation/loading is synchronous and memory-bound; for large databases or production disaster recovery, use native PostgreSQL backup/restore under maintenance procedures. Do not infer a point-in-time recovery guarantee from this UI.

The schedule screen saves frequency/retention preferences; no timer/scheduler is implemented by this fix. Manual backups are available. A retention policy is not proof that automated backups ran.

## Native backup example (current Compose database)

Run from the POS repository directory, using an output directory outside the web-served tree:

```sh
docker compose exec -T db pg_dump -U admin -d buildpro_pos -Fc > pos-native-backup.dump
```

Use a binary-safe shell/redirection method (PowerShell versions differ). Check the process exit status and validate the archive with PostgreSQL tools before relying on it. This native archive must not be uploaded to the JSON-fixture restore screen.

## Verification

Focused regressions cover private storage, legacy public URL denial, missing/invalid/empty restore input, uploaded bytes, removing post-snapshot rows, pre-restore backup creation, rollback after a failed load, truthful media metadata, and preservation of colliding legacy backups. Flutter tests cover upload/download wire data and visible restore failures. These tests do not prove native Windows file picker behavior, crash recovery, live multi-user restore safety, or production deployment security.
