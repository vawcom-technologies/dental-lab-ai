# GDPR checklist (Germany / dental PHI)

- [ ] Encryption at rest (AES-256) for scans/photos/XML — stub in `core/encryption.py`  
- [ ] TLS in transit (HTTPS) in production  
- [ ] Per-dentist access scoping (enforced on patients; extend to cases)  
- [ ] Activity log on sensitive actions (partially wired)  
- [ ] Regular backups documented  
- [ ] **EU-region** Postgres + object storage confirmed  
- [ ] Data processing agreement / retention policy with client  
- [ ] **Sub-processor DPAs** signed and listed in the privacy notice: OpenAI (interpreter speech-to-text, translation and cloud voices send what patients say), Roboflow (shade photo segmentation), Resend (emails), Supabase, Cloudflare R2, Railway  
- [ ] Migration `026_lock_down_direct_access.sql` applied in Supabase (RLS on all tables, no direct user writes, profiles read-own only)  
- [ ] Right to access / deletion workflow  
- [ ] No real patient data in non-EU or local demo DBs shared outside team  

Do not store real PHI until EU hosting + encryption are live.
