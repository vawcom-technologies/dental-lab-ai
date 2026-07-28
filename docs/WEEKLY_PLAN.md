# Weekly development plan

Aligned with contract (≤35 hr/week, ~4–5 weeks).

## Week 1 — Foundations + AI POC ✅

- [x] Spec + open questions draft (`docs/CLIENT_FOLLOWUP_WEEK1.md`)
- [x] Branding directions A/B/C + Pro UI from Figma
- [x] Repo architecture (`STRUCTURE.md`, `docs/ARCHITECTURE.md`)
- [x] Auth + patient CRUD
- [x] Shade POC (API + UI wired to `/api/ai/shade/suggest`)
- [x] Scan-quality POC (API + Scans UI)
- [ ] Client answers blockers (still waiting)

## Week 2 — Core data capture ✅

- [x] Camera (frontal/left/right, ≤10, full-res preference) — `features/camera/camera_page.dart`
- [x] Scan upload + encrypted storage (client AES cache + server Fernet `.enc`)
- [x] Offline queue/sync architecture — `core/offline/` + `docs/OFFLINE_SYNC.md`
- [x] XML/DATEV skeleton — `GET /api/exports/{id}/datev.xml` + Week 2 risk flag to client

## Week 3 — AI integration ✅

- [x] Finalize scan validation against available PLYs (`references/scans/` fixtures; real Medit samples still pending from client)
- [x] Shade + override persistence on cases (`POST /api/cases/{id}/shade` + Shade UI)
- [x] Shape overlay on patient photo (pan / resize / rotate → `POST /api/cases/{id}/shape`)
- [x] Scan body diameter scaffold (provisional table + detect/match UI; swap when client sends ground truth)

## Week 4 — Communication + lab web

- [ ] Chat (text/voice/image) + notifications + read receipts  
- [ ] Lab dashboard  
- [ ] Website only if scoped  

## Week 5 — Hardening

- [ ] iPad 11 E2E  
- [ ] Performance / battery  
- [ ] GDPR checklist  
- [ ] Handover  

**Where to work next:** Week 4 communication + lab web. Client still owes real Medit PLYs + official scan-body diameter table + DATEV XSD/Beraternummer.
