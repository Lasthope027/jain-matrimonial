# Validation record

## Phase 6 update — 2026-11-15

- Final test rerun: **129 passed** — 82 backend against PostgreSQL, 19 customer Flutter and 28 administrator Flutter. Python compilation and dependency consistency checks passed.
- Customer APK generated successfully with Flutter 3.50.0, Dart 3.14.0, JDK 21, Gradle 9.5.0, AGP 9.3.1, SDK 36 and NDK 28.2.13676358. Android's apksigner verified the v2 signature. Manifest checks confirm the expected application ID, minimum API 24, target API 36 and ARM64 ABI. This is a debug build for local testing, not a production-signed release.
- Windows x64 release AOT assets and native runner compiled and linked with Microsoft's 14.44 compiler and Windows SDK 10.0.26100.0 using CMake/Ninja. The distribution includes its Flutter DLL, AOT library, ICU/assets and release Visual C++ runtime DLLs. The extracted distribution opened and rendered the administrator sign-in screen successfully. No administrator password is bundled.
- Native Windows compilation used embedded compiler debug information and a project-local install prefix; it does not require the system MSI installer service or write to Program Files. Standard Flutter Windows builds still use Visual Studio. The local SDK's batch entry point also invokes the Dart Flutter tool directly, matching the local PowerShell launcher and avoiding blocked online bootstrap.
- A real `pg_dump` / `pg_restore` rehearsal passed on two disposable databases, including migration 0005, customer/profile ownership, roles and restored private-file SHA-256. Working data was not altered. Current SQL export regenerated through 0005.
- Source packaging excludes `.env`, SDKs, dependency caches, build outputs, private uploads, signing keys and database backups. Deliverables have SHA-256 checksums and installation/restore instructions.
- Remaining integration limits: no Android hardware/emulator run; adb cannot create its default restricted user-profile state here. Live SMTP delivery needs provider credentials. Docker container startup still requires the unavailable Docker Linux engine. Previous live Dart-client/API proposal and permission checks remain recorded below.

## Phase 5 update — 2026-11-15

- **129 tests passed:** 82 backend/PostgreSQL, 19 customer Flutter and 28 administrator Flutter tests.
- Checks cover preview privacy, original-party isolation, immutable independent responses, concurrent/duplicate requests, rejection, sharing gates, hashes, bilateral biodata selection, notifications and consent invalidation.
- Actual Dart clients passed the complete isolated HTTP workflow: blocked premature downloads, mutual acceptance, explicit release, exact-byte downloads, notifications, edit-triggered closure/revocation and final rejection.
- Migration 0005 applied to both databases. Data-bearing downgrade/re-upgrade retained three proposals, three responses and two sharing records, while withdrawing legacy pending access. Temporary records/files were removed.
- Customer proposal/history/shared-biodata/notification screens and administrator creation/response/sharing/audit/closure controls are implemented. Shared administrator widgets were extracted into admin_common.dart.
- Live API 0.5.0 reports ready at revision 0005. There remain two applications, one database and two roles, with no matching algorithm or public file URLs.
- Native packaging/device checks and real SMTP delivery remain outstanding. See proposals.md.

## Phase 4 update — 2026-11-15

- **101 automated tests passed:** 65 backend/PostgreSQL, 23 administrator Flutter and 13 customer Flutter tests.
- Administrator UI checks cover the wide desktop sidebar, narrow navigation, live refresh, profile filters, customer creation, activation confirmation, association and audit viewing.
- Actual Dart clients passed live HTTP dashboard, combined search/filter, customer creation/email verification, profile counts, deactivation/session revocation, reactivation and audit checks against the disposable API/database. Temporary accounts/data were removed.
- Migration 0004 applied to development and test databases. Downgrade to 0003/re-upgrade verified; successful-login backfill and exclusion of invalidated OTPs checked independently. Metadata/schema comparison passed in the backend suite.
- Live API 0.4.0 reports ready at revision 0004. No default administrator credentials were added to the development database.
- Static analysis has no errors/warnings beyond informational Material compatibility-import deprecations. Existing FastAPI test-client deprecation remains non-failing.
- See administration.md for counts, endpoints, permissions and user workflows. Existing native packaging and SMTP prerequisites remain unchanged. Phase 5 implements proposals and consent-based biodata sharing.

## Phase 3 update — 2026-11-15

