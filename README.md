# Jain Matrimonial Management System

Private consultancy system: one Flutter Android customer app, one Flutter Windows administrator app, one FastAPI backend and one PostgreSQL database.

## Current scope

Phases 1–6 are implemented: shared schema/migrations, authentication, profile/document management, administrator/customer management, manual proposals, independent responses, in-app notifications, administrator-authorised biodata after mutual acceptance, testing and native packaging. `dist` contains the ARM64 customer debug APK, Windows x64 administrator release bundle, source archive and SHA-256 checksums. The Windows bundle was opened successfully. The Android APK signature and manifest were verified; a physical-device run remains unverified.

Start with `documentation/installation.md` for app setup, administrator provisioning and USB phone testing. There is no default administrator password. Local development builds use the localhost backend; production needs your HTTPS endpoint, SMTP settings and Android release signing key.

See `documentation/authentication.md` for local login testing, administrator provisioning, SMTP setup, provider limits and production configuration. Real SMTP delivery requires your provider credentials; local testing uses development OTP responses.
See `documentation/profiles.md` for profile/document workflows, ownership rules, file limits, API usage and native file-dialog setup.
See `documentation/administration.md` for dashboard counts, filters, customer activation and audit workflows.
See `documentation/proposals.md` for proposal consent, private previews, sharing, revocation and notifications.

## Start the existing local setup

The local PostgreSQL 17.12 cluster and Flutter 3.50.0 SDK are under `.tools` (excluded from source control). The development database is `jain`; the disposable integration-test database is `jain_test`. Both are on `127.0.0.1:5432`. From E:\J1, open separate PowerShell terminals:

```powershell
.\scripts\start-local-db.ps1
```

```powershell
.\scripts\start-api.ps1
```

Keep these terminals running. Alternatively, `.\.venv\Scripts\python.exe scripts\start-local-stack.py` supervises the database and API together in one foreground terminal, which is the verified launch method in this managed environment. Do not launch both methods simultaneously. Check http://127.0.0.1:8000/api/v1/ready.

Run the complete backend suite against the disposable test database:

```powershell
$env:TEST_DATABASE_URL = 'postgresql+psycopg://jain:local-development-only@127.0.0.1:5432/jain_test'
.\.venv\Scripts\python.exe -m pytest -q
```

The local Flutter launcher avoids this environment's AppData and Dart online-download restrictions:

```powershell
cd customer_app
..\scripts\flutter-local.ps1 test --no-pub
cd ..\admin_app
..\scripts\flutter-local.ps1 test --no-pub
```

Normal Flutter installations can use `flutter test`. The project-local JDK 21, Android SDK/NDK, Microsoft compiler and Windows SDK were used to produce the native deliverables. `scripts/build-android-local.ps1` and `scripts/build-windows-local.ps1` rebuild them with that existing local toolchain. Standard installations can use the Flutter build commands in the installation guide.

## Backend development (PowerShell, from E:\J1)

```powershell
Copy-Item .env.example .env
.\.venv\Scripts\python.exe -m pip install -r backend\requirements.lock.txt
$env:PYTHONPATH = "$PWD\backend"
.\.venv\Scripts\python.exe -m pytest
```

Start Docker Desktop with Linux containers, then:

```powershell
docker compose up --build -d
```

Compose waits for PostgreSQL, applies the migration in a one-shot service, then starts the API. API documentation: http://127.0.0.1:8000/docs. Liveness: `/api/v1/health`. Readiness: `/api/v1/ready` (503 until the database is migrated). Services bind only to localhost by default.

For a host-run backend instead:

```powershell
docker compose up -d db
.\.venv\Scripts\python.exe -m alembic upgrade head
.\.venv\Scripts\python.exe -m uvicorn app.main:app --reload
```

The environment example contains local-development credentials. Replace them before deployment. Private files are never mounted as public static files. Compose stores files in a private Docker volume; host mode uses `storage/private`.

## Flutter platform setup

Install Flutter stable, Android SDK for the customer app, and Visual Studio with Desktop development with C++ for the Windows app. Run `flutter doctor` to verify platform prerequisites.

```powershell
.\scripts\bootstrap-flutter.ps1 -Flutter C:\path\to\flutter\bin\flutter.bat
cd customer_app
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
cd ..\admin_app
flutter run -d windows --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

Android and Windows runners and dependency lockfiles are already generated. The bootstrap script can regenerate platform scaffolding with a normal Flutter installation. It does not create a third app. It removes only the generated counter-app test and runs the repository's real tests.

Android emulator development can use `10.0.2.2` to reach the host. The packaged APK instead uses `127.0.0.1:8000` with `adb reverse tcp:8000 tcp:8000` over USB. See the installation guide. The debug manifest permits local HTTP; release deployment requires HTTPS. Keep development OTP delivery confined to local testing.

## Migrations and schema

Alembic configuration is at the repository root. Migration `0001` has a frozen schema snapshot, seeds CUSTOMER and ADMINISTRATOR, and installs update timestamp triggers. Migration `0002` adds hashed sessions and shared rate limits. Migration `0003` adds profile concurrency, sub-community and document withdrawal. Migration `0004` adds customer versioning, email verification backfill and list indexes. Migration `0005` adds consent snapshots, cancellation and auditable biodata grants. `database/schema.sql` is exported through 0005. Future revisions must not edit the initial snapshot. Schema changes belong in new Alembic revisions.

```powershell
.\.venv\Scripts\python.exe -m alembic upgrade head --sql
```

See `documentation/architecture.md` for decisions and remaining phases. See `documentation/backup.md` for database backup and restore.
See `documentation/validation.md` for checks performed and outstanding environment blockers.

## Reference documentation

- FastAPI modular routes: https://fastapi.tiangolo.com/tutorial/bigger-applications/
- Flutter setup: https://docs.flutter.dev/install
- Alembic migrations: https://alembic.sqlalchemy.org/en/latest/tutorial.html
