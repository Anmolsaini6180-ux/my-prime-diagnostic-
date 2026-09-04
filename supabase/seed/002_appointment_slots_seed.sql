-- ============================================================
-- Seed: 002_appointment_slots_seed
-- ============================================================
-- The exact 8 time windows from index-1.html's #mbkSlot dropdown
-- (line ~3715-3722), now a real reference table instead of hardcoded
-- <option> tags. default_capacity=12 is a placeholder pending the
-- business's real per-slot operational capacity — see DATABASE.md.
-- ============================================================
insert into public.appointment_slots (label, start_time, end_time, sort_order, default_capacity) values
  ('07:00 - 08:00 AM', '07:00', '08:00', 1, 12),
  ('08:00 - 09:00 AM', '08:00', '09:00', 2, 12),
  ('09:00 - 10:00 AM', '09:00', '10:00', 3, 12),
  ('10:00 - 11:00 AM', '10:00', '11:00', 4, 12),
  ('11:00 AM - 12:00 PM', '11:00', '12:00', 5, 12),
  ('02:00 - 03:00 PM', '14:00', '15:00', 6, 12),
  ('03:00 - 04:00 PM', '15:00', '16:00', 7, 12),
  ('04:00 - 05:00 PM', '16:00', '17:00', 8, 12)
on conflict (label) do nothing;
