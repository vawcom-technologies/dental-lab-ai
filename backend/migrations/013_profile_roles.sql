-- Align public.profiles.role with Flutter registration: dentist | laboratory | admin.
-- Legacy clinic / lab values become laboratory.

UPDATE public.profiles
SET role = 'laboratory'
WHERE lower(trim(role)) IN ('clinic', 'lab');

UPDATE public.profiles
SET role = 'dentist'
WHERE lower(trim(role)) = 'dentist';

COMMENT ON COLUMN public.profiles.role IS 'dentist | laboratory | admin';
