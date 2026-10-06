# Scan transfer (Windows PC → iPad) + GDPR gaps

Scanners export `.ply`/`.stl`/`.obj` to a Windows PC; the app runs on iPadOS.
Patient data already lives on the backend (R2 + Supabase), not only on the device.

## Gaps to close (revised)

Railway and Supabase are already in the correct EU region. Cloudflare R2 is the open problem.

| # | Pri | Gap | Fix |
|---|---|---|---|
| 1 | P0 | All 7 R2 buckets (voice, documents, videos, patient images, scans, shades, smiles) are in Asia-Pacific | New EU-jurisdiction buckets, migrate, delete the old ones |
| 2 | P0 | Public access enabled: anyone with a link can read patient files | Private buckets; serve files only through the authenticated backend |
| 3 | P0 | App sends the user's login token to the R2 host on downloads (`downloadMediaBytes`) | Resolved by #2: downloads go to the backend only |
| 4 | P0 | Processor agreements not confirmed (Cloudflare, Supabase, Railway, Resend, OpenAI) | Sign/confirm each DPA; tick `GDPR_CHECKLIST.md` |
| 5 | P0 | Hardcoded dev encryption keys (`core/encryption.py`; mobile offline cache per `OFFLINE_SYNC.md`) | Keys from env / device keystore |
| 6 | P1 | Patient names may reach logs (`patient_scans.py` logs filename at debug) | Stop logging filenames |
| 7 | P1 | Interpreter sends patient speech/text to OpenAI (`config.py`) | Confirm what is sent; DPA + EU endpoint, or exclude patient data |
| 8 | P1 | Scans/photos not app-encrypted (only notes use Fernet) | Decide: R2 server-side encryption enough, or add app-level |
| 9 | P2 | Activity log partly wired; retention/backup/deletion undocumented; CORS `*` | After P0/P1 |

Rule from the checklist: no real patient data until these P0 items are closed.

## Action plan: fix Cloudflare (gaps #1–#3)

### Step 1: Inventory (dashboard, ~1h)
- List the 7 buckets: size, object count, public domains, `r2.dev` on/off.
- Note which DB tables point at which bucket: `patient_scans`, `shade_detections`, `smile_previews`, `patient_photos`, chat media.
- Done when: a table of bucket → env var → table → size exists.

### Step 2: Create EU buckets (dashboard, ~1h)
- Create 7 buckets with Jurisdiction = European Union, public access off, no custom domain.
- Create a new API token scoped to those buckets only.
- Done when: all 7 exist, private, with the new token.

### Step 3: Code: private access through the backend (~1–2 days)
1. Configurable endpoint: add `R2_JURISDICTION` setting; `get_r2_client` in `r2.py` uses `https://{account}.eu.r2.cloudflarestorage.com` when set.
2. Add `GET /api/files/{kind}/{id}`: loads the row, checks `require_patient_access` (chat media: conversation membership), streams from R2 with the right content type. Write an activity-log entry.
3. Change serializers to return the relative path `/api/files/...` instead of the public URL. The app already handles this: `resolveMediaUrl` prefixes the backend URL, and `downloadMediaBytes` and `Image.network` send the auth header.
4. Key lookup: scans, shades and smiles rows have `file_key`; `patient_photos` stores only `file_url`, so derive the key from the URL path (or add a `file_key` column).
5. Remove the `R2_*_PUBLIC_URL` dependency from upload and delete paths.
6. Tests: owner can read, other user gets 403, missing file gets 404, correct content type, large file streams.
- Done when: every file type opens in the app with public access still on (so rollback is easy).

### Step 4: Migrate data (~half a day, plan a quiet window)
1. Copy old → EU buckets with `rclone` or `aws s3 sync` using two endpoints. Keys stay identical.
2. Compare object counts and sizes per bucket.
3. Point `R2_*_BUCKET` and `R2_JURISDICTION` at the EU buckets; redeploy.
4. Rewrite stored `file_url` values (or let Step 3 ignore them). 
5. Smoke test: open a scan, a photo, a shade, a smile, a chat image, voice and video.
- Done when: all types load from the EU buckets and counts match.

### Step 5: Close the old buckets (~30 min)
- Disable public access on the old buckets, wait a few days, then delete them.
- Rotate the old R2 API token.
- Done when: old buckets are gone, no public URLs respond.

