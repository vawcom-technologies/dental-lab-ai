-- Scans are library uploads until the dentist saves them onto the case.
-- Shade Accept/Save and smile Save already attach those items; scans need
-- an explicit "Save to case" (on_case = true).
--
-- Default true so existing rows keep counting as case items. New uploads
-- set on_case=false explicitly in the API.
ALTER TABLE public.patient_scans
  ADD COLUMN IF NOT EXISTS on_case BOOLEAN NOT NULL DEFAULT true;

COMMENT ON COLUMN public.patient_scans.on_case IS
  'True when the dentist saved this scan onto the patient case for lab review.';
