# Dental Lab AI — Backend

FastAPI backend for the Elite Dent / Dental Lab AI platform.  
**Active stack today:** Supabase Auth + `public.profiles` + Resend email.  
**Legacy (not mounted):** older SQLAlchemy/SQLite domain APIs (patients, cases, scans, etc.) remain in the repo for future migration.

---

## Quick start

```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt

# Fill in backend/.env (see Environment variables below)

uvicorn app.main:app --reload --port 8000
```

- API docs (Swagger): http://127.0.0.1:8000/docs  
- Health: `GET /health`

---

## High-level architecture

```
┌─────────────┐     HTTP/JSON      ┌──────────────────┐
│ Flutter app │ ─────────────────► │ FastAPI (uvicorn)│
└─────────────┘                    └────────┬─────────┘
                                            │
                    ┌───────────────────────┼───────────────────────┐
                    ▼                       ▼                       ▼
            Supabase Auth            public.profiles            Resend
         (signup/signin/JWT)      (role/verified/deleted)   (admin notify email)
```

### What runs when a request arrives

1. **CORS middleware** — allows all origins (dev-friendly).
2. **Debug middleware** — logs method, path, status, timing, and full response body.
3. **Router** — matches `/api/auth/*`, `/api/admin/*`, `/health`, `/api/ai/*`.
4. **Dependencies** (when needed) — `get_current_user` / `require_admin` validate the Bearer JWT via Supabase, then overlay role/profile fields from `public.profiles`.

---

## Folder & file map

```
backend/
├── .env                    # Secrets & config (gitignored) — never commit real keys
├── requirements.txt        # Python dependencies
├── README.md               # This file
└── app/
    ├── main.py             # FastAPI app entrypoint, middleware, router mounting
    ├── schemas.py          # Shared Pydantic request/response models
    ├── api/                # HTTP route modules (APIRouter)
    ├── core/               # Config, auth, Supabase clients, middleware
    ├── services/           # Business helpers (email, profiles, legacy notify/export)
    ├── models/             # Legacy SQLAlchemy models (not used by active auth stack)
    ├── storage/            # Legacy encrypted local file storage
    └── ai/                 # AI POC helpers (shade, scan quality, scan-body)
```

---

## Root files

| File | Purpose |
|------|---------|
| `requirements.txt` | Pin/minimum versions of all Python packages |
| `.env` | Runtime secrets loaded by `pydantic-settings` (`app/core/config.py`) |
| `README.md` | Project documentation |

---

## `app/main.py` — application entrypoint

- Creates the FastAPI app (`Dental Lab AI API`, v0.3.0).
- On startup (`lifespan`): enables API debug logging.
- Middleware order (Starlette: last added = outermost):
  - `CORSMiddleware`
  - `DebugRequestMiddleware`
- **Mounted routers (active):**
  - `health` → `/health`
  - `auth` → `/api/auth`
  - `admin` → `/api/admin`
  - `ai_poc` → `/api/ai` (optional; skipped if import fails)

Patients/cases/scans/etc. routers exist under `app/api/` but are **not** included in `main.py` (they still expect the removed local SQLAlchemy DB).

---

## `app/core/` — foundations

| File | What it does | Main packages |
|------|----------------|---------------|
| `config.py` | `Settings` class reads `.env` into typed fields | `pydantic-settings` |
| `supabase_client.py` | Cached Supabase clients: **anon** (user auth) and **service role** (admin/DB) | `supabase` |
| `security.py` | JWT Bearer auth, `AuthUser`, `get_current_user`, `require_admin`, `require_dentist`; overlays `profiles` onto metadata | `fastapi`, `supabase` (via clients), profiles service |
| `debug_middleware.py` | Logs every request/response including full response body + `print` | `starlette` |
| `database.py` | **Stub** — local SQLAlchemy DB removed; `get_db()` raises | — |
| `encryption.py` | Fernet encrypt/decrypt for file-at-rest (legacy storage) | `cryptography` |

