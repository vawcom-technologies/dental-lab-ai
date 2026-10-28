-- Dentists no longer request access to each other's patients; only the lab
-- decides sharing tickets (ticket_lab_id). Close the old owner-approval
-- requests left from before the lab rules, so nothing waits on a dentist.
UPDATE public.patient_access
   SET status = 'rejected'
 WHERE status = 'pending'
   AND ticket_lab_id IS NULL;
