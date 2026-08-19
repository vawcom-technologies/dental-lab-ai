-- Structured patient @mentions on chat messages.
-- Display text stays in `content` (e.g. "@Jane Doe"); IDs live here so
-- taps can open the patient profile even if the name is edited later.
ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS mentioned_patients JSONB NOT NULL DEFAULT '[]'::jsonb;

COMMENT ON COLUMN public.messages.mentioned_patients IS
  'Array of {id, label} patient @mentions referenced in content';
