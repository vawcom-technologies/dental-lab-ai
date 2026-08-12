-- Patient workflow status (pending → in_progress → in_review → completed / rejected)
-- Idempotent — safe to re-run in Supabase SQL Editor.

ALTER TABLE public.patients
  ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'pending';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'patients_status_check'
  ) THEN
    ALTER TABLE public.patients
      ADD CONSTRAINT patients_status_check
      CHECK (status IN (
        'pending',
        'in_progress',
        'in_review',
        'completed',
        'rejected'
      ));
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_patients_status
  ON public.patients (status)
  WHERE deleted = FALSE;

UPDATE public.patients
SET status = 'pending'
WHERE status IS NULL OR status = '';
