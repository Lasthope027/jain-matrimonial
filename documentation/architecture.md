# Architecture and delivery plan

## Communication

Customer Android and administrator Windows communicate with the same versioned FastAPI REST API. Only the backend connects to PostgreSQL and private storage. The initial connection screens call readiness; no customer data routes are exposed before authentication is implemented.

## Schema

The fifteen required tables are defined in backend/app/models.py. Accounts have one role category, constrained to CUSTOMER or ADMINISTRATOR. Account/profile relationships permit multiple profiles per account and at most one authorised account per profile. Administrators can create unassociated profiles. Education, family and preferences are one-to-one profile extensions. Document records contain private storage keys, hashes, types and sizes; never file blobs or public URLs.

Proposals store ordered distinct profile UUID pairs. A partial unique index prevents duplicate non-rejected proposals for a pair. Responses record actor, profile and decision independently. Sharing records identify proposal, exact document, recipient profile and administrator; timestamps are automatic. Notification, audit and OTP records support later workflows. Foreign keys restrict deletion; use deactivation for retained history.

## Decisions to enforce in service transactions

- Customer registration uses email OTP; administrator login uses a password and separate entry point, with no public administrator creation.
- Access tokens expire and refresh sessions must be revocable; a session-table migration is expected in Phase 2.
- OTPs expire after five minutes, allow five failures, and have a 60-second resend cooldown. Use keyed secure hashes, invalidation and database-backed rate limits across workers.
- Only approved profiles with active associated customer accounts receive proposals. Administrators may retain unassociated records.
- Customer edits to approved biodata require reverification. A future service must define proposal behaviour when a participating profile becomes inactive or pending.
- Pre-acceptance match summaries expose only age, height, community, general location, education and profession. Names, employer, family details, exact birth date, photographs and files remain private pending explicit policy approval.
- Acceptance, rejection and sharing require transaction locks. A response must belong to one of the proposal's two profiles. Either rejection is final; both acceptances yield mutual acceptance. Only then may an administrator authorise specific counterpart documents. These cross-record rules are not implemented by the Phase 1 schema alone.
- Document types: PDF/JPEG/PNG; maximum 10 MiB. Later uploads require content-signature validation, random storage keys and permission-checked retrieval.
- Development SMTP configuration is separate from production. Production OTPs must never be logged. Provider free-tier limits must be verified when SMTP is integrated.
- Define retention, account recovery, legal notices and backup retention before production.

## Phases

1. Foundation: schema, migrations, backend connectivity and Flutter platform scaffolding.
2. Authentication: SMTP OTP, separate administrator login, tokens, sessions, rate limiting and authorisation tests.
3. Profiles: account association, forms, documents, verification and access tests.
4. Administration: dashboard, customer management, filtering and audit views.
5. Proposals: manual selection, limited previews, responses, notifications and audited biodata sharing.
6. Packaging: real PostgreSQL integration and permission tests, Android APK, Windows application and installation documentation.

No automated matching, Firebase, public profile browsing or additional permission roles.
