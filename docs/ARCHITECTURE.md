# Architecture

```
┌──────────────────────┐     JWT / REST      ┌─────────────────────────┐
│  Flutter (iPad)      │◄───────────────────►│  FastAPI backend        │
│  dentist app         │                     │  + AI modules           │
│  offline Drift cache │                     │  SQLite→Postgres (EU)   │
└──────────────────────┘                     └───────────┬─────────────┘
                                                         │
┌──────────────────────┐                                 │
│  lab-web (Week 4)    │◄────────────────────────────────┤
│  role=lab            │                                 │
└──────────────────────┘                     ┌───────────▼─────────────┐
                                             │ Encrypted file storage  │
                                             │ scans / photos / xml    │
                                             └─────────────────────────┘
```

## API surface (current)

| Method | Path | Notes |
|--------|------|-------|
| GET | `/health` | |
| POST | `/api/auth/login` | form: username, password |
| GET | `/api/auth/me` | |
| CRUD | `/api/patients` | dentist-scoped |
| CRUD | `/api/cases` | |
| POST/GET | `/api/cases/{id}/scans` | PLY + validation |
| POST/GET | `/api/cases/{id}/photos` | angle form field |
| GET/POST | `/api/cases/{id}/messages` | chat scaffold |
| POST | `/api/cases/{id}/shade` | persist selection |
| POST | `/api/cases/{id}/shape` | persist overlay |
| GET | `/api/exports/{patient_id}/datev.xml` | DATEV-like |
| POST | `/api/ai/shade/suggest` | POC |
| POST | `/api/ai/scan/validate` | POC |

Full folder map: [`STRUCTURE.md`](../STRUCTURE.md).
