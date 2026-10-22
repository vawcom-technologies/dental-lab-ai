# Security Hardening: Risks Closed

21 Oct 2026

## Summary

We closed 11 security gaps in the Elite-D dental lab app. The most serious one let any signed-in user make themselves an administrator. The fixes are live in the database (migration 026, applied 21 Oct 2026) and committed on the `admin-rework` branch; the backend and app changes take effect at the next deploy and release.

In plain terms:

- **Users can no longer change data behind the app's back.** Everything now goes through the server, which checks who may do what and records it in the GDPR audit log.
- **Patient and case data can no longer be read or edited without permission**, even by someone who has our public app key.
- **Paid AI features, uploads and login are protected against abuse**: bots can't run up our AI bill, flood storage, or guess passwords.
- **Fewer clues for attackers**: internal error details and the API's map of endpoints are no longer exposed.

## Risks closed

Sorted by severity. "Before" is what an attacker or misbehaving user could do; "After" is the result now.

| # | Risk | Severity | Before | After |
| --- | --- | --- | --- | --- |
| 1 | Self-promotion to admin | Critical | Any signed-in user could set their own role to admin or mark themselves verified | Users can only read their own profile; only the server changes roles |
| 2 | Direct database writes | Critical | Users could add, edit or delete patients, appointments, notes, sharing rights and messages directly, skipping case rules | All writes go through the server's checks |
| 3 | Forged GDPR audit log | High | Users could insert fake entries into the patient audit log | Only the server writes the audit log |
| 4 | Open case history and lab requests | High | Two tables had no access rules at all | Locked; the public key now sees nothing |
| 5 | Unauthenticated AI endpoints | High | Anyone on the internet could call paid AI features (cost and data risk) | Login required; server-status needs an admin |
| 6 | Unlimited upload size | Medium | Huge uploads could exhaust memory or storage | Capped: 25 MB images and audio, 300 MB scans |
| 7 | Password guessing and signup spam | Medium | No limit on login, signup or reset attempts | Rate-limited per email and per network address |
| 8 | Any website could call the API | Medium | CORS allowed all origins | Only elite-d.de domains |
| 9 | Leaky error messages and API map | Low | Internal errors and the full endpoint list (/docs) were public | Generic errors; docs off in production |
| 10 | Deactivated users kept access | Low | Up to 1 minute of continued access after deactivation | Cut off immediately |
| 11 | Unencrypted connection in release | Low | A misconfigured release could talk to the server over plain HTTP | Release builds refuse non-HTTPS servers |

Privacy extra: the interpreter no longer saves phrases on the iPad that contain numbers, email addresses or more than 120 characters, which are likely patient details.

## Technical details

The root cause of risks 1–4: the Supabase anon key is public (it ships in the forgot-password page), so any user could call PostgREST with their own JWT. The app never does this; the backend uses the service-role key, which bypasses RLS. Removing user-level write policies therefore costs the app nothing.

| Change | Where | Mechanism |
| --- | --- | --- |
| RLS lockdown | `backend/migrations/026_lock_down_direct_access.sql` | RLS on `case_events`, `lab_requests`, `profiles`; dropped all user write policies on messages, conversations, patients, notifications, appointments, patient_access, patient_notes, patient_audit_logs; `profiles` reduced to `profiles_select_own`. SELECT policies kept |
| AI auth | `backend/app/api/ai_poc.py` | `get_current_user` on all routes; `require_admin` on segment-status |
| Upload caps | `backend/app/core/uploads.py` | `read_capped()` reads at most limit+1 bytes, returns 413; used in AI, interpreter, scans, shade, smile, GDPR photo routes |
| Rate limits | `backend/app/core/rate_limit.py`, `api/auth.py` | In-memory sliding window, per IP (X-Forwarded-For) and per email; 429 with Retry-After. Sign-in 20/IP, 5/email per minute; reset 5/3 per 15 min; signup 5/3 per hour |
| CORS | `core/config.py`, `main.py` | `CORS_ORIGINS` allowlist, credentials off |
| Error text | `api/auth.py` | Supabase messages passed through only for known safe hints; others logged, generic reply |
| API docs | `main.py` | `/docs`, `/redoc`, `/openapi.json` off unless `ENABLE_DOCS=true` |
| Session cut-off | `api/admin.py` | `clear_auth_cache()` after deactivate and delete |
| HTTPS | `mobile/lib/core/api/api_host_io.dart` | Release build throws unless `API_BASE` starts with `https://` |
| Interpreter privacy | `interpreter_phrases.dart` | `looksPersonal()` skips digits, `@`, >120 chars |
| Lab signup | `schemas.py`, `api/auth.py` | Photo required for dentists only, validated server-side |

The sign-up trigger `handle_user_login_or_signup` runs as its owner (SECURITY DEFINER), so profile creation is unaffected by the `profiles` lockdown.

## Verification

The lockdown works on the live database, and the server still has full access.

| Check | Result |
| --- | --- |
| Public key reads `case_events`, `lab_requests` | Empty: no rows visible |
| Public key reads `profiles`, `messages`, `patients`, `patient_audit_logs` | Refused (permission denied) |
| Server key reads `case_events`, `lab_requests`, `profiles` | Rows returned, so the app is unaffected |
| Sign-up trigger runs as owner | Yes, so new signups still get a profile |
| App tests (Flutter) | 246 passed |
| Backend tests | 248 passed; 2 AI-model tests fail (a PyTorch/NumPy compatibility test and a shade-segmentation test). These changes didn't touch that code; cause not yet confirmed |

These checks did not cover a manual end-to-end run in the app (signing up and creating a case).

## Remaining actions and limits

- [ ] Deploy the backend and ship a new app release, so the code fixes go live
- [ ] Smoke-test in the app: sign up a dentist and a lab, sign in, send a message, create a patient, approve a case
- [ ] Sign data processing agreements with OpenAI, Roboflow, Resend, Supabase, Cloudflare R2 and Railway (GDPR)
- [ ] Add any other web domain that calls the API to `CORS_ORIGINS`

Known limit: rate limits are held in server memory. They are correct for one server instance, but each extra instance would get its own counters. Move them to Redis if the API scales out.