### Auth helpers in `security.py`

- **`get_current_user`** — validates `Authorization: Bearer <token>` with `supabase.auth.get_user(token)`, builds `AuthUser`, then prefers `public.profiles` for `role`, `name`, `email`, `clinic_name`, `phone`.
- **`require_admin`** — allows only `role == "admin"` (from profiles when present).
- **`require_dentist`** — allows `clinic` / `dentist` / `lab` (legacy naming).

---

## `app/api/` — HTTP endpoints

### Active routers

#### `health.py`
| Method | Path | Auth | Behavior |
|--------|------|------|----------|
| `GET` | `/health` | No | Liveness JSON |

#### `auth.py` — authentication & account

| Method | Path | Auth | Behavior |
|--------|------|------|----------|
| `POST` | `/api/auth/signup` | No | Supabase `sign_up`; role hardcoded `clinic`; German phone `+49` + 11 digits; queues Resend admin email; **no tokens** until verified |
| `POST` | `/api/auth/signin` | No | Supabase password login; loads `profiles`; blocks deleted/unverified (admins bypass verified); returns tokens + profile fields |
| `POST` | `/api/auth/forgot-password` | No | Supabase password-reset email |
| `GET` | `/api/auth/me` | Bearer | Current user (profile-aware) |
| `POST` | `/api/auth/me/password` | Bearer | Verify current password, then admin `update_user_by_id` for new password |

**Signup flow**

1. Validate body (`SignUpRequest`) — email, name, password, clinic, phone (`normalize_german_phone`).
2. `sign_up` with user_metadata (`role: clinic`, …).
3. Reject duplicates (`user.identities == []`).
4. Background task → Resend “new signup” email to admin.
5. Return `TokenOut` **without** access tokens + message that admin verification is required.

**Signin flow**

1. `sign_in_with_password`.
2. `fetch_profile(user.id)`.
3. `_enforce_signin_access`:
   - `deleted == true` → **403** deactivated  
   - not admin and `verified != true` → **403** pending verification  
   - missing profile → treated as unverified  
4. Build `TokenOut` from **profiles** (fallback to Auth metadata).

**Packages used here:** `fastapi`, `supabase`, `logging`; Resend via `app.services.email`.

#### `admin.py` — admin user management (`public.profiles`)

All routes require **`require_admin`** (Bearer + `role=admin` in profiles).

| Method | Path | Behavior |
|--------|------|----------|
| `GET` | `/api/admin/users?skip=&limit=` | List non-deleted profiles, `updated_at` desc |
| `PATCH` | `/api/admin/users/{user_id}/verify` | Set `verified=true` |
| `DELETE` | `/api/admin/users/{user_id}/soft-delete` | Set `deleted=true` |
| `DELETE` | `/api/admin/users/{user_id}/hard-delete` | Delete Auth user + profiles row |

Uses **service-role** client for table + Auth admin APIs.

### Legacy / unmounted routers (SQLAlchemy era)

These files still exist and import `get_db` / old `User` models. They are **not** registered in `main.py` until migrated to Supabase.

| File | Intended domain |
|------|-----------------|
| `patients.py` | Patient CRUD |
| `cases.py` | Case list/create/update |
| `scans.py` | Scan upload/list/delete/preview |
| `photos.py` | Case photos |
| `messages.py` | Case chat + inbox threads |
| `notifications.py` | In-app notifications |
| `clinical.py` | Shade / shape / scan-body selections |
| `exports.py` | DATEV-like XML export |
| `reports.py` | Clinic dashboard summary |
| `ai_poc.py` | **Mounted** AI proof-of-concept endpoints (no DB required for most) |

---

## `app/schemas.py` — Pydantic models