- Backend/PostgreSQL suite: **50 passed**, none skipped in the configured integration run.
- Customer Flutter suite: **13 passed**. Administrator Flutter suite: **13 passed**.
- Real Dart clients passed live HTTP profile creation, manual administrator creation, verification, binary upload/download, account reassignment, immediate denial for the former owner, document removal and logout. The test API used jain_test and a separate private storage directory. Test accounts/data and uploaded bytes were removed afterward.
- Migration 0003 applied to development and test databases. Downgrade to 0002 and re-upgrade verified against the cleaned disposable test database. Schema comparison found no drift.
- Live API version 0.3.0 reports ready with revision 0003. Binary upload request schemas verified in the live OpenAPI document.
- Python compilation, dependency consistency and Docker Compose config checks passed. Dependencies are locked, including Pillow/pypdf and Flutter file_picker/platform packages.
- Static analysis reports no errors; informational Material compatibility-import deprecations remain. The existing FastAPI test-client deprecation warning remains non-failing.
- Windows Flutter plugin registration reports that symlink support/Developer Mode is required. No global system setting was changed. Android SDK, Visual Studio C++ desktop tools and Windows Developer Mode remain native packaging prerequisites. Native file dialogs and installable packages have not been exercised.
- See profiles.md for API/UI workflows, validation, storage, authorisation and limits. Phase 4 adds administrator dashboard statistics, customer management and search/filtering.

## Phase 2 update — 2026-11-15

- Backend authentication and permission suite: **23 passed**, against real PostgreSQL. No skipped tests in this run.
- Customer Flutter suite: **7 passed**. Administrator Flutter suite: **7 passed**.
- Both real Dart authentication clients passed live HTTP sign-in and logout against a disposable test API backed by PostgreSQL: customer OTP and separate administrator password login. Ephemeral test accounts were removed afterward; no default administrator was added to the development database.
- Migration 0002 applied to development and test databases; downgrade to 0001 and re-upgrade verified on the test database. Schema comparison found no drift.
- Live API updated to version 0.2.0, readiness revision 0002. The API on port 8000 remains available.
- Current schema has 17 tables: the required fifteen plus sessions and authentication rate limits. The two roles are unchanged.
- Docker Compose config, Python compilation and pip dependency checks passed.
- Flutter analysis has no errors. The SDK reports informational Material compatibility-import deprecations. FastAPI's test client reports an httpx deprecation warning; it does not affect passing tests or runtime APIs.
- SMTP transport, TLS selection, failure handling and non-disclosure were tested with mocks. Live provider delivery is unverified because sender credentials are not configured. Local OTP delivery is explicitly development-only.
- See authentication.md for administrator provisioning, SMTP setup, session behaviour and operational limits. Profile management is the next implementation phase.

The remaining sections record Phase 1 checks and tooling history.

Verified on 2026-11-15:

- Python 3.12.10 virtual environment; locked backend dependencies; pip check passed.
- Python compilation passed.
- PostgreSQL 17.12 runs locally on 127.0.0.1:5432. Development database jain and disposable test database jain_test share the same schema.
- Real Alembic upgrade applied to both databases. Downgrade to base and re-upgrade passed against jain_test.
- Backend tests: 5 passed, none skipped when TEST_DATABASE_URL points at jain_test. Checks include schema compilation, snapshot consistency, safe unavailability responses, role/OTP constraints and update timestamps.
- Alembic offline SQL generated database/schema.sql with all fifteen tables, two seeded roles and timestamp triggers.
- Live API /api/v1/ready returned HTTP 200, PostgreSQL, revision 0001.
- Docker Compose configuration validation passed. Container startup remains untested because Docker Desktop's Linux engine is unavailable. Local PostgreSQL provides the tested development path.
- Flutter 3.50.0 / Dart 3.14.0 installed under .tools/flutter.
- Android customer runner and Windows administrator runner generated successfully; no other application platforms created.
- Both applications resolve dependencies offline and have pubspec.lock files.
- Customer Flutter widget tests: 2 passed. Administrator Flutter widget tests: 2 passed. Tests verify readiness responses, pending-request duplicate prevention and retry availability.
- Dart static analysis: no errors; two informational Material API deprecation notices per app on Flutter 3.50. The compatibility import remains functional.
- Android has Internet permission and allows cleartext only in the debug manifest for local emulator testing.

## Managed-environment tooling

Dart networking exits during online dependency resolution. Python HTTPS downloads work. scripts/cache-flutter-packages.py populates a local cache using published archive SHA-256 checksums. scripts/cache-flutter-artifacts.py downloads universal SDK artifacts. Packages resolve with dart pub get --offline.

Flutter writes persistent state under AppData by default. Specific permission requests did not make those paths writable here. The local, ignored SDK has one configuration-path change in packages/flutter_tools/lib/src/base/config.dart: the project-specific JAIN_FLUTTER_CONFIG_DIR variable takes precedence over the normal path. scripts/flutter-local.ps1 supplies that path, disables analytics, uses the local cache and suppresses online version checks. Application source and standard Flutter installations do not require this SDK change. Replacing the ignored SDK requires reapplying the path change for this managed environment.

PostgreSQL must run in a persistent foreground terminal here; a detached pg_ctl server was stopped after its launching shell exited. Use scripts/start-local-db.ps1. Local DNS resolution of localhost can stall; use numeric 127.0.0.1 in database connection strings.

## Phase 1 native packaging baseline (historical)

At Phase 1, Android SDK and Visual Studio C++ desktop build tools were absent from standard locations, and no native packages existed. Later phase records above supersede that baseline. Phase 1 covered the app foundations; authentication and profile management were added in subsequent phases.
