-- Extend messages for chat media (voice / image / document)
ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS media_url TEXT DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS media_type TEXT DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS duration_seconds NUMERIC DEFAULT NULL;

-- Optional check: media_type values when present
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'messages_media_type_check'
  ) THEN
    ALTER TABLE public.messages
      ADD CONSTRAINT messages_media_type_check
      CHECK (
        media_type IS NULL
        OR media_type IN ('voice', 'image', 'document')
      );
  END IF;
END $$;
