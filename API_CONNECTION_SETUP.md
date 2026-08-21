# BuildPro — Flutter ↔ Django API Connection Guide

How the Flutter frontend connects to the Dockerized Django (DRF) backend for local development.

## 1. Backend settings (`backend_django/config/settings.py`)

- `ALLOWED_HOSTS = ['*']` (dev only) — accepts requests from any `Host` header
  (web/desktop `127.0.0.1`, Android emulator `10.0.2.2`, physical device LAN IP).
- `'rest_framework'` and `'corsheaders'` added to `INSTALLED_APPS`.
- `corsheaders.middleware.CorsMiddleware` added to `MIDDLEWARE` (above `CommonMiddleware`).
- `CORS_ALLOW_ALL_ORIGINS = True` (dev only; use `CORS_ALLOWED_ORIGINS` in production).

## 2. Health check endpoint

`GET /api/health/` → `{"status": "ok", "service": "BuildPro API"}`

Defined in `config/urls.py` using DRF `@api_view`.

## 3. Base API URL routing (Flutter)

Resolved in `lib/core/config/api_config.dart`:

| Target                  | Base URL                      |
| ----------------------- | ----------------------------- |
| Flutter Web / Desktop   | `http://127.0.0.1:8000`       |
| Android Emulator        | `http://10.0.2.2:8000`        |
| iOS Simulator           | `http://127.0.0.1:8000`       |
| Physical device (Wi-Fi) | `http://<PC_LAN_IP>:8000`     |

Physical-device override (no code edit needed):

```bash
flutter run --dart-define=API_BASE_URL=http://192.168.1.5:8000
```

> For a physical device, ensure the PC and phone are on the same network and
> Windows Firewall allows inbound TCP on port `8000`.

## 4. Flutter API client

- `lib/core/network/api_client.dart` — Dio singleton with a JWT `Authorization: Bearer <token>` interceptor.
- `lib/core/config/api_config.dart` — platform-aware base URL.
- `lib/data/services/health_service.dart` — `ping()` hits `/api/health/`.
- Login page has a **"Test API Connection"** button to prove connectivity.
- `ApiClient.instance.init()` is called in `main.dart`.

## 5. Android networking

`android/app/src/main/AndroidManifest.xml`:

- Added `INTERNET` permission (required for release / physical-device builds).
- Added `android:usesCleartextTraffic="true"` (allows `http://` — dev only).

## 6. How to test

1. Start the backend: `docker compose up -d --build`
2. Verify in a browser: `http://127.0.0.1:8000/api/health/`
3. Install Flutter deps: `flutter pub get`
4. Run the app: `flutter run -d chrome` (or `-d windows`, an emulator, etc.)
5. Tap **Test API Connection**.

## Notes / recommendations (future work)

- Move `SECRET_KEY` and DB credentials to a `.env` file (e.g. `django-environ`).
- Split `settings.py` into base/dev/prod/test.
- Commit Django migrations and drop the auto `makemigrations` in `docker-compose` startup.
- Root `.gitignore` still has legacy `client/` and `server/` paths (folders are now
  `flutter/` / `backend_django/`); Flutter's own `.gitignore` covers `build`/`.dart_tool`,
  but tracked `__pycache__`/`.pyc` files under `backend_django/` still need clean-up
  (`git rm -r --cached backend_django/**/__pycache__`).