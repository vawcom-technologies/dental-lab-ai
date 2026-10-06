-- Scan inbox: files uploaded from a PC web page, waiting to be assigned to a
-- patient on the iPad. Objects live under {user}/ in the private bucket
-- R2_SCAN_INBOX_BUCKET, whose lifecycle rule deletes them after 30 days.
-- Idempotent — safe to re-run in Supabase SQL Editor.

CREATE TABLE IF NOT EXISTS public.scan_inbox (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  uploaded_by  UUID NOT NULL REFERENCES public.profiles (id) ON DELETE CASCADE,
  file_key     TEXT NOT NULL,
  file_name    TEXT NOT NULL DEFAULT '',
  format       TEXT NOT NULL DEFAULT '',
  byte_size    BIGINT NOT NULL DEFAULT 0,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_scan_inbox_user
  ON public.scan_inbox (uploaded_by, created_at DESC);

-- The backend uses the service role; no direct client access.
ALTER TABLE public.scan_inbox ENABLE ROW LEVEL SECURITY;
