-- ============================================================
-- Migration: 0011b_drop_old_booking_rpc_overloads
-- ============================================================
-- Same lesson as 0010b, caught again via get_advisors immediately
-- after 0011: adding p_override_amount/p_amount_received (and
-- p_amount_received on admin_update_booking) as new trailing
-- parameters made Postgres create OVERLOADS, not replacements --
-- CREATE OR REPLACE only replaces a function with the IDENTICAL
-- parameter list (same count and types). The OLD-arity versions of
-- both functions were still live and still GRANTed to authenticated
-- from migration 0010, sitting alongside the new ones. This drops
-- them outright, leaving exactly one create_booking and exactly one
-- admin_update_booking in existence.
-- ============================================================

drop function if exists public.create_booking(
  text, uuid, text, text, text, date, text, text, jsonb, date, uuid, text, text, text, uuid, text
);

drop function if exists public.admin_update_booking(
  uuid, text, text, text, date, text, text, jsonb, date, uuid, text, text, uuid, text
);
