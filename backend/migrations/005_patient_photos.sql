-- Patient clinical photos (chairside camera) — metadata in Postgres, bytes in R2.
-- Idempotent — safe to re-run in Supabase SQL Editor.

CREATE TABLE IF NOT EXISTS public.patient_photos (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id   UUID NOT NULL REFERENCES public.patients (id) ON DELETE CASCADE,
  uploaded_by  UUID NOT NULL REFERENCES public.profiles (id) ON DELETE RESTRICT,
  angle        TEXT NOT NULL
               CHECK (angle IN ('frontal', 'left', 'right', 'other')),
  filename     TEXT NOT NULL DEFAULT 'photo.jpg',
  file_url     TEXT NOT NULL,
  byte_size    INTEGER NOT NULL DEFAULT 0,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_patient_photos_patient
  ON public.patient_photos (patient_id, created_at DESC);

ALTER TABLE public.patient_photos ENABLE ROW LEVEL SECURITY;
