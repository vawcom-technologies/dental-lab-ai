-- Lab review workspace on the case (docs/roadmap.md → Lab suggestions).
--   feedback:    {scan|shade|smile: {status: ok|needs_work, note}} — the lab's
--                draft verdicts while reviewing; cleared when it approves/rejects.
--   suggestions: {scan|shade|smile: {...}} — changes the lab proposes. They never
--                touch the dentist's items until the owning dentist accepts them.
ALTER TABLE public.patients
  ADD COLUMN IF NOT EXISTS lab_review JSONB NOT NULL DEFAULT '{}'::jsonb;
