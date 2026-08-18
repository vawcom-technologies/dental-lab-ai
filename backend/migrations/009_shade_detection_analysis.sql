-- Persist Accept AI / override results on a shade detection (GDPR patients
-- have no integer Case). Idempotent — safe to re-run in Supabase SQL Editor.

ALTER TABLE public.shade_detections
  ADD COLUMN IF NOT EXISTS analysis JSONB;