### Step 6: Paperwork (parallel, no code)
- DPAs for Cloudflare, Supabase, Railway, Resend and OpenAI (gap #4).
- Tick EU-region, TLS and DPA items in `GDPR_CHECKLIST.md`.

### Then
Gaps #5 → #6 → #7 → #8, then the inbox/Wi-Fi drop below. The inbox must use the EU private bucket and the same authenticated download path from Step 3.

Order and risk: Steps 1–3 are safe and reversible; Step 4 is the only one with downtime risk, so do it last and after a backup.

## Today's flow

Scans tab → `pickMeshFile` (Files sheet) → whole file read into memory → `POST /api/patients/{id}/scans` → R2 + `patient_scans`.

## Two options

| | A. Web inbox | B. Wi-Fi drop |
|---|---|---|
| Path | PC → backend inbox → iPad | PC → iPad directly over LAN |
| Network | Any (internet) | Same Wi-Fi/LAN only |
| Unassigned files in cloud | Yes (30-day expiry) | No |
| Backend work | Table, endpoints, EU bucket first (#1, #2) | None |
| iPad must be open | No, files wait in the inbox | Yes, on the receive screen |
| Encryption in transit | HTTPS | Plain HTTP on LAN unless self-signed TLS |
| Audit trail | Central log | Only at assign |
| Several iPads/PCs | Yes | No |

Use B if the iPad sits next to the PC in one clinic (cheaper, less GDPR exposure). Use A for remote, multi-iPad or async use. Both can share the same preview-and-assign screen.

### A. Web inbox

PC uploads via a web page; iPad lists "Incoming scans"; dentist previews, assigns to a patient.

Reuses: R2 upload and extension validation, `require_patient_access`, `POST /api/auth/signin`, `patient_scans`, the patient picker.

Defaults:
- Per-user inbox
- Static page served by the backend at `/scan-upload` (no separate deploy)
- Assign = new `patient_scans` row pointing at the same R2 object (no copy)
- 300MB cap, streamed to R2
- 30-day expiry, enforced by a storage lifecycle rule

Phases:
- **0. Confirm.** Hosting body/timeout limits (test a 100MB upload); a sample scanner file (size, filename).
- **0b. EU storage.** Needs the Cloudflare action plan (Steps 1–4) done first. Then add a lifecycle rule to the inbox prefix.
- **1. Backend.** Migration `014_scan_inbox.sql` (`scan_inbox`: id, uploaded_by, file_key, file_url, file_name, format, byte_size, created_at; RLS on). `scan_inbox.py`: `POST`, `GET`, `POST /{id}/assign`, `DELETE`, expiry job. Tests: types and size, owner-only access, assign moves the scan, failed assign keeps the row. No filename logging; activity-log entries.
- **2. PC page.** Login (token in memory only), drag-and-drop, per-file progress and errors, HTTPS + HSTS.
- **3. iPad.** `listScanInbox`, `assignScanInbox`, `deleteScanInbox`; "Incoming" section with badge; preview → assign; delete; pull-to-refresh.
- **4. Optional.** "New scan" notification; empty state showing the page address.

Risks: large uploads on weak Wi-Fi (fallback: chunked upload); wrong-patient assignment (preview + filename shown); orphaned R2 objects on partial failure (tested).

### B. Wi-Fi drop

Scans tab → "Receive from PC" starts a small web server on the iPad and shows `http://<ipad-ip>:8080` plus a QR code and a one-time PIN. The PC opens the address, enters the PIN, drops files; they upload straight to the iPad. Files then go through the same preview → assign flow; nothing reaches the backend until assigned.

Packages (check versions on pub.dev): `dart:io` `HttpServer` or `shelf` + `shelf_multipart` (server), `network_info_plus` (IP), `qr_flutter` (QR), `nsd` (optional stable name).

Needs: `NSLocalNetworkUsageDescription` in `Info.plist`; app in foreground while receiving (iPadOS suspends sockets in background); a session that ends after the transfer; files written to temp storage and deleted after assign or on close.

Risks: guest Wi-Fi that isolates devices blocks it; IP changes (QR code covers it); plain HTTP on the LAN (PIN + short session, optional self-signed TLS); large files held in memory (write to disk instead).

Phases:
- **1. Server.** Start/stop, PIN, upload page, multi-file, write to temp dir, size cap.
- **2. iPad UI.** Receive screen (address, QR, PIN, live file list), then preview → assign.
- **3. Hardening.** Session timeout, cleanup, `Info.plist` permission, test on guest-network and background cases.

## Assigning a patient when there are many

The current picker (`patient_picker.dart`) has no search. For either option:
1. Default to the patient already selected in the app (`PatientSession`): one-tap "Assign to <name>".
2. Add search to the picker.
3. List patients with appointments today first.
4. Suggest a match from the filename if scanners name files by patient/ID (needs a sample export).
5. Option A only: pick the patient on the PC page so files arrive already assigned.

## Order

1. Cloudflare action plan, Steps 1–5 (gaps #1–#3), with Step 6 paperwork in parallel (gap #4).
2. Gap #5 (encryption keys), then #6, #7, #8.
3. Patient picker search.
4. B or A, per the table above (A needs the Cloudflare plan done first).

## Built: web inbox (option A), branch `file-transfer-web-inbox`

- PC page: `GET /scan-upload` (static, `backend/app/static/scan_upload.html`). Signs in with the app account (`POST /api/auth/signin`), token kept in memory only, drag-and-drop, per-file progress.
- API: `POST/GET /api/scan-inbox`, `GET /{id}/file` (preview), `POST /{id}/assign {patient_id}`, `DELETE /{id}`. Owner only; `.ply/.stl/.obj`, 300 MB, streamed to R2.
- Storage: **the existing scans bucket**, prefix `inbox/{user_id}/` (no new bucket, so the later EU move carries it along). Migration `016_scan_inbox.sql`.
- Assign **copies** the object server-side to `patients/{patient}/scans/{item}.ext` and then removes the inbox object. (Not "same object, no copy" as first proposed: the 30-day lifecycle rule on `inbox/` would otherwise delete assigned scans, and patient files must live in the patient's folder for access checks and account deletion.)
- Expiry: Cloudflare lifecycle rule on prefix `inbox/` (delete after 30 days); the list endpoint drops the matching DB rows.
- iPad: Scans tab, "Incoming" button (count) → pick → preview → Assign to selected patient / Delete / Close.
- Not done: German strings for the new UI, scan-quality check at assign time, "new scan" notification.
