-- Change one key of patients.lab_review in place, so concurrent lab actions
-- (a suggestion save and a feedback tap) can't overwrite each other.
--   p_path  e.g. {suggestions,shade} | {feedback,scan} | {dentist_updated}
--   p_value NULL removes the key.
--   p_bump  also moves updated_at (the lab's queue sorts by it).
-- Idempotent — safe to re-run in Supabase SQL Editor.
CREATE OR REPLACE FUNCTION public.lab_review_set(
  p_id UUID, p_path TEXT[], p_value JSONB, p_bump BOOLEAN DEFAULT FALSE
) RETURNS JSONB
LANGUAGE sql AS $$
  UPDATE public.patients
     SET lab_review = CASE
           WHEN p_value IS NULL THEN COALESCE(lab_review, '{}'::jsonb) #- p_path
           -- jsonb_set only creates the last key: make sure the parent object exists.
           WHEN array_length(p_path, 1) = 2 THEN jsonb_set(
             COALESCE(lab_review, '{}'::jsonb)
               || jsonb_build_object(p_path[1], COALESCE(lab_review -> p_path[1], '{}'::jsonb)),
             p_path, p_value, TRUE)
           ELSE jsonb_set(COALESCE(lab_review, '{}'::jsonb), p_path, p_value, TRUE)
         END,
         updated_at = CASE WHEN p_bump THEN now() ELSE updated_at END
   WHERE id = p_id
  RETURNING lab_review;
$$;
