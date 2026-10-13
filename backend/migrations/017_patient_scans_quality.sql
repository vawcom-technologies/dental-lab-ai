-- Scan quality result, computed once by the server and reused on every view.
-- Shape: validate_scan_bytes() output plus "v" (QUALITY_VERSION); rows with an
-- older "v" (or NULL) are re-validated on demand by POST /api/scans/{id}/validate.
-- Idempotent — safe to re-run in Supabase SQL Editor.
ALTER TABLE public.patient_scans
  ADD COLUMN IF NOT EXISTS quality JSONB;
