# POS production setup

Development needs none of this: `docker compose up -d` keeps the dev server, demo
accounts and open settings. Production is switched on by **one file**,
`backend_django/.env` (gitignored), and the backend **refuses to start** if a required
value is missing or weak.

## 1. Create `backend_django/.env`

Copy `backend_django/.env.production.example` to `backend_django/.env`, then fill it in:

| Setting | What to put |
|---|---|
| `DJANGO_DEBUG` | `false` |
| `DJANGO_SECRET_KEY` | A fresh random value, 50+ characters. Generate it once: `python -c "import secrets; print(secrets.token_urlsafe(50))"`. Never reuse the dev key or share it. |
| `DJANGO_ALLOWED_HOSTS` | Every address the apps use, comma-separated: the server PC's fixed LAN IP (e.g. `192.168.1.10`), `localhost`, and the tunnel or hosted domain. |
| `DJANGO_HTTPS` | `true` **only** when the server is reached over HTTPS (hosted server or TLS proxy). Leave it `false` on a store LAN server reached by `http://`, or every request is redirected. |
| `DJANGO_CORS_ALLOWED_ORIGINS` | Only if a **web** build of the app is used: its exact origin (e.g. `https://pos.example.com`). Desktop and phone apps need nothing here. |
| `POSTGRES_PASSWORD` | Keep `adminpassword` on an existing database unless you also change it inside PostgreSQL (`ALTER USER admin PASSWORD '...'`) and in `docker-compose.yml`. |

## 2. Rebuild and start

```bash
docker compose build backend      # installs gunicorn (once)
docker compose up -d
docker compose logs -f backend    # expect "Starting gunicorn" and "Listening at"
```

With `DJANGO_DEBUG=false` the backend migrates, collects admin static files and runs
**gunicorn**. It **does not** create demo accounts (`admin` / `demo1234` etc.).

## 3. Create the first real admin (fresh database only)

```bash
docker compose exec backend python manage.py createsuperuser --username owner --full_name "Store Owner"
```

The superuser signs in as Administrator and creates the other staff in the app.
If you are moving an existing demo database to production, **change or deactivate every
demo account** (`admin`, `manager`, `stocker`, `cashier`, `checker`, `cpms_service`),
which all share the password `demo1234`.

## 4. Before going live

- Give the server PC a **fixed LAN address** (DHCP reservation in the router).
- Make Docker start with the PC; turn off sleep on the server PC.
- Back up regularly **and copy the backups off the PC**: the database backups from the app,
  plus `backend_django/media/` (photos) and `backend_django/private/` (backup files).
  See [backup-restore-safety.md](backup-restore-safety.md).
- SMS link: see `scripts/sms_bridge/README.md` (`SMS_ENABLED`, `SMS_GATEWAY_KEY`).
- CPMS link: see the README tunnel section (the CPMS key and the CPMS service password
  must not be the demo values).

## Notes

- One gunicorn process with 8 threads: the failed-login lockout counter lives in that
  process's memory, so a single process keeps the 5-attempt limit exact.
- Uploaded photos (`product-images/`, `avatars/`, `bodega-deliveries/`) are served by the
  backend itself; nothing else under `media/` is reachable.
- `check --deploy` still lists `SECURE_HSTS_INCLUDE_SUBDOMAINS` and `SECURE_HSTS_PRELOAD`;
  they affect the whole domain and are left off on purpose.
