-- Labs, admin approval, reject list, case history (docs/roadmap.md, Phase 0/1).
-- Idempotent — safe to re-run in Supabase SQL Editor.

-- ── profiles: lab membership, hide settings, signup date, tombstones ─────────
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS lab_id            UUID REFERENCES public.profiles (id) ON DELETE SET NULL,
  -- Lab settings (set from the lab side in Phase 3; both off by default)
  ADD COLUMN IF NOT EXISTS hidden_from_labs  BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS hide_dentists     BOOLEAN NOT NULL DEFAULT FALSE,
  -- Why a dentist has no lab: no_lab | removed | lab_deleted (NULL while in a lab)
  ADD COLUMN IF NOT EXISTS unassigned_reason TEXT,
  ADD COLUMN IF NOT EXISTS unassigned_at     TIMESTAMPTZ,
  -- Set when an account is permanently deleted: personal details cleared, row
  -- kept because patients and uploads still point at it.
  ADD COLUMN IF NOT EXISTS anonymized_at     TIMESTAMPTZ;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'profiles_unassigned_reason_check') THEN
    ALTER TABLE public.profiles
      ADD CONSTRAINT profiles_unassigned_reason_check
      CHECK (unassigned_reason IN ('no_lab', 'removed', 'lab_deleted'));
  END IF;
END $$;

-- Real signup dates for existing rows (the column default stamped them "now").
UPDATE public.profiles p
SET created_at = u.created_at
FROM auth.users u
WHERE u.id = p.id AND p.created_at > u.created_at;

-- Existing approved dentists have no lab yet.
UPDATE public.profiles
SET unassigned_reason = 'no_lab', unassigned_at = now()
WHERE role = 'dentist' AND lab_id IS NULL AND unassigned_reason IS NULL;

-- ── reject list ──────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.rejected_signups (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email        TEXT NOT NULL UNIQUE,  -- lowercased
  name         TEXT,
  role         TEXT,
  reason       TEXT,
  rejected_by  UUID REFERENCES public.profiles (id) ON DELETE SET NULL,
  rejected_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── lab requests: dentist asks to join / lab asks to remove a dentist ────────
CREATE TABLE IF NOT EXISTS public.lab_requests (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  kind        TEXT NOT NULL CHECK (kind IN ('join', 'remove')),
  lab_id      UUID NOT NULL REFERENCES public.profiles (id) ON DELETE CASCADE,
  dentist_id  UUID NOT NULL REFERENCES public.profiles (id) ON DELETE CASCADE,
  reason      TEXT,
  status      TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  decided_by  UUID REFERENCES public.profiles (id) ON DELETE SET NULL,
  decided_at  TIMESTAMPTZ,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- One pending request of each kind per dentist.
CREATE UNIQUE INDEX IF NOT EXISTS uq_lab_requests_pending
  ON public.lab_requests (dentist_id, kind)
  WHERE status = 'pending';

-- ── patients: auto-submit switch, unassigned / waiting for a lab ─────────────
ALTER TABLE public.patients
  ADD COLUMN IF NOT EXISTS auto_submit     BOOLEAN NOT NULL DEFAULT TRUE,
  -- Set when the owner was deleted, or while waiting for a lab to pick a dentist.
  ADD COLUMN IF NOT EXISTS unassigned_at   TIMESTAMPTZ,
  -- The lab that has to choose a dentist ("waiting for lab").
  ADD COLUMN IF NOT EXISTS waiting_lab_id  UUID REFERENCES public.profiles (id) ON DELETE SET NULL;

-- ── case history ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.case_events (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id   UUID NOT NULL REFERENCES public.patients (id) ON DELETE CASCADE,
  actor_id     UUID REFERENCES public.profiles (id) ON DELETE SET NULL,
  -- created | submitted | approved | rejected | updated | reassigned | admin_override | lab_left
  type         TEXT NOT NULL,
  from_status  TEXT,
  to_status    TEXT,
  remarks      TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_case_events_patient
  ON public.case_events (patient_id, created_at DESC);

-- Backend uses the service role; no direct PostgREST access to these.
ALTER TABLE public.rejected_signups ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lab_requests     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.case_events      ENABLE ROW LEVEL SECURITY;
