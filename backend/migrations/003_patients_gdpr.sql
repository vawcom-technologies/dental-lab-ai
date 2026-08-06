-- GDPR patient management: ownership, shared access, encrypted notes, audit trail
-- Idempotent — safe to re-run in Supabase SQL Editor.

-- ── patients ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.patients (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_by       UUID NOT NULL REFERENCES public.profiles (id) ON DELETE RESTRICT,
  first_name       TEXT NOT NULL,
  last_name        TEXT NOT NULL,
  date_of_birth    DATE NOT NULL,
  address          TEXT NOT NULL DEFAULT '',
  phone            TEXT NOT NULL DEFAULT '',
  health_insurance TEXT NOT NULL DEFAULT '',
  deleted          BOOLEAN NOT NULL DEFAULT FALSE,
  deleted_at       TIMESTAMPTZ NULL,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_patients_created_by
  ON public.patients (created_by)
  WHERE deleted = FALSE;

CREATE INDEX IF NOT EXISTS idx_patients_name
  ON public.patients (last_name, first_name);

-- ── patient_access (delegation / sharing) ────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.patient_access (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id UUID NOT NULL REFERENCES public.patients (id) ON DELETE CASCADE,
  user_id    UUID NOT NULL REFERENCES public.profiles (id) ON DELETE CASCADE,
  granted_by UUID NOT NULL REFERENCES public.profiles (id) ON DELETE RESTRICT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT patient_access_unique UNIQUE (patient_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_patient_access_user
  ON public.patient_access (user_id);

CREATE INDEX IF NOT EXISTS idx_patient_access_patient
  ON public.patient_access (patient_id);

-- ── patient_notes (ciphertext only — never store plaintext) ──────────────────
CREATE TABLE IF NOT EXISTS public.patient_notes (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id      UUID NOT NULL REFERENCES public.patients (id) ON DELETE CASCADE,
  author_id       UUID NOT NULL REFERENCES public.profiles (id) ON DELETE RESTRICT,
  note_ciphertext TEXT NOT NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_patient_notes_patient
  ON public.patient_notes (patient_id, created_at DESC);

-- ── patient_audit_logs (GDPR accountability) ─────────────────────────────────
CREATE TABLE IF NOT EXISTS public.patient_audit_logs (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id UUID NULL REFERENCES public.patients (id) ON DELETE SET NULL,
  actor_id   UUID NOT NULL REFERENCES public.profiles (id) ON DELETE RESTRICT,
  action     TEXT NOT NULL,
  details    JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_patient_audit_patient
  ON public.patient_audit_logs (patient_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_patient_audit_actor
  ON public.patient_audit_logs (actor_id, created_at DESC);

-- ── RLS (backend uses service-role; policies protect direct PostgREST access) ─
ALTER TABLE public.patients ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.patient_access ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.patient_notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.patient_audit_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS patients_select_own_or_shared ON public.patients;
CREATE POLICY patients_select_own_or_shared
  ON public.patients
  FOR SELECT
  TO authenticated
  USING (
    created_by = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.patient_access a
      WHERE a.patient_id = patients.id AND a.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS patients_insert_authenticated ON public.patients;
CREATE POLICY patients_insert_authenticated
  ON public.patients
  FOR INSERT
  TO authenticated
  WITH CHECK (created_by = auth.uid());

DROP POLICY IF EXISTS patients_update_owner ON public.patients;
CREATE POLICY patients_update_owner
  ON public.patients
  FOR UPDATE
  TO authenticated
  USING (created_by = auth.uid())
  WITH CHECK (created_by = auth.uid());

DROP POLICY IF EXISTS patients_delete_owner ON public.patients;
CREATE POLICY patients_delete_owner
  ON public.patients
  FOR DELETE
  TO authenticated
  USING (created_by = auth.uid());
