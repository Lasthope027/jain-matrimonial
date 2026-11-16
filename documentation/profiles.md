# Phase 3: profiles and private documents

## Application workflow

After signing in, customers open **My profiles**. Each account may manage multiple profiles. **Create profile** opens personal details, education/career, family information and partner preferences. Choose gender and date of birth, enter the full name, and complete optional details as available. The application currently accepts adult profiles aged 18–100 as an application rule. Heights use centimetres and annual income is optional, in rupees.

Community and marital status use selection controls; date of birth uses a date picker; community/marital preferences use multi-select chips. Location, education and profession preferences accept comma-separated choices. Save the profile before adding files. New customer profiles are pending verification and appear in the administrator's central profile listing.

Administrators open **Manage profiles**. They can create office profiles without a customer account, or enter an active registered customer email during creation. Open an existing profile to associate/reassign/unlink a registered customer, upload documents, or approve/reject/deactivate/return it to pending verification. Status changes require confirmation; rejection requires a reason.

No customer can browse another account's profiles. Reassignment immediately removes the former account's access to both the profile and documents. Inactive customers cannot authenticate; customers can view their own inactive profile but cannot edit it or change its documents. Only administrators can reactivate it.

Saving changes to an approved/rejected profile returns it to pending verification and clears the previous verification decision. Uploading/removing documents does the same. Administrator edits also require reverification; inactive profiles remain inactive until an explicit administrator status change. Version checks reject stale writes with HTTP 409 rather than overwriting later changes. Reload the profile before retrying a conflict. The Flutter editor requires saving unsaved changes before document, account or verification actions, and confirms discarding edits when reloading.

## API

| Operation | Route |
| --- | --- |
| List/create own profiles | GET/POST /api/v1/profiles |
| List/create consultancy profiles (administrator) | GET/POST /api/v1/admin/profiles |
| Authorised detail/full update | GET/PUT /api/v1/profiles/{profile_id} |
| Administrator account association | PUT /api/v1/admin/profiles/{profile_id}/account |
| Administrator verification/deactivation | PUT /api/v1/admin/profiles/{profile_id}/verification |
| List/upload authorised documents | GET/POST /api/v1/profiles/{profile_id}/documents |
| Authorised binary download | GET /api/v1/documents/{document_id}/download |
| Remove an authorised document | DELETE /api/v1/documents/{document_id}?version={current_version} |

Lists return items and next_offset; use offset/limit for pagination. Profile updates replace all editable sections and require the current version. Customer input cannot set account ownership, verification status or creator IDs. Administrator account association uses an active registered customer's email, or null to unlink. The backend validates role and ownership independently of the applications.

## Private files

Use Add photograph or Add biodata to select a native file. Use Save document to retrieve an authorised file into a location chosen through the native save dialog. There are no public file URLs or public storage mounts. PDFs are downloaded for opening in the user's preferred viewer; an embedded PDF viewer is not included in this phase.

Supported formats: PDF/JPG/JPEG/PNG, maximum 10 MiB per file and 20 active files per profile. Photographs must be JPEG or PNG. Biodata can use any supported format. PDF files must be unencrypted, valid and contain 1–500 pages; images must be valid, fully decodable and at most 20 megapixels. The backend checks actual content, extension and MIME agreement, not just the supplied filename. Streaming enforces the size limit even without Content-Length. Invalid/stale uploads remove their temporary bytes and never leave usable metadata.

Files live under random server-generated names in STORAGE_PATH. PostgreSQL stores metadata, hash, uploader and timestamps. Download/list metadata does not expose storage keys. Downloads check current account/profile authorisation and use attachment, no-store and restrictive content headers. Every mutation updates profile version and records an audit event; verification/submission sends in-app notification records. Notification listing is a later application feature.

Removing a document withdraws its metadata from access immediately and removes its private file. Metadata is retained with deleted_at for audit references. If physical removal fails, the withdrawn file remains inaccessible through the API and can be removed by operator maintenance. Back up PostgreSQL and private storage together as documented in backup.md.

No counterpart biodata access exists yet. Mutual acceptance and administrator-authorised sharing are Phase 5; merely approving a profile does not expose its documents to another customer.

### Binary upload example

Uploads use a raw binary request body instead of multipart. The API documentation includes binary request schemas. Supply filename, kind and current version as query parameters. Example from PowerShell (replace the sample profile ID, version, token and file path):

```powershell
$uploadUri = 'http://127.0.0.1:8000/api/v1/profiles/PROFILE_UUID/documents?filename=biodata.pdf&kind=BIODATA&version=1'
Invoke-WebRequest -Uri $uploadUri -Method Post -Headers @{ Authorization = "Bearer $accessToken" } -ContentType 'application/pdf' -InFile 'C:\path\biodata.pdf'
```

## Tests and native setup

Migration 0003 adds profile version, sub-community and document withdrawal timestamp. Migration/schema checks use real PostgreSQL, including downgrade/re-upgrade on the disposable test database. Backend tests cover ownership, multiple profiles, manual profiles, reassignment, verification, input validation, optimistic concurrency, document content/size/path checks, access and removal. Widget tests cover listings, edits, inactive restrictions, verification confirmation and preserving unsaved edits. Real Dart clients additionally exercise the full HTTP profile/document flow against the disposable test API.

The file_picker dependency supports Android and Windows native file dialogs. Windows plugin setup reports that Developer Mode is required for symlink creation on this machine. Android SDK and Visual Studio C++ desktop tools also remain packaging prerequisites. No system settings were changed. Native dialogs and installable packages have not been exercised on actual devices; widget/API tests pass without those packaging prerequisites.

Phase 4 will add administrator dashboard statistics, customer management and profile search/filtering. Phase 3 provides the basic shared profile listing and management forms.
