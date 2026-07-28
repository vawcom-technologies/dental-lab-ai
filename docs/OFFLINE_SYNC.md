# Offline sync architecture (Week 2)

## Flow

```
Chairside capture
   │
   ├─► LocalEncryptedStore (AES)  — always write first
   │
   ├─ online? ──yes──► API upload (photos/scans)
   │
   └─ no / fail ──► SyncQueue (SharedPreferences)
                         │
                         └─ flush() when connectivity returns
```

## Files

| File | Role |
|------|------|
| `mobile/lib/core/offline/sync_queue.dart` | AES cache + queue persistence |
| `mobile/lib/core/offline/sync_service.dart` | capture + flush orchestration |
| `backend/app/core/encryption.py` | Fernet AES at rest on server |
| `backend/app/storage/local.py` | writes `.enc` files |

## Notes

- Queue ops: `photoUpload`, `scanUpload` (patient create reserved)
- Dev key is hardcoded for Week 2 — replace with secure device keystore before real PHI
- Drift/SQLite full local DB can replace SharedPreferences in Week 3+ if needed
