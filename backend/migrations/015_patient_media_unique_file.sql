-- One record per image per patient. The backend already reuses a record when
-- the same image is saved again; this makes the database enforce it.
-- Run AFTER scripts/cleanup_patient_media.py --apply (fails on duplicates).
-- Idempotent — safe to re-run in Supabase SQL Editor.

CREATE UNIQUE INDEX IF NOT EXISTS shade_detections_patient_file_key
  ON public.shade_detections (patient_id, file_key);
CREATE UNIQUE INDEX IF NOT EXISTS smile_previews_patient_file_key
  ON public.smile_previews (patient_id, file_key);
CREATE UNIQUE INDEX IF NOT EXISTS patient_scans_patient_file_key
  ON public.patient_scans (patient_id, file_key);
