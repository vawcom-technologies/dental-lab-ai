-- N-tier patient access: pending owner approval workflow
-- Idempotent — safe to re-run in Supabase SQL Editor.

-- ── columns ──────────────────────────────────────────────────────────────────
ALTER TABLE public.patient_access
  ADD COLUMN IF NOT EXISTS requested_by UUID REFERENCES public.profiles (id) ON DELETE RESTRICT;

ALTER TABLE public.patient_access
  ADD COLUMN IF NOT EXISTS approved_by UUID REFERENCES public.profiles (id) ON DELETE RESTRICT;

ALTER TABLE public.patient_access
  ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'approved';

-- Backfill legacy rows (granted before approval workflow existed)
UPDATE public.patient_access
SET
  requested_by = COALESCE(requested_by, granted_by),
  approved_by  = COALESCE(approved_by, granted_by),
  status       = CASE
                   WHEN status IS NULL OR btrim(status) = '' THEN 'approved'
                   ELSE status
                 END
WHERE requested_by IS NULL
   OR approved_by IS NULL
   OR status IS NULL
   OR btrim(status) = '';

-- Tighten status domain
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'patient_access_status_check'
      AND conrelid = 'public.patient_access'::regclass
  ) THEN
    ALTER TABLE public.patient_access
      ADD CONSTRAINT patient_access_status_check
      CHECK (status IN ('pending', 'approved', 'rejected'));
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_patient_access_status
  ON public.patient_access (status);

CREATE INDEX IF NOT EXISTS idx_patient_access_pending_patient
  ON public.patient_access (patient_id)
  WHERE status = 'pending';

-- ── RLS: only approved shares grant SELECT on patients ───────────────────────
DROP POLICY IF EXISTS patients_select_own_or_shared ON public.patients;
CREATE POLICY patients_select_own_or_shared
  ON public.patients
  FOR SELECT
  TO authenticated
  USING (
    created_by = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.patient_access a
      WHERE a.patient_id = patients.id
        AND a.user_id = auth.uid()
        AND a.status = 'approved'
    )
  );
