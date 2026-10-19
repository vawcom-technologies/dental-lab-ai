-- Phase 3: sharing tickets decided by the lab, transfers between labs.
-- Idempotent — safe to re-run in Supabase SQL Editor.

-- A pending share with a dentist in the same lab waits on that lab.
ALTER TABLE public.patient_access
  ADD COLUMN IF NOT EXISTS ticket_lab_id UUID REFERENCES public.profiles (id) ON DELETE SET NULL;

-- share:    a dentist shares with another lab; their lab forwards, the other lab
--           accepts and picks a dentist; both dentists keep access.
-- handover: a lab (or the admin) sends a patient to a lab, which picks the owner.
CREATE TABLE IF NOT EXISTS public.lab_transfers (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  kind          TEXT NOT NULL CHECK (kind IN ('share', 'handover')),
  patient_id    UUID NOT NULL REFERENCES public.patients (id) ON DELETE CASCADE,
  from_lab_id   UUID REFERENCES public.profiles (id) ON DELETE SET NULL,
  to_lab_id     UUID NOT NULL REFERENCES public.profiles (id) ON DELETE CASCADE,
  requested_by  UUID REFERENCES public.profiles (id) ON DELETE SET NULL,
  status        TEXT NOT NULL CHECK (status IN (
                  'awaiting_sender', 'awaiting_recipient', 'accepted', 'rejected', 'cancelled')),
  dentist_id    UUID REFERENCES public.profiles (id) ON DELETE SET NULL,  -- chosen by the receiving lab
  reason        TEXT,
  decided_by    UUID REFERENCES public.profiles (id) ON DELETE SET NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- One open transfer per patient and receiving lab.
CREATE UNIQUE INDEX IF NOT EXISTS uq_lab_transfers_open
  ON public.lab_transfers (patient_id, to_lab_id)
  WHERE status IN ('awaiting_sender', 'awaiting_recipient');

ALTER TABLE public.lab_transfers ENABLE ROW LEVEL SECURITY;