| Schema | Used by |
|--------|---------|
| `SignUpRequest` | Signup; validates DE phone via `normalize_german_phone` |
| `SignInRequest` | Signin |
| `ForgotPasswordRequest` | Forgot password |
| `PasswordChange` | Change password |
| `TokenOut` | Auth token/profile response |
| `UserOut` | `/me` |
| `AuthMessageOut` | Simple `{ message }` responses |
| `ProfileOut` / `ProfileListOut` / `ProfileActionOut` | Admin APIs |
| `Patient*` / `Case*` / AI POC models | Legacy / AI routes |

**Packages:** `pydantic`, `email-validator` (for `EmailStr`).

---

## `app/services/` — reusable logic

| File | Purpose | Packages |
|------|---------|----------|
| `profiles.py` | `fetch_profile(user_id)` from `public.profiles` via service role | `supabase` |
| `email.py` | Resend HTML email on successful signup (admin notification) | `resend` |
| `notify.py` | Legacy in-app notification helpers (SQLAlchemy) | — |
| `datev_export.py` | Legacy DATEV-like XML builder | — |

### `public.profiles` columns (expected)

| Column | Type | Notes |
|--------|------|-------|
| `id` | uuid | Matches Supabase Auth user id |
| `name` | text | |
| `email` | text | |
| `phone` | text | Stored as `+49` + 11 digits |
| `role` | text | `clinic`, `admin`, … |
| `clinic_name` | text | |
| `verified` | bool | Must be true to sign in (except admin) |
| `deleted` | bool | Soft-delete flag |
| `updated_at` | timestamptz | |

---

## `app/models/` — legacy SQLAlchemy ORM

Used by the old local SQLite stack. **Not wired** in current `main.py`.

| File | Tables / classes |
|------|------------------|
| `user.py` | `User` |
| `patient.py` | `Patient` |
| `case.py` | `Case` |
| `scan.py` | `Scan` |
| `photo.py` | `Photo` |
| `clinical.py` | Shade / shape / scan-body selections |
| `comms.py` | Message, Notification, XMLExport, ActivityLog |
| `__init__.py` | Re-exports all models |

---

## `app/storage/` & `app/ai/`

| Path | Purpose | Packages |
|------|---------|----------|
| `storage/local.py` | Encrypt files under `data/uploads/` (legacy) | uses `encryption.py` → `cryptography` |
| `ai/shade.py` | VITA shade suggestion from image colors | `numpy`, `pillow` / OpenCV as used |
| `ai/scan_quality.py` | Mesh quality heuristics (PLY/STL/OBJ) | `numpy` |
| `ai/scan_body.py` | Implant scan-body diameter table + photo detect | `opencv-python-headless`, `numpy` |
| `ai/translate.py` | Translation stub | — |

---

## Packages (`requirements.txt`) — where they are used

| Package | Role | Primary files |
|---------|------|----------------|
| `fastapi` | Web framework, routers, Depends, HTTPException | `main.py`, all `app/api/*`, `security.py` |
| `uvicorn[standard]` | ASGI server | CLI only |
| `pydantic` | Request/response validation | `schemas.py`, settings |
| `pydantic-settings` | Load `.env` into `Settings` | `core/config.py` |
| `email-validator` | Validates `EmailStr` | `schemas.py` |
| `python-multipart` | Form/file uploads | AI POC + legacy upload routes |
| `supabase` | Auth + PostgREST client | `supabase_client.py`, `auth.py`, `admin.py`, `profiles.py`, `security.py` |
| `resend` | Transactional email | `services/email.py` |
| `pillow` | Image handling (AI/shade) | `ai/*`, AI routes |
| `numpy` | Numeric / mesh / color math | `ai/*` |
| `opencv-python-headless` | Image processing (scan-body detect) | `ai/scan_body.py` |
| `aiofiles` | Async file I/O (legacy uploads) | storage-related routes |
| `cryptography` | Fernet file encryption | `core/encryption.py`, `storage/local.py` |

---

## Environment variables (`.env`)

Create `backend/.env` (do **not** commit secrets):

