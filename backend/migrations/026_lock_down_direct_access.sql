-- Lock down direct database access (security review, Oct 2026).
--
-- The Supabase anon key is public (forgot-password page), so any signed-in
-- user can call PostgREST directly with their own JWT. The app never does:
-- every read and write goes through the backend, which uses the service role
-- (it bypasses RLS) and enforces access, case flow and audit logging.
-- So: RLS on everywhere, no direct writes for users, reads only where a
-- policy already scopes them to the user.

-- 1. Tables created without RLS.
ALTER TABLE public.case_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lab_requests ENABLE ROW LEVEL SECURITY;

-- 2. Direct writes would skip the backend's checks (case flow, owner-only
--    edits, GDPR audit log, message integrity).
DROP POLICY IF EXISTS messages_update_read ON public.messages;
DROP POLICY IF EXISTS messages_insert_own ON public.messages;
DROP POLICY IF EXISTS conversations_insert_participants ON public.conversations;
DROP POLICY IF EXISTS patients_insert_authenticated ON public.patients;
DROP POLICY IF EXISTS patients_update_owner ON public.patients;
DROP POLICY IF EXISTS patients_delete_owner ON public.patients;
DROP POLICY IF EXISTS notifications_update_own ON public.notifications;
DROP POLICY IF EXISTS appointments_insert_authenticated ON public.appointments;
DROP POLICY IF EXISTS appointments_update_authenticated ON public.appointments;
DROP POLICY IF EXISTS appointments_delete_authenticated ON public.appointments;
DROP POLICY IF EXISTS patient_access_request_shared ON public.patient_access;
DROP POLICY IF EXISTS patient_access_manage_owner ON public.patient_access;
DROP POLICY IF EXISTS patient_audit_logs_insert ON public.patient_audit_logs;
DROP POLICY IF EXISTS patient_notes_insert ON public.patient_notes;
DROP POLICY IF EXISTS patient_notes_modify ON public.patient_notes;

-- 3. profiles holds role / verified / lab_id: a self-update policy would let
--    anyone make themselves admin. It isn't created in these migrations, so
--    whatever policies it has came from the dashboard: replace them all with
--    read-own-row only.
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
DO $$
DECLARE p record;
BEGIN
  FOR p IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'profiles' LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.profiles', p.policyname);
  END LOOP;
END $$;
CREATE POLICY profiles_select_own ON public.profiles
  FOR SELECT TO authenticated
  USING (id = auth.uid());
