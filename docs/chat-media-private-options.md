# Chat media (voice, documents, videos): making the buckets private

Status: patient media (photos, scans, shades, smiles) is private and served through `/api/files`. Chat media is still public. Nothing for chat is built yet; decision pending.

## Why not repeat the patient-media approach

Patient files work because those screens already send the login header, so the address could just change to `/api/files/...`. Chat widgets open bare URLs with no header:

| Chat media | Widget | Problem with the proxy approach |
|---|---|---|
| Images | `Image.network` | Needs headers added (easy) |
| Voice | just_audio | Needs headers added |
| Video | `VideoPlayerController` | Needs headers, range support for seeking, and up to 200 MB per video streamed through Railway |
| Documents | System browser | A browser can't send a login header; needs a download-and-open flow and a new package |

So chat needs an app change either way. The question is which one.

## Options, best to worst

Ranked for scalability and control. The app is still in development, so an app update is acceptable.

1. **On-demand signed link.** The widget calls the API with its login, gets a link valid for a few minutes, then loads it. Access and conversation checked each time, every access can be logged, R2 serves the bytes (no range handling or video traffic on Railway), and documents work because the signed link opens in the browser. Needs changes in all 4 widgets.
2. **Presigned links in messages + auto-refresh.** The backend signs links when it sends messages; the app re-requests a link if one fails. No visible expiry, links can be short. Small app change.
3. **Presigned links in messages.** Same without auto-refresh. No app change. Links work for anyone holding them until expiry (up to 7 days, R2's maximum). A chat screen left open past expiry shows failed media until reloaded.
4. **Authenticated proxy** (`/api/chat-files/...`). Login checked on every request, no expiring links, full audit. Weakest at scale: every voice and video byte passes through Railway, and range support must be written. Documents still need a workaround.
5. **Hybrid.** Proxy for small files, signed links for audio and video. Works, but it's both sets of work.
6. **Authenticated redirect.** API checks the login, then redirects to a short signed link. Small app change, but audio and video players may not keep headers across a redirect. Needs testing first.
7. **Edge token check** (Cloudflare Worker in front of the bucket). No app change, but another component to build and maintain, and it protects no more than option 3.
8. **Move chat media to Supabase Storage.** Same outcome as signed links, plus a storage rewrite and migration.
9. **Postpone chat** and leave the three buckets public for now. Acceptable while there is no real patient data, but chat can mention patients and carry clinical images, so close it before the first clinic.
10. **Leave public and mitigate** (random names, auto-delete). Doesn't close access.

**Add-on, not an alternative:** encrypting files before storing. A public bucket with encrypted files can still be downloaded. It only adds protection if storage is breached, and it adds CPU cost and key management.

## Recommendation

Option 1 for the end state. Option 2 if less app work is wanted first.

## Open decisions

- Which option.
- For option 1: OK to change all 4 chat widgets in one app update?
- Link lifetime (options 2–3): 12 hours, or up to 7 days?
- The R2 API token must be able to read the voice, documents and videos buckets.