```env
SUPABASE_URL=
SUPABASE_ANON_KEY=
SUPABASE_SERVICE_ROLE_KEY=
PASSWORD_RESET_REDIRECT_URL=
RESEND_API_KEY=
RESEND_FROM_EMAIL=onboarding@resend.dev
RESEND_WELCOME_TO_EMAIL=
```

| Variable | Used for |
|----------|----------|
| `SUPABASE_URL` | Project URL |
| `SUPABASE_ANON_KEY` | User-facing Auth (signup/signin/reset/`get_user`) |
| `SUPABASE_SERVICE_ROLE_KEY` | Admin Auth + `profiles` reads/writes (bypasses RLS) |
| `PASSWORD_RESET_REDIRECT_URL` | Optional redirect after reset email link |
| `RESEND_API_KEY` | Send signup notification emails |
| `RESEND_FROM_EMAIL` | From address (Resend sandbox: `onboarding@resend.dev`) |
| `RESEND_WELCOME_TO_EMAIL` | Admin inbox for “new signup” alerts |

Mapped in code by `app/core/config.py` (`supabase_url`, `resend_api_key`, …).

---

## Roles & access control

| Role | How set | Can sign in if unverified? | Admin APIs |
|------|---------|----------------------------|------------|
| `clinic` | Hardcoded on signup | No — needs `profiles.verified=true` | No |
| `admin` | Set in `profiles.role` (and optionally Auth metadata) | Yes (verified check bypassed) | Yes |

**How to make an admin**

1. Create/sign up a user (or create in Supabase Auth).
2. In `public.profiles`, set `role = 'admin'` and `verified = true`.
3. Sign in → `TokenOut.role` and `/api/auth/me` read from **profiles**, not stale JWT metadata.
4. Call `/api/admin/*` with `Authorization: Bearer <access_token>`.

Soft-deleted users (`deleted=true`) cannot sign in (403).

---

## Important business rules

1. **Phone (signup):** normalized to `+49` + exactly **11** digits.
2. **Signup:** no access tokens returned; client should return to login and wait for admin verify.
3. **Signin:** 401 = bad credentials; 403 = deleted or pending verification.
4. **Duplicate signup:** empty `identities` → 400 “already exists” (no email sent).
5. **Change password:** Bearer required; current password re-checked via Supabase; update via service-role admin API.
6. **Debug logging:** every response body is printed in the uvicorn terminal (`debug_middleware.py`).

---

## How the pieces work together (example: clinic user lifecycle)

```
Signup ──► Supabase Auth user + (trigger/app) profiles row
       ──► Resend email to admin
       ──► API returns success message (no token)

Admin  ──► PATCH /api/admin/users/{id}/verify
       ──► profiles.verified = true

Signin ──► Auth password OK
       ──► profiles check (verified / not deleted)
       ──► JWT + role/name from profiles

App    ──► Authorization: Bearer …
       ──► GET /api/auth/me
       ──► POST /api/auth/me/password (optional)
```

---

## API cheat sheet (active)

```
GET  /health
POST /api/auth/signup
POST /api/auth/signin
POST /api/auth/forgot-password
GET  /api/auth/me
POST /api/auth/me/password
GET  /api/admin/users
PATCH /api/admin/users/{user_id}/verify
DELETE /api/admin/users/{user_id}/soft-delete
DELETE /api/admin/users/{user_id}/hard-delete
POST /api/ai/shade/suggest
POST /api/ai/scan/validate
GET  /api/ai/scan-body/table
POST /api/ai/scan-body/match
POST /api/ai/scan-body/detect
```

Interactive docs: `/docs`.

---

## Related apps

- **Flutter client:** `../mobile/` — login/register, profile change-password, admin laboratories UI calling these endpoints.
- This README covers **`backend/`** only.

---

## Notes for future work

- Migrate patients/cases/scans/messages/etc. from SQLAlchemy models to Supabase tables and remount those routers in `main.py`.
- Replace stub `core/database.py` once domain data lives fully in Supabase.
- Tighten CORS and remove full response-body debug logging before production.
