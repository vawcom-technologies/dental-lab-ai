-- Human-facing staff IDs: dentists D-01…, labs L-01…
-- Stored as public_number; prefix comes from role. Idempotent.

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS public_number INTEGER;

-- One sequence per role family (dentists vs labs).
CREATE UNIQUE INDEX IF NOT EXISTS profiles_dentist_public_number_uidx
  ON public.profiles (public_number)
  WHERE role = 'dentist' AND public_number IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS profiles_lab_public_number_uidx
  ON public.profiles (public_number)
  WHERE role IN ('laboratory', 'lab', 'clinic') AND public_number IS NOT NULL;

-- Backfill existing dentists (oldest first).
WITH ranked AS (
  SELECT
    id,
    ROW_NUMBER() OVER (
      ORDER BY created_at NULLS LAST, updated_at NULLS LAST, id
    ) AS n
  FROM public.profiles
  WHERE role = 'dentist'
    AND public_number IS NULL
    AND COALESCE(deleted, false) = false
)
UPDATE public.profiles p
SET public_number = ranked.n
FROM ranked
WHERE p.id = ranked.id;

-- Backfill existing labs (oldest first).
WITH ranked AS (
  SELECT
    id,
    ROW_NUMBER() OVER (
      ORDER BY created_at NULLS LAST, updated_at NULLS LAST, id
    ) AS n
  FROM public.profiles
  WHERE role IN ('laboratory', 'lab', 'clinic')
    AND public_number IS NULL
    AND COALESCE(deleted, false) = false
)
UPDATE public.profiles p
SET public_number = ranked.n
FROM ranked
WHERE p.id = ranked.id;
