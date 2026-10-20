-- Optional lab membership: defer joining; bring patients on join/transfer;
-- dentist-initiated lab-to-lab transfer approved by the current lab.

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS lab_join_deferred_at TIMESTAMPTZ;

ALTER TABLE public.lab_requests
  ADD COLUMN IF NOT EXISTS to_lab_id UUID REFERENCES public.profiles (id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS patient_ids UUID[] NOT NULL DEFAULT '{}';

-- Recreate kind check to allow 'transfer'.
ALTER TABLE public.lab_requests DROP CONSTRAINT IF EXISTS lab_requests_kind_check;
ALTER TABLE public.lab_requests
  ADD CONSTRAINT lab_requests_kind_check
  CHECK (kind IN ('join', 'remove', 'transfer'));

COMMENT ON COLUMN public.profiles.lab_join_deferred_at IS
  'Dentist chose Request later on the lab picker; app unlocks without a lab.';
COMMENT ON COLUMN public.lab_requests.to_lab_id IS
  'Destination lab for kind=transfer (current lab is lab_id).';
COMMENT ON COLUMN public.lab_requests.patient_ids IS
  'Patients to auto-share with the destination lab on approve.';
