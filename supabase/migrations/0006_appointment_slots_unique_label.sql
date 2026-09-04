-- ============================================================
-- Migration: 0006_appointment_slots_unique_label
-- ============================================================
-- Caught while writing the slots seed file: appointment_slots had no
-- unique constraint on label, so two slots could accidentally get the
-- same display label, and the seed file's `on conflict` couldn't
-- target anything meaningful. Fixed before it caused a real duplicate.
-- ============================================================
alter table public.appointment_slots add constraint appointment_slots_label_key unique (label);
