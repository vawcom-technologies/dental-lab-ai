-- Saved Smile Preview = the photo with overlays (file_key, what the lab sees)
-- + the photo without overlays (base_file_key) + where each shape sat
-- (overlay) so the doctor can reopen and keep editing.
-- Idempotent — safe to re-run in Supabase SQL Editor.

ALTER TABLE public.smile_previews
  ADD COLUMN IF NOT EXISTS base_file_key TEXT,
  ADD COLUMN IF NOT EXISTS overlay JSONB;
