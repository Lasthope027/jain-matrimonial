# Phase 2: authentication

## Local testing

Run the local PostgreSQL server and API as described in README.md. The ignored .env contains a generated random AUTH_SECRET and OTP_DELIVERY=development. No administrator account or default administrator password is shipped.

Open http://127.0.0.1:8000/docs. Under authentication:

1. POST /api/v1/auth/otp/request with your email.
2. In development mode only, copy development_otp from the response.
3. POST /api/v1/auth/otp/verify with the email and six-digit code.
4. Copy access_token into Swagger's Authorize dialog as the bearer token.
5. GET /api/v1/customer/session or /api/v1/auth/me confirms your account. /api/v1/admin/session must return 403 for a customer.
6. POST /api/v1/auth/logout with refresh_token revokes the session, including the access token.

The customer Android login screen requests/verifies email codes. Debug builds display a development code when the development backend explicitly supplies it. Release builds do not display the development helper. The Windows application opens a separate administrator email/password screen. Both use the same API and database.

Credentials remain only in app memory. Restarting an app requires signing in again. Access tokens expire after 15 minutes. The client rotates the refresh credential when a protected request returns 401; refresh sessions expire absolutely after seven days. Refresh rotation invalidates both previous credentials, and logout revokes the whole session. Account deactivation is checked on every authenticated request and refresh.

## Provision the administrator

From E:\J1, use a separate email from any customer account:

```powershell
$env:PYTHONPATH = "$PWD\backend"
.\.venv\Scripts\python.exe -m app.create_admin --email YOUR_ADMIN_EMAIL
```

The CLI prompts twice without echoing the password. Passwords must contain 12–128 characters and are salted using scrypt (N=32768, r=8, p=1). Existing accounts are never promoted or overwritten. There is no public administrator registration endpoint. There remain exactly two permission categories: CUSTOMER and ADMINISTRATOR.

## SMTP configuration

Edit only the ignored .env, then restart the API:

```dotenv
OTP_DELIVERY=smtp
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_SECURITY=starttls
SMTP_USERNAME=YOUR_SENDER_EMAIL
SMTP_PASSWORD=YOUR_APP_PASSWORD
SMTP_FROM=YOUR_SENDER_EMAIL
```

For implicit TLS use SMTP_SECURITY=ssl with the provider's corresponding port (commonly 465). SMTP certificates are verified. STARTTLS is mandatory in starttls mode; there is no plaintext SMTP mode. SMTP exceptions are converted to safe delivery-failure messages without logging exception content. An OTP whose delivery fails is invalidated, while request rate counters remain committed.

Gmail app passwords require 2-Step Verification and may be unavailable under some account policies. See [Google's app-password instructions](https://support.google.com/accounts/answer/185833). Personal Gmail is a possible free, low-volume testing provider: Google documents daily restrictions around 500 emails, with additional recipient limits. Exceeding limits can pause sending. See [Google's sending limits](https://support.google.com/mail/answer/22839). These are provider restrictions, not a delivery guarantee; check them before deployment. No paid provider is required by the application.

SMTP behaviour is verified with mocked transports, including TLS and failure handling. Real delivery has not been attempted because no sender credentials were supplied. No email has been sent to a real recipient by this implementation work.

## Production configuration

Use ENVIRONMENT=production, OTP_DELIVERY=smtp, configured SMTP_HOST/SMTP_FROM, and a random AUTH_SECRET of at least 32 characters. Generate it with Python secrets.token_urlsafe(48), save it to server-side environment configuration, and keep it out of source control. The locally generated secret is development configuration. All backend workers must use the same secret.

Production configuration rejects development OTP delivery. Production responses never expose OTPs; raw OTPs are never written to application logs. Store passwords as salted scrypt hashes, OTPs as keyed HMAC-SHA256 hashes, and random opaque session tokens only as SHA-256 hashes in PostgreSQL. Rotating AUTH_SECRET invalidates pending OTPs and changes rate-limit keys; existing opaque sessions remain valid until revoked or expired.

Production HTTP is refused (426). Terminate TLS at a reverse proxy and configure Uvicorn to trust forwarded headers only from that proxy, so request schemes and client IPs are accurate. Never use an unrestricted forwarded-allow-ips setting for a directly reachable backend. Auth responses use Cache-Control: no-store. Validation errors omit rejected input so passwords and codes are not reflected.

## Fixed-window limits (per hour)

| Operation | Per email | Per client IP |
| --- | ---: | ---: |
| OTP request | 5 | 20 |
| OTP verification | 30 | 60 |
| Administrator login | 5 | 30 |
| Session refresh | — | 120 |

OTP resend also enforces 60 seconds per email, and each OTP allows at most five incorrect attempts within five minutes. Resending invalidates prior codes. Counters are held in PostgreSQL and guarded by transaction advisory locks, so different workers cannot bypass limits. A failed or throttled request may still consume its broader IP/email budget. A production reverse proxy can apply additional general request limits.

## Database and tests

Migration 0002 adds auth_sessions and auth_rate_limits, for 17 tables in total. It retains the original fifteen tables and exactly two roles. Migration 0001 remains frozen.

Tests require an explicitly configured disposable database ending in _test. Authentication tests truncate test data before/after each case and never run those destructive resets against the development database. The suite covers one-time OTP consumption, expiry, attempts, resends, account reuse/deactivation, notifications/audits, password login, role boundaries, session hashing/expiry/rotation/revocation, concurrency, SMTP failure, production safeguards, and schema drift.

Profile management is Phase 3. Account/profile ownership checks must use the authenticated user returned by the existing dependencies and database relationship checks; no personal-data routes are exposed in Phase 2.
