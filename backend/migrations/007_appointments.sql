-- Patient appointments
-- Idempotent — safe to re-run in Supabase SQL Editor.

CREATE TABLE IF NOT EXISTS public.appointments (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id     UUID NOT NULL REFERENCES public.patients (id) ON DELETE CASCADE,
  created_by     UUID NOT NULL REFERENCES public.profiles (id) ON DELETE RESTRICT,
  description    TEXT NOT NULL DEFAULT '',
  start_time     TIMESTAMPTZ NOT NULL,
  end_time       TIMESTAMPTZ NOT NULL,
  status         TEXT NOT NULL DEFAULT 'scheduled'
                 CHECK (status IN ('scheduled', 'confirmed', 'completed', 'cancelled', 'no_show')),
  reminder_sent  BOOLEAN NOT NULL DEFAULT FALSE,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT appointments_time_range CHECK (end_time > start_time)
);

CREATE INDEX IF NOT EXISTS idx_appointments_patient
  ON public.appointments (patient_id, start_time ASC);

CREATE INDEX IF NOT EXISTS idx_appointments_created_by
  ON public.appointments (created_by, start_time ASC);

CREATE INDEX IF NOT EXISTS idx_appointments_status_start
  ON public.appointments (status, start_time);

ALTER TABLE public.appointments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS appointments_select_own_or_shared ON public.appointments;
CREATE POLICY appointments_select_own_or_shared
  ON public.appointments
  FOR SELECT
  TO authenticated
  USING (
    created_by = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.patients p
      WHERE p.id = appointments.patient_id
        AND p.deleted = FALSE
        AND (
          p.created_by = auth.uid()
          OR EXISTS (
            SELECT 1 FROM public.patient_access a
            WHERE a.patient_id = p.id
              AND a.user_id = auth.uid()
              AND a.status = 'approved'
          )
        )
    )
  );
