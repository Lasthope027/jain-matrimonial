# Installation and local testing

The system has two native applications and one shared backend. Keep the complete Windows application folder together: the executable needs its Flutter DLL and data directory. The development apps connect to `http://127.0.0.1:8000`. The customer APK is an ARM64 debug build for Android 7.0/API 24 or later; it is intended for local testing over USB.

## Existing E:\J1 development environment

Open PowerShell in `E:\J1`. Keep the database and API terminals running:

For the existing local toolchain, the verified single-terminal alternative is `.\.venv\Scripts\python.exe scripts\start-local-stack.py`. It supervises PostgreSQL and the API together. Use that command or the two commands below, never both at once.

```powershell
.\scripts\start-local-db.ps1
```

```powershell
.\scripts\start-api.ps1
```

Readiness is `http://127.0.0.1:8000/api/v1/ready`. It must report migration 0005. If PostgreSQL is already running, use that instance instead of starting another one. This managed execution environment may isolate separately launched processes; the validation run started PostgreSQL and its test process within one parent session.

Provision your administrator once, in another terminal with the database running:

```powershell
$env:PYTHONPATH = "$PWD\backend"
.\.venv\Scripts\python.exe -m app.create_admin --email your-address@example.com
```

Enter a password at the hidden prompt. There is no shipped administrator password. Start `jain_admin.exe` from the extracted Windows application folder and sign in with that account.

## Customer phone over USB

Enable USB debugging on an ARM64 Android phone and authorise your own computer when the phone asks. Install the debug APK using Android platform-tools:

```powershell
.\.tools\android-sdk\platform-tools\adb.exe devices
.\.tools\android-sdk\platform-tools\adb.exe install -r .\dist\jain-customer-arm64-debug.apk
.\.tools\android-sdk\platform-tools\adb.exe reverse tcp:8000 tcp:8000
```

Keep USB connected while testing. The reverse tunnel lets the APK's localhost URL reach the computer's localhost API. Reapply the reverse command after reconnecting. No LAN binding is needed. Use a development test email to request a code. Development OTP responses are supported only when the backend is explicitly configured for development delivery; SMTP delivery requires the settings below.

## Fresh machine: backend and database

Install Python 3.12 and PostgreSQL 17, or use the optional Docker Compose configuration. Extract the source, create a Python virtual environment, and install `backend/requirements.lock.txt`. Copy `.env.example` to `.env`, create your own PostgreSQL database/user, and set `DATABASE_URL` and a random `AUTH_SECRET` in that private file. Generate a secret with `python -c "import secrets; print(secrets.token_urlsafe(48))"`.

From the source root:

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r backend\requirements.lock.txt
.\.venv\Scripts\python.exe -m alembic upgrade head
$env:PYTHONPATH = "$PWD\backend"
.\.venv\Scripts\python.exe -m uvicorn app.main:app --host 127.0.0.1 --port 8000
```

The private storage directory must be writable by the backend process. Keep it outside public web roots. Back up the database and private files together; see `backup.md`. Docker Compose is an alternative documented in the README; its Linux engine must be available.

## Email and production configuration

Set `OTP_DELIVERY=smtp`, `SMTP_HOST`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD`, `SMTP_FROM` and `SMTP_SECURITY` in `.env`. See `authentication.md` and `.env.example` for the exact settings. Verify delivery through your chosen provider; live email delivery has not been tested without provider credentials.

Before deployment, use `ENVIRONMENT=production`, your own database credentials and random secret, SMTP delivery, and an HTTPS reverse proxy. Build both apps with the actual HTTPS API URL. Customer release signing requires your own Android signing key; the local debug APK is not a production release. Keep credentials, signing keys, uploads and backups outside source archives.

## Rebuild the applications on a standard machine

Install Flutter 3.50.0/Dart 3.14.0, Java 21, Android SDK platform/build-tools 36 and NDK 28.2.13676358 for Android. Windows builds need Visual Studio's Desktop development with C++ workload and a Windows SDK. Enable Developer Mode for Flutter's plugin links. Resolve each app's dependencies with its committed lockfile, then:

```powershell
cd customer_app
flutter pub get
flutter build apk --debug --target-platform android-arm64 --dart-define=API_BASE_URL=http://127.0.0.1:8000
cd ..\admin_app
flutter pub get
flutter build windows --release --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

For a remote deployment, replace both URLs with your HTTPS endpoint and configure Android release signing before building a release APK. The ignored `.tools` SDK and local build scripts contain managed-environment workarounds and are not required on a standard Flutter installation.
