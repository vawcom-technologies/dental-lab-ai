# Dental Lab AI App — Project Specification

**Client:** Erlan Djaniev (Elite Dent, Germany)  
**Freelancer:** Muhammad Babar (Upwork)  
**Contract:** Upwork hourly · $25/hr · 35 hr/week · 4–5 weeks (120–150 hrs)  
**Platform:** iPad 11 (primary), offline-capable  
**Status:** Week 1 ✅ · Week 2 ✅  
**Brand:** Elite Dent (`references/logo.jpg`)  
**Structure map:** [`STRUCTURE.md`](STRUCTURE.md)

---

## Status snapshot

| Area | Status |
|------|--------|
| Spec + branding directions | Done |
| Auth + patient CRUD | Done |
| Full DB schema (all §5 tables) | Done |
| Cases / scans / photos / messages APIs | Scaffolded |
| Shade + scan-quality AI POCs | Done (heuristic) |
| Tooth shape library (20 smiles) | Saved + Smile Preview UI |
| VITA Classical A1–D4 guide | Saved + Shade Detection UI |
| DATEV XML skeleton | Done (demo schema) |
| Camera / offline / chat UI | Camera + offline sync done (Week 2); chat UI scaffold |
| Lab web / marketing website | Deferred (Week 4 / client) |

---

## 1. Project Summary

Dentists send intraoral scans (~30 km to lab) plus verbal/written shade & shape decisions.

**Problems:** bad scans → patient returns; shade/shape disputes (no structured record).

**Goal — iPad app that:**

1. Validates scan quality before the patient leaves  
2. Previews tooth shape + color on patient photo  
3. Detects tooth shade (AI + **mandatory** manual override)  
4. Detects scan body diameter → tooth/manufacturer  
5. GDPR-compliant encrypted records; XML export (DATEV / “Datext”)  
6. Chat (incl. voice) dentist ↔ lab  
7. Companion website (scope TBD)

---

## 2. Confirmed Requirements (Jul 21–22)

### 2.1 Users
- Tablet: dentists only, own login  
- Lab: remote monitor → web dashboard from day one  

### 2.2 Patient data (GDPR — Germany)
Fields: first/last name, DOB, address, phone, notes, health insurance.  
Encrypt at rest + in transit; backups; access control; activity log.

### 2.3 Scanning
Medit · **PLY** · flag grainy/distorted · prompt rescan  

### 2.4 Shape preview
Client library · overlay · assume resize/rotate/reposition  

### 2.5 Shade
VITA Classical A1–D4 · AI suggest · **manual override required**  

### 2.6 Photos
≤10 · frontal / left / right · full resolution  

### 2.7 Communication
Per-patient chat · voice · files · notifications · read status  

### 2.8 XML
DATEV-like sample in `references/datev/` (spec said Datext). Official XSD still pending.

### 2.9 Hardware
iPad 11 · offline-first sync  

### 2.10 Extra AI
Scan body diameter · language translation (scope TBD)  

### 2.11 Branding
Logo colors · 3 directions in `docs/BRANDING_DIRECTIONS.md` (default A)  

### 2.12 Website
Scope deferred — do not build until confirmed  

---

## 3. Open questions

See `docs/CLIENT_FOLLOWUP_WEEK1.md`.

---

## 4. Roles

| Role | Access |
|------|--------|
| Dentist | iPad — own patients |
| Lab | Web — all cases, chat, XML, logs |
| Admin | Future |

---

## 5. Data model

Implemented in `backend/app/models/`:

`User`, `Patient`, `Case`, `Scan`, `Photo`, `ShadeSelection`, `ShapeSelection`, `ScanBodyDetection`, `Message`, `Notification`, `XMLExport`, `ActivityLog`

---

## 6. Tech stack

| Layer | Choice |
|-------|--------|
| Tablet | Flutter |
| Backend | FastAPI |
| DB | SQLite (dev) → PostgreSQL EU (prod) |
| Files | `backend/data/uploads` → S3/Supabase EU |
| Auth | JWT |
| Offline | Drift/SQLite + sync queue |
| AI | OpenCV / color pipeline / LLM translate |

---

## 7. AI priority

1. Scan quality → 2. Shade → 4. Scan body → 3. Shape overlay → 5. Translate  

---

## 8. Weekly plan

See `docs/WEEKLY_PLAN.md`.

---

## 9. Deliverables checklist

- [ ] Branding approved  
- [x] Dentist login + patient CRUD  
- [ ] Camera (3 angles, ≤10)  
- [ ] Scan upload + AI validation + rescan  
- [ ] Shade AI + override  
- [ ] Shape overlay  
- [ ] Scan body matching  
- [ ] Chat + notifications  
- [ ] Encrypted DATEV/XML (official)  
- [ ] Offline + sync  
- [ ] Lab dashboard  
- [ ] Website (pending)  
- [ ] GDPR review (EU hosting)  
- [ ] iPad 11 testing  
- [ ] Handover docs  

---

## 10. Risks

| Risk | Mitigation |
|------|------------|
| No official DATEV XSD | Keep skeleton; don’t finalize |
| AI accuracy | POCs early; need real PLY/shade refs |
| Website undefined | Week 4 flexible |
| No official scan-body table | Week 3 ships provisional table + UI; swap when client sends |
| GDPR residency | EU hosting before real PHI |
