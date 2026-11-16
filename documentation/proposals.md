# Phase 5: manual proposals and controlled biodata

Prepare the intended biodata/photographs, approve both profiles and link them to two different active customer accounts before proposing. The administrator selects profiles manually; no matching algorithm is used.

## Administrator

Open Proposals in the Windows dashboard. Search/filter proposals or create one by selecting two approved profiles. Both customers receive an in-app notification. Open a proposal to monitor responses and review documents.

Sharing requires MUTUALLY_ACCEPTED, both recorded acceptances and unchanged eligibility. Select specific files and confirm Authorise sharing. Initial release requires at least one BIODATA document from each profile; photographs are optional. Only selected files go to the opposite parties. Each release records proposal, document, source/recipient profiles, recipient account, administrator, time and SHA-256. Repeated requests are idempotent.

Close proposal / revoke access requires confirmation, current version and an internal reason. Internal notes are not disclosed to customers. Closing permanently ends future API sharing; fresh consent needs a new proposal.

## Customer

My proposals includes Pending, Mutually accepted, Proposal history and Shared biodata views. Each proposal identifies the customer's own managed profile. Counterpart previews expose only age when proposed, height, community, location, qualification and profession. They exclude names, exact birth date, employer, income, family details, email, photographs, document IDs and filenames.

Accept/reject requires confirmation. Responses are independent, immutable and idempotent. One acceptance remains PENDING; either rejection finalises REJECTED; both acceptances yield MUTUALLY_ACCEPTED. Mutual acceptance alone does not release files.

After administrator release, selected counterpart files appear in Shared biodata. Downloads use a proposal-scoped authenticated endpoint that checks the actual recipient, both responses, active owners, profile versions, grant and content hash. Normal private-profile/document endpoints retain ownership restrictions.

Notifications are private to the account, support unread/read state and open linked proposals. They cover registration, verification, proposals, responses, mutual acceptance, sharing and closure. Messages exclude counterpart private data and internal notes. Notifications are in-app; external proposal email or OS push is not required.

## Consent changes and history

CANCELLED, displayed as Closed, distinguishes withdrawal from a customer rejection. Changes to biodata, documents, verification, ownership or owner activation close affected active proposals and revoke grants atomically. Reapproval/reactivation does not restore them. Upload intended files before proposing; adding files later requires reverification and fresh consent.

Original participants retain history using immutable permitted previews and their own original profile name. Reassignment does not disclose later private edits or transfer old proposal history to a new account. Revocation blocks future API requests; it does not erase files already saved outside the application.

## API

| Method | Route | Purpose |
| --- | --- | --- |
| GET | /api/v1/proposals | Own proposals; status/profile/shared_only filters |
| GET | /api/v1/admin/proposals | Administrator search/status listing |
| GET | /api/v1/proposals/{id} | Role-specific authorised detail |
| POST | /api/v1/admin/proposals | Create from two IDs and approved versions |
| POST | /api/v1/proposals/{id}/responses | Customer's own profile ID and response |
| POST | /api/v1/admin/proposals/{id}/sharing | Administrator version and document IDs |
| POST | /api/v1/admin/proposals/{id}/cancel | Administrator version and internal reason |
| GET | /api/v1/proposals/{id}/documents/{document_id}/download | Recipient-specific shared download |
| GET | /api/v1/notifications | Own notifications with pagination/unread filter |
| PUT | /api/v1/notifications/{id}/read | Idempotent own read state |

## Transactions, migration and checks

A PostgreSQL transaction advisory lock serialises consent-affecting operations before row locks across workers. Responses are unique per proposal/profile and active pairs are unique. Simultaneous independent acceptance succeeds; conflicting same-party choices have one winner.

Migration 0005 adds version/owner/preview snapshots, closure, grant recipient/hash/revocation fields and notification profile references. The architecture still has 17 tables and two roles. Earlier phases had no proposal workflow, so legacy active rows cannot prove version-bound consent: upgrade closes them, revokes sharing and preserves audit/history for administrator review. Snapshotless legacy records cannot confer file access. Downgrade removes new consent fields; use backups for production rollback.

Validation: 82 backend/PostgreSQL tests, 19 customer Flutter tests and 28 administrator Flutter tests passed. Actual Dart clients exercised the full two-customer HTTP workflow, blocked premature downloads, exact files after release, notifications, edit-triggered revocation and final rejection. A data-bearing downgrade/re-upgrade preserved proposal/response/sharing history while withdrawing legacy access. Test data/files were removed.

Phase 6 remains packaging and installation verification. Android SDK, Visual Studio C++ desktop tools and Windows Developer Mode for plugin symlinks remain prerequisites. APK/Windows builds, native dialogs/device verification and real SMTP delivery are not claimed complete.
