-- Require non-null patient email (GDPR contact field)
-- Idempotent — safe to re-run in Supabase SQL Editor.

ALTER TABLE public.patients
  ADD COLUMN IF NOT EXISTS email TEXT;

-- Backfill legacy rows so NOT NULL can be applied
UPDATE public.patients
SET email = 'legacy+' || id::text || '@patients.local'
WHERE email IS NULL OR btrim(email) = '';

ALTER TABLE public.patients
  ALTER COLUMN email SET NOT NULL;

CREATE INDEX IF NOT EXISTS idx_patients_email
  ON public.patients (email)
  WHERE deleted = FALSE;
