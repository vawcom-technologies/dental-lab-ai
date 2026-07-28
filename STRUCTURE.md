# Dental Lab AI — Repository Structure

Canonical layout for further development. Matches the full project specification.

```
dental-lab-ai/
├── PROJECT.md                 # Full product/spec (source of truth)
├── README.md                  # How to run
├── STRUCTURE.md               # This file
├── docs/
│   ├── ARCHITECTURE.md
│   ├── BRANDING_DIRECTIONS.md
│   ├── CLIENT_FOLLOWUP_WEEK1.md
│   ├── GDPR_CHECKLIST.md
│   └── WEEKLY_PLAN.md
├── references/                # Client assets (never commit real PHI)
│   ├── logo.jpg
│   ├── tooth-shapes.jpg
│   ├── datev/                 # DATEV/Datext XML samples (DATEV clarified)
│   ├── scans/                 # PLY good/bad/blurry (pending client)
│   ├── shades/                # VITA Classical reference images
│   └── shapes/                # Shape library PNGs (pending client)
├── backend/                   # FastAPI + AI
│   ├── app/
│   │   ├── main.py
│   │   ├── core/              # config, db, security, encryption
│   │   ├── models/            # Full SQLAlchemy schema (§5)
│   │   ├── schemas/           # Pydantic DTOs
│   │   ├── api/               # HTTP routers
│   │   ├── services/          # Business logic
│   │   ├── ai/                # Scan quality, shade, scan-body, translate
│   │   └── storage/           # Encrypted file paths (local → S3/EU)
│   ├── requirements.txt
│   └── tests/
├── mobile/                    # Flutter iPad app (dentist)
│   └── lib/
│       ├── main.dart
│       ├── core/              # theme, api, auth, offline sync
│       └── features/          # One folder per product area
└── lab-web/                   # Lab dashboard (Week 4) — scaffold only
    └── README.md
```

## Feature → code map

| Spec area | Backend | Flutter | Status |
|-----------|---------|---------|--------|
| Auth (dentist/lab) | `api/auth.py` | `features/auth/` | Done (Week 1) |
| Patients CRUD | `api/patients.py` | `features/patients/` | Done (Week 1) |
| Cases | `api/cases.py` | `features/cases/` | Scaffold |
| Camera / photos | `api/photos.py` | `features/camera/` | Scaffold (Week 2) |
| Scans + validation | `api/scans.py`, `ai/scan_quality.py` | `features/scans/` | POC + scaffold |
| Shade AI + override | `ai/shade.py`, `api/ai_*.py` | `features/shade/` | POC + scaffold |
| Shape overlay | `api/shapes.py` | `features/shapes/` | Scaffold (Week 3) |
| Scan body diameter | `ai/scan_body.py` | `features/scan_body/` | Scaffold |
| Chat + voice | `api/messages.py` | `features/chat/` | Scaffold (Week 4) |
| Notifications | `api/notifications.py` | `features/notifications/` | Scaffold |
| DATEV/XML export | `services/datev_export.py` | — | Skeleton |
| Offline sync | — | `core/offline/` | Scaffold (Week 2) |
| Lab dashboard | — | `lab-web/` | Scaffold (Week 4) |
| Website | — | deferred | Pending client scope |
| GDPR / audit | `models/activity.py`, encryption stubs | — | Partial |

## Roles

| Role | Client | Access |
|------|--------|--------|
| `dentist` | Flutter iPad | Own patients/cases only |
| `lab` | Lab web | All cases, chat, exports, activity logs |
| `admin` | Future | Full system (not MVP) |

## XML note

Spec originally said “Datext”. Client sample is **DATEV**-like (`references/datev/`). Keep both names in docs until client confirms official XSD.
