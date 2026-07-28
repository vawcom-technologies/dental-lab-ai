# Dental Lab AI — Elite Dent

iPad dentist app + FastAPI backend for remote dental-lab case capture, AI checks, and DATEV/XML export.

**Start here:** [`STRUCTURE.md`](STRUCTURE.md) · [`PROJECT.md`](PROJECT.md) · [`docs/WEEKLY_PLAN.md`](docs/WEEKLY_PLAN.md)

## Run

### Backend

```bash
cd backend
python3.12 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload --port 8000
```

- API docs: http://127.0.0.1:8000/docs  
- Dentist: `dentist@elitedent.demo` / `demo1234`  
- Lab: `lab@elitedent.demo` / `demo1234`

### Flutter

```bash
cd mobile
flutter pub get
flutter run -d chrome --dart-define=API_BASE=http://127.0.0.1:8000
```

## Layout

| Path | Purpose |
|------|---------|
| `mobile/` | Flutter iPad app |
| `backend/` | FastAPI + AI + DATEV export |
| `lab-web/` | Lab dashboard (Week 4 scaffold) |
| `references/` | Logo, shapes, DATEV, future PLY/shades |
| `docs/` | Spec helpers, GDPR, weekly plan |

## Next work

Week 2: camera + scan upload UI + offline sync (`mobile/lib/features/camera|scans` + `core/offline`).
