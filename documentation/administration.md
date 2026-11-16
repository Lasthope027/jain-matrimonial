# Phase 4: administrator dashboard

Sign in to the Windows administrator application with a provisioned administrator account and select **Open dashboard**. Wide windows have a sidebar; narrow windows use bottom navigation. Overview, Profiles, Customers and Activity all use backend-enforced ADMINISTRATOR permissions. Customer credentials receive 403; unauthenticated requests receive 401. There are still exactly two roles.

## Overview

The active dashboard reads PostgreSQL every five seconds while its route is current. New registrations are immediately available to queries and appear on the next UI refresh, without restarting. Failed requests display an error instead of fabricated counts. Aggregates use one repeatable-read snapshot.

Counts include total, pending, approved, rejected and inactive profiles; total/active customers; unlinked profiles; active proposals; pending responses; and mutual acceptance. Total/pending/approved/rejected profile tiles open the corresponding listing. Proposal counts come from the existing tables; proposal workflow is Phase 5.

- Active proposals: PENDING plus MUTUALLY_ACCEPTED, excluding REJECTED.
- Pending responses: missing party responses on PENDING proposals only.
- Unlinked profiles: no account/profile relationship.
- Profile totals include every verification status.

## Profile search

Search by name or full/partial profile UUID. Combine gender, minimum/maximum age, location, community, status and unlinked-only filters. Age is calculated from date of birth on the server. Text matching is case-insensitive under database collation; SQL wildcard characters are treated literally and values are bound as parameters.

Select Apply filters after entering criteria. Background refresh uses the applied query, not partially typed input. Clear filters resets both the query and controls. Tables use pages of 30; the API supports limits from 1 to 100. Open a row for existing editing, verification, document and association controls. Create profile remains available.

## Customers

Search customer email, filter active/inactive accounts, see verification/profile counts and open account detail. Administrator accounts are excluded and cannot be mutated through customer endpoints.

Create customer provisions a passwordless CUSTOMER account. It does not verify email, set a password, issue a session or automatically send an email. The customer must complete email OTP authentication. Successful OTP login records email_verified_at. Existing emails cannot be overwritten or promoted.

Customer detail shows metadata and associated profiles. Link existing profile offers a searchable, paginated unlinked-profile picker; association rechecks profile version and active customer status. Reassignment/unlinking remains available in the profile editor.

Activate/deactivate requires confirmation and current account version. Deactivation atomically disables the customer, revokes all sessions and invalidates pending OTPs, serialised with OTP login using the same email lock. Linked profiles/documents remain in the database. Reactivation requires fresh authentication and does not restore old credentials. Profile deactivation remains a separate verification action.

## Activity

Read-only audit rows show timestamp, actor, action, entity and reference. Search action/entity/actor email and open Details for stored metadata. The first page refreshes automatically; older pages remain still while reviewed. Customer/activity responses exclude password, OTP and session hashes and tokens.

## API

| Method | Route | Purpose |
| --- | --- | --- |
| GET | /api/v1/admin/dashboard | Snapshot statistics |
| GET | /api/v1/admin/profiles | Search/filter/paginate profiles |
| GET/POST | /api/v1/admin/customers | List/search or create customers |
| GET | /api/v1/admin/customers/{id} | Metadata and associated profiles |
| PUT | /api/v1/admin/customers/{id}/activation | Versioned activation |
| GET | /api/v1/admin/audit-logs | Read/search audit records |

Profile parameters: q, gender, age_min, age_max, location, community, status, unassociated_only, offset, limit. Age filters must be 18–100 and ordered correctly.

Customer parameters: q (email substring), active, offset, limit. Create accepts email only. Activation accepts version (positive integer) and active (JSON boolean); role-changing input is rejected. Audit parameters: q, actor_id, offset, limit. Paginated lists return total and next_offset.

## Migration and verification

Migration 0004 adds users.version, users.email_verified_at and list-order/gender indexes. Backfill uses successful CUSTOMER_LOGIN/CUSTOMER_REGISTERED audit records. Consumed OTPs are not proof: codes are also invalidated on replacement, failed delivery or deactivation. Both backfill cases were verified on the disposable database using scripts/check-email-backfill.py, including downgrade/re-upgrade.

Checks: **65 backend/PostgreSQL tests, 23 administrator Flutter tests and 13 customer Flutter tests passed**. This includes desktop sidebar layout, filtering, customer creation, confirmations, linking, polling and audit viewing. Actual Dart clients also passed live HTTP dashboard/filter/customer/verification/activation/revocation/audit checks. Temporary test accounts were removed; no default administrator was shipped.

Packaging prerequisites remain Android SDK, Visual Studio C++ desktop tools and Windows Developer Mode for plugin symlinks. Installable native builds and native file dialogs remain unverified. SMTP requires provider credentials. Phase 5 adds manual proposals, independent responses/history and administrator-authorised biodata after mutual acceptance; no matchmaking algorithm is included.
