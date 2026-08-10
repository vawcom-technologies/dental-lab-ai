-- Patient media assets: 3D scans, shade detections, smile previews
-- Idempotent — safe to re-run in Supabase SQL Editor.

-- ── patient_scans ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.patient_scans (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id   UUID NOT NULL REFERENCES public.patients (id) ON DELETE CASCADE,
  uploaded_by  UUID NOT NULL REFERENCES public.profiles (id) ON DELETE RESTRICT,
  file_key     TEXT NOT NULL,
  file_url     TEXT NOT NULL,
  file_name    TEXT NOT NULL DEFAULT '',
  format       TEXT NOT NULL DEFAULT '',
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_patient_scans_patient
  ON public.patient_scans (patient_id, created_at DESC);

-- ── shade_detections ─────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.shade_detections (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id   UUID NOT NULL REFERENCES public.patients (id) ON DELETE CASCADE,
  uploaded_by  UUID NOT NULL REFERENCES public.profiles (id) ON DELETE RESTRICT,
  file_key     TEXT NOT NULL,
  file_url     TEXT NOT NULL,
  file_name    TEXT NOT NULL DEFAULT '',
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_shade_detections_patient
  ON public.shade_detections (patient_id, created_at DESC);

-- ── smile_previews ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.smile_previews (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id   UUID NOT NULL REFERENCES public.patients (id) ON DELETE CASCADE,
  uploaded_by  UUID NOT NULL REFERENCES public.profiles (id) ON DELETE RESTRICT,
  file_key     TEXT NOT NULL,
  file_url     TEXT NOT NULL,
  file_name    TEXT NOT NULL DEFAULT '',
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_smile_previews_patient
  ON public.smile_previews (patient_id, created_at DESC);

-- ── RLS (backend uses service-role; policies protect direct PostgREST) ───────
ALTER TABLE public.patient_scans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shade_detections ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.smile_previews ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS patient_scans_select_own_or_shared ON public.patient_scans;
CREATE POLICY patient_scans_select_own_or_shared
  ON public.patient_scans
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.patients p
      WHERE p.id = patient_scans.patient_id
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

DROP POLICY IF EXISTS shade_detections_select_own_or_shared ON public.shade_detections;
CREATE POLICY shade_detections_select_own_or_shared
  ON public.shade_detections
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.patients p
      WHERE p.id = shade_detections.patient_id
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

DROP POLICY IF EXISTS smile_previews_select_own_or_shared ON public.smile_previews;
CREATE POLICY smile_previews_select_own_or_shared
  ON public.smile_previews
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.patients p
      WHERE p.id = smile_previews.patient_id
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
