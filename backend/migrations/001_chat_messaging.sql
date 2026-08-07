-- Idempotent migration: 1-to-1 real-time messaging
-- Run in Supabase SQL Editor (or via CLI migration).

-- ── conversations ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.conversations (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_a     UUID NOT NULL REFERENCES public.profiles (id) ON DELETE CASCADE,
  user_b     UUID NOT NULL REFERENCES public.profiles (id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT conversations_canonical_order CHECK (user_a < user_b),
  CONSTRAINT conversations_unique_pair UNIQUE (user_a, user_b)
);

CREATE INDEX IF NOT EXISTS idx_conversations_user_a
  ON public.conversations (user_a, updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_conversations_user_b
  ON public.conversations (user_b, updated_at DESC);

-- ── messages ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.messages (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id     UUID NOT NULL REFERENCES public.conversations (id) ON DELETE CASCADE,
  sender_id           UUID NOT NULL REFERENCES public.profiles (id) ON DELETE CASCADE,
  content             TEXT NOT NULL DEFAULT '',
  media_url           TEXT NULL,
  media_type          TEXT NULL,
  duration_seconds    NUMERIC NULL,
  reply_to_message_id UUID NULL REFERENCES public.messages (id) ON DELETE SET NULL,
  read_at             TIMESTAMPTZ NULL,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_messages_conversation
  ON public.messages (conversation_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_messages_unread
  ON public.messages (conversation_id, sender_id)
  WHERE read_at IS NULL;

-- ── Row Level Security ───────────────────────────────────────────────────────
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

-- Conversations: participants can SELECT
DROP POLICY IF EXISTS conversations_select_participants ON public.conversations;
CREATE POLICY conversations_select_participants
  ON public.conversations
  FOR SELECT
  TO authenticated
  USING (auth.uid() = user_a OR auth.uid() = user_b);

-- Messages: only if the user is a participant of the parent conversation
DROP POLICY IF EXISTS messages_select_participants ON public.messages;
CREATE POLICY messages_select_participants
  ON public.messages
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.conversations c
      WHERE c.id = messages.conversation_id
        AND (c.user_a = auth.uid() OR c.user_b = auth.uid())
    )
  );

-- Optional: allow authenticated inserts for their own messages / rooms
-- (backend uses service-role; these policies help if clients talk to PostgREST directly)
DROP POLICY IF EXISTS conversations_insert_participants ON public.conversations;
CREATE POLICY conversations_insert_participants
  ON public.conversations
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_a OR auth.uid() = user_b);

DROP POLICY IF EXISTS messages_insert_own ON public.messages;
CREATE POLICY messages_insert_own
  ON public.messages
  FOR INSERT
  TO authenticated
  WITH CHECK (
    sender_id = auth.uid()
    AND EXISTS (
      SELECT 1
      FROM public.conversations c
      WHERE c.id = conversation_id
        AND (c.user_a = auth.uid() OR c.user_b = auth.uid())
    )
  );

DROP POLICY IF EXISTS messages_update_read ON public.messages;
CREATE POLICY messages_update_read
  ON public.messages
  FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.conversations c
      WHERE c.id = messages.conversation_id
        AND (c.user_a = auth.uid() OR c.user_b = auth.uid())
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.conversations c
      WHERE c.id = messages.conversation_id
        AND (c.user_a = auth.uid() OR c.user_b = auth.uid())
    )
  );
