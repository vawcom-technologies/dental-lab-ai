-- Profile photos. Path the app loads with its login token:
-- /api/media/avatars/{name}; the name changes whenever the photo does.
-- Idempotent — safe to re-run in Supabase SQL Editor.

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS avatar_url TEXT;
