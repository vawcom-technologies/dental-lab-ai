-- Allow chat video messages (original-quality R2 objects, max 200 MB).
ALTER TABLE public.messages DROP CONSTRAINT IF EXISTS messages_media_type_check;

ALTER TABLE public.messages
  ADD CONSTRAINT messages_media_type_check
  CHECK (
    media_type IS NULL
    OR media_type IN ('voice', 'image', 'document', 'video')
  );
